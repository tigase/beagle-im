//
// MessageEventHandler.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift
import TigaseSwiftOMEMO
import os
import Combine

class MessageEventHandler: XmppServiceEventHandler {

    public static let instance = MessageEventHandler();
    
    public static let OMEMO_AVAILABILITY_CHANGED = Notification.Name(rawValue: "OMEMOAvailabilityChanged");

    static func prepareBody(message: Message, forAccount account: BareJID) -> (String?, MessageEncryption, String?) {
        var encryption: MessageEncryption = .none;
        var fingerprint: String? = nil;

        guard (message.type ?? .chat) != .error else {
            guard let body = message.body else {
                if let delivery = message.messageDelivery {
                    switch delivery {
                    case .received(_):
                        // if our message delivery confirmation is not delivered just drop this info
                        return (nil, encryption, nil);
                    default:
                        break;
                    }
                }
                return (message.to?.resource == nil ? nil : "", encryption, nil);
            }
            return (body, encryption, nil);
        }

        var encryptionErrorBody: String?;
        if let omemoModule: OMEMOModule = XmppService.instance.getClient(for: account)?.module(.omemo) {
            switch omemoModule.decode(message: message) {
            case .successMessage(_, let keyFingerprint):
                encryption = .decrypted;
                fingerprint = keyFingerprint
                break;
            case .successTransportKey(_, _):
                print("got transport key with key and iv!");
            case .failure(let error):
                switch error {
                case .invalidMessage:
                    encryptionErrorBody = "Message was not encrypted for this device.";
                    encryption = .notForThisDevice;
                case .duplicateMessage:
                    // message is a duplicate and was processed before
                    return (nil, .none, nil);
                case .notEncrypted:
                    encryption = .none;
                default:
                    encryptionErrorBody = "Message decryption failed!";
                    encryption = .decryptionFailed;
                }
                break;
            }
        }

        guard let body = message.body ?? message.oob ?? encryptionErrorBody else {
            return (nil, encryption, nil);
        }
        return (body, encryption, fingerprint);
    }

    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE, MessageDeliveryReceiptsModule.ReceiptEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, MessageArchiveManagementModule.ArchivedMessageReceivedEvent.TYPE, OMEMOModule.AvailabilityChangedEvent.TYPE];

    private init() {
    }

    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.$state.sink(receiveValue: { [weak client] state in
            guard case .connected(let resumed) = state, !resumed, let client = client else {
                return;
            }
            MessageEventHandler.scheduleMessageSync(for: client.userBareJid);
            DBChatHistoryStore.instance.loadUnsentMessage(for: client.userBareJid, completionHandler: { (account, messages) in
                DispatchQueue.global(qos: .background).async {
                    for message in messages {
                        var chat = DBChatStore.instance.conversation(for: account, with: message.jid);
                        if chat == nil {
                            switch DBChatStore.instance.createChat(for: client, with: message.jid) {
                            case .created(let newChat):
                                chat = newChat;
                            case .found(let existingChat):
                                chat = existingChat;
                            case .none:
                                return;
                            }
                        }
                        if let dbChat = chat as? Chat {
                            dbChat.resendMessage(content: message.data, isAttachment: message.type == .attachment, encryption: message.encryption != .none ? .omemo : .none, stanzaId: message.correctionStanzaId ?? message.stanzaId, correctedMessageOriginId: message.correctionStanzaId == nil ? nil : message.stanzaId);
                        }

                    }
                }
            });
        }).store(in: &cancellables);
        client.module(.mam).$availableVersions.sink(receiveValue: { [weak client] versions in
            guard !versions.isEmpty, let client = client else {
                return;
            }
            MessageEventHandler.syncMessagesScheduled(for: client);
        }).store(in: &cancellables);
        client.module(.messageCarbons).$isAvailable.filter({ $0 }).sink(receiveValue: { [weak client] _ in
            client?.module(.messageCarbons).enable();
        }).store(in: &cancellables);
    }

    func handle(event: Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            guard e.message.from != nil else {
                return;
            }

            DBChatHistoryStore.instance.append(for: e.chat as! Conversation, message: e.message, source: .stream);
        case let e as MessageDeliveryReceiptsModule.ReceiptEvent:
            guard let from = e.message.from?.bareJid, let account = e.sessionObject.userBareJid else {
                return;
            }
            
            guard let conversation = DBChatStore.instance.conversation(for: account, with: from) else {
                return;
            }

            DBChatHistoryStore.instance.updateItemState(for: conversation, stanzaId: e.messageId, from: .outgoing, to: .outgoing_delivered);
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from?.bareJid, let to = e.message.to?.bareJid else {
                return;
            }
            
            let jid = e.action == MessageCarbonsModule.Action.received ? from : to;
            let conversation: ConversationKey = DBChatStore.instance.conversation(for: account, with: jid) ?? ConversationKeyItem(account: account, jid: jid);
                        
            DBChatHistoryStore.instance.append(for: conversation, message: e.message, source: .carbons(action: e.action));
        case let e as MessageArchiveManagementModule.ArchivedMessageReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from?.bareJid, let to = e.message.to?.bareJid else {
                return;
            }
            
            let jid = from != account ? from : to;
            
            let conversation: ConversationKey = DBChatStore.instance.conversation(for: account, with: jid) ?? ConversationKeyItem(account: account, jid: jid);
            
            DBChatHistoryStore.instance.append(for: conversation, message: e.message, source: .archive(source: e.source, version: e.version, messageId: e.messageId, timestamp: e.timestamp));
        case let e as OMEMOModule.AvailabilityChangedEvent:
            NotificationCenter.default.post(name: MessageEventHandler.OMEMO_AVAILABILITY_CHANGED, object: e);
        default:
            break;
        }
    }
    

    static func calculateDirection(for conversation: ConversationKey, direction: MessageDirection, sender: ConversationEntrySender) -> MessageDirection {
        switch sender {
        case .buddy(_):
            return direction;
        case .participant(let id, _, let jid):
            if let senderJid = jid {
                return senderJid == conversation.account ? .outgoing : .incoming;
            }
            if let channel = conversation as? Channel {
                return channel.participantId == id ? .outgoing : .incoming;
            }
            // we were not able to determine if we were senders or not.
            return direction;
        case .occupant(let nickname, let jid):
            if let senderJid = jid {
                return senderJid == conversation.account ? .outgoing : .incoming;
            }
            if let room = conversation as? Room {
                return room.nickname == nickname ? .outgoing : .incoming;
            }
            // we were not able to determine if we were senders or not.
            return direction;
        }
    }

    static func calculateState(direction: MessageDirection, message: Message, isFromArchive archived: Bool, isMuc: Bool) -> ConversationEntryState {
        let error = message.type == StanzaType.error;
        let unread = (!archived) || isMuc;
        if direction == .incoming {
            if error {
                return unread ? .incoming_error_unread(errorMessage: message.errorText ?? message.errorCondition?.rawValue) : .incoming_error(errorMessage: message.errorText ?? message.errorCondition?.rawValue);
            }
            return unread ? .incoming_unread : .incoming;
        } else {
            if error {
                return unread ? .outgoing_error_unread(errorMessage: message.errorText ?? message.errorCondition?.rawValue) : .outgoing_error(errorMessage: message.errorText ?? message.errorCondition?.rawValue);
            }
            return .outgoing;
        }
    }
    
    private static var syncSinceQueue = DispatchQueue(label: "syncSinceQueue");
    private static var syncSince: [BareJID: Date] = [:];
    
    static func scheduleMessageSync(for account: BareJID) {
        if AccountSettings.messageSyncAuto(account).bool() {
            var syncPeriod = AccountSettings.messageSyncPeriod(account).double();
            if syncPeriod == 0 {
                syncPeriod = 72;
            }
            let syncMessagesSince = max(DBChatHistoryStore.instance.lastMessageTimestamp(for: account), Date(timeIntervalSinceNow: -1 * syncPeriod * 3600));
            // use last "received" stable stanza id for account MAM archive in case of MAM:2?
            syncSinceQueue.async {
                self.syncSince[account] = syncMessagesSince;
            }
        } else {
            syncSinceQueue.async {
                syncSince.removeValue(forKey: account);
                DBChatHistorySyncStore.instance.removeSyncPeriods(forAccount: account);
            }
        }
    }
    
    static func syncMessagesScheduled(for client: XMPPClient) {
        syncSinceQueue.async {
            guard AccountSettings.messageSyncAuto(client.userBareJid).bool(), let syncMessagesSince = syncSince[client.userBareJid] else {
                return;
            }
            syncMessages(for: client, since: syncMessagesSince);
        }
    }
    
    static func syncMessages(for client: XMPPClient, version: MessageArchiveManagementModule.Version? = nil, componentJID: JID? = nil, since: Date, rsmQuery: RSM.Query? = nil) {
        let period = DBChatHistorySyncStore.Period(account: client.userBareJid, component: componentJID?.bareJid, from: since, after: nil);
        DBChatHistorySyncStore.instance.addSyncPeriod(period);
        
        syncMessagePeriods(for: client, version: version, componentJID: componentJID?.bareJid)
    }
    
    static func syncMessagePeriods(for client: XMPPClient, version: MessageArchiveManagementModule.Version? = nil, componentJID jid: BareJID? = nil) {
        guard let first = DBChatHistorySyncStore.instance.loadSyncPeriods(forAccount: client.userBareJid, component: jid).first else {
            NotificationManager.instance.syncCompleted(for: client.userBareJid, with: jid)
            return;
        }

        NotificationManager.instance.syncStarted(for: client.userBareJid, with: jid);
        
        syncSinceQueue.async {
            syncMessages(for: client, period: first, version: version);
        }
    }
    
    static func syncMessages(for client: XMPPClient, period: DBChatHistorySyncStore.Period, version: MessageArchiveManagementModule.Version? = nil, rsmQuery: RSM.Query? = nil, retry: Int = 3) {
        let start = Date();
        let queryId = UUID().uuidString;
        client.module(.mam).queryItems(version: version, componentJid: period.component == nil ? nil : JID(period.component!), start: period.from, end: period.to, queryId: queryId, rsm: rsmQuery ?? RSM.Query(after: period.after, max: 150), completionHandler: { [weak client] result in
            switch result {
            case .success(let response):
                if response.complete || response.rsm == nil {
                    DBChatHistorySyncStore.instance.removeSyncPerod(period);
                    if let client = client {
                        syncMessagePeriods(for: client, version: version, componentJID: period.component);
                    }
                } else {
                    if let last = response.rsm?.last, UUID(uuidString: last) != nil {
                        DBChatHistorySyncStore.instance.updatePeriod(period, after: last);
                    }
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                        guard let client = client else {
                            return;
                        }
                        self.syncMessages(for: client, period: period, version: version, rsmQuery: response.rsm?.next(150));
                    }
                }
                os_log("for account %s fetch for component %s with id %s executed in %f s", log: .chatHistorySync, type: .debug, period.account.stringValue, period.component?.stringValue ?? "nil", queryId, Date().timeIntervalSince(start));
            case .failure(let error):
                guard client?.state ?? .disconnected() == .connected(), retry > 0 && error != .feature_not_implemented else {
                    os_log("for account %s fetch for component %s with id %s could not synchronize message archive for: %{public}s", log: .chatHistorySync, type: .debug, period.account.stringValue, period.component?.stringValue ?? "nil", queryId, error.description);
                    NotificationManager.instance.syncCompleted(for: period.account, with: period.component)
                    return;
                }
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                    guard let client = client else {
                        return;
                    }
                    self.syncMessages(for: client, period: period, version: version, rsmQuery: rsmQuery, retry: retry - 1);
                }
            }
        });
    }

    static func extractRealAuthor(from message: Message, for conversation: ConversationKey) -> (ConversationEntrySender,ConversationEntryRecipient)? {
        if message.type == .groupchat {
            if let mix = message.mix {
                if let id = message.from?.resource, let nickname = mix.nickname {
                    return (.participant(id: id, nickname: nickname, jid: mix.jid), .none);
                }
                // invalid sender? what should we do?
                return nil;
            } else {
                // in this case it is most likely MUC groupchat message..
                if let nickname = message.from?.resource {
                    return (.occupant(nickname: nickname, jid: nil), .none);
                }
                // invalid sender? what should we do?
                return nil;
            }
        } else {
            // this can be 1-1 message from MUC..
            if let room = conversation as? Room, message.findChild(name: "x", xmlns: "http://jabber.org/protocol/muc#user") != nil {
                if conversation.account == message.from?.bareJid {
                    // outgoing message!
                    if let recipientNickname = message.to?.resource {
                        return (.occupant(nickname: room.nickname, jid: nil), .occupant(nickname: recipientNickname));
                    }
                } else {
                    // incoming message!
                    if let senderNickname = message.from?.resource {
                        return (.occupant(nickname: senderNickname, jid: nil), .occupant(nickname: room.nickname));
                    }
                }
                // invalid sender? what should we do?
                return nil;
            }
        }
        return (conversation.account == message.from?.bareJid ? .me(conversation: conversation) : .buddy(conversation: conversation), .none);
    }
    
    static func itemType(fromMessage message: Message) -> ItemType {
        if let oob = message.oob {
            if (message.body == nil || oob == message.body), URL(string: oob) != nil {
                return .attachment;
            }
        }
        return .message;
    }
}
