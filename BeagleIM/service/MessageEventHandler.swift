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

class MessageEventHandler: XmppServiceEventHandler {
    
    public static let OMEMO_AVAILABILITY_CHANGED = Notification.Name(rawValue: "OMEMOAvailabilityChanged");
    
    static func prepareBody(message: Message, forAccount account: BareJID) -> (String?, MessageEncryption, String?) {
        var encryption: MessageEncryption = .none;
        var fingerprint: String? = nil;
        
        if let omemoModule: OMEMOModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(OMEMOModule.ID) {
            switch omemoModule.decode(message: message) {
            case .successMessage(let decodedMessage, let keyFingerprint):
                encryption = .decrypted;
                fingerprint = keyFingerprint
                break;
            case .successTransportKey(let key, let iv):
                print("got transport key with key and iv!");
            case .failure(let error):
                switch error {
                case .invalidMessage:
                    encryption = .notForThisDevice;
                case .duplicateMessage:
                    if let from = message.from?.bareJid, DBChatHistoryStore.instance.checkItemAlreadyAdded(for: account, with: from, authorNickname: nil, type: .message, timestamp: message.delay?.stamp ?? Date(), direction: account == from ? .outgoing : .incoming, stanzaId: message.getAttribute("id"), data: nil) {
                        return (nil, .none, nil);
                    }
                default:
                    encryption = .decryptionFailed;
                }
                break;
            }
        }
        
        guard let body = message.body ?? message.oob else {
            return (nil, encryption, nil);
        }
        guard (message.type ?? .chat) != .error else {
            guard let error = message.errorCondition else {
                return ("Error: Unknown error\n------\n\(body)", encryption, nil);
            }
            return ("Error: \(message.errorText ?? error.rawValue)\n------\n\(body)", encryption, nil);
        }
        return (body, encryption, fingerprint);
    }
    
    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE, MessageDeliveryReceiptsModule.ReceiptEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, MessageArchiveManagementModule.ArchivedMessageReceivedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, OMEMOModule.AvailabilityChangedEvent.TYPE];
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.CHANGED, object: nil);
    }
    
    @objc func settingsChanged(_ notification: Notification) {
        guard let setting = notification.object as? Settings else {
            return;
        }
        
        switch setting {
        case .enableMessageCarbons:
            XmppService.instance.clients.values.filter { (client) -> Bool in
                return client.state == .connected
                }.forEach { client in
                    guard let mcModule: MessageCarbonsModule = client.modulesManager.getModule(MessageCarbonsModule.ID), mcModule.isAvailable else {
                        return;
                    }
                    if setting.bool() {
                        mcModule.enable();
                    } else {
                        mcModule.disable();
                    }
            }
        default:
            break;
        }
    }
    
    func handle(event: Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            guard let from = e.message.from, let account = e.sessionObject.userBareJid else {
                return;
            }
            if e.message.findChild(name: "encrypted") != nil {
                return;
            }
            
            let (body, encryption, fingerprint) = MessageEventHandler.prepareBody(message: e.message, forAccount: account)
            guard body != nil else {
                if (e.message.type ?? .normal) != .error, let chatState = e.message.chatState, e.message.delay == nil {
                    DBChatHistoryStore.instance.process(chatState: chatState, for: account, with: from.bareJid);
                }
                return;
            }
            
            let timestamp = e.message.delay?.stamp ?? Date();
            let state: MessageState = ((e.message.type ?? .chat) == .error) ? .incoming_error_unread : .incoming_unread;
            DBChatHistoryStore.instance.appendItem(for: account, with: from.bareJid, state: state, type: .message, timestamp: timestamp, stanzaId: e.message.id, data: body!, chatState: e.message.chatState, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, completionHandler: nil);
        case let e as MessageDeliveryReceiptsModule.ReceiptEvent:
            guard let from = e.message.from?.bareJid, let account = e.sessionObject.userBareJid else {
                return;
            }
            DBChatHistoryStore.instance.updateItemState(for: account, with: from, stanzaId: e.messageId, from: .outgoing, to: .outgoing_delivered);
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            let account = e.sessionObject.userBareJid!;
            if AccountSettings.messageSyncAuto(account).bool() {
                var syncPeriod = AccountSettings.messageSyncPeriod(account).double();
                if syncPeriod == 0 {
                    syncPeriod = 72;
                }
                let syncMessagesSince = max(DBChatStore.instance.lastMessageTimestamp(for: account), Date(timeIntervalSinceNow: -1 * syncPeriod * 3600));
                
                syncMessages(for: account, since: syncMessagesSince);
            }
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            guard Settings.enableMessageCarbons.bool() else {
                return;
            }
            guard e.features.contains(MessageCarbonsModule.MC_XMLNS) else {
                return;
            }
            guard let mcModule: MessageCarbonsModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) else {
                return;
            }
            mcModule.enable();
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from, let to = e.message.to else {
                return;
            }
            let (body, encryption,fingerprint) = MessageEventHandler.prepareBody(message: e.message, forAccount: account);
            guard body != nil else {
                return;
            }
            let jid = account == from.bareJid ? to.bareJid : from.bareJid;
            let timestamp = e.message.delay?.stamp ?? Date();
            let state: MessageState = calculateState(direction: account == from.bareJid ? .outgoing : .incoming, error: ((e.message.type ?? .chat) == .error), unread: !Settings.markMessageCarbonsAsRead.bool());
            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, type: .message, timestamp: timestamp, stanzaId: e.message.id, data: body!, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, completionHandler: nil);
        case let e as MessageArchiveManagementModule.ArchivedMessageReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from, let to = e.message.to else {
                return;
            }
            let (body, encryption, fingerprint) = MessageEventHandler.prepareBody(message: e.message, forAccount: account)
            guard body != nil else {
                return;
            }
            let jid = account == from.bareJid ? to.bareJid : from.bareJid;
            let timestamp = e.timestamp!;
            let state: MessageState = calculateState(direction: account == from.bareJid ? .outgoing : .incoming, error: ((e.message.type ?? .chat) == .error), unread: false);
            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, type: .message, timestamp: timestamp, stanzaId: e.message.id, data: body!, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, completionHandler: nil);
        case let e as OMEMOModule.AvailabilityChangedEvent:
            NotificationCenter.default.post(name: MessageEventHandler.OMEMO_AVAILABILITY_CHANGED, object: e);
        default:
            break;
        }
    }
    
    fileprivate func calculateState(direction: MessageDirection, error: Bool, unread: Bool) -> MessageState {
        if direction == .incoming {
            if error {
                return unread ? .incoming_error_unread : .incoming_error;
            }
            return unread ? .incoming_unread : .incoming;
        } else {
            if error {
                return unread ? .outgoing_error_unread : .outgoing_error;
            }
            return .outgoing;
        }
    }

    fileprivate func syncMessages(for account: BareJID, since: Date, rsmQuery: RSM.Query? = nil) {
        guard let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageArchiveManagementModule.ID) else {
            return;
        }
        
        let queryId = UUID().uuidString;
        mamModule.queryItems(start: since, queryId: queryId, rsm: rsmQuery ?? RSM.Query(lastItems: 100), onSuccess: { (queryid,complete,rsmResponse) in
            if rsmResponse != nil && rsmResponse!.index != 0 && rsmResponse?.first != nil {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
                    self.syncMessages(for: account, since: since, rsmQuery: rsmResponse?.previous(100));
                }
            }
        }) { (error, stanza) in
            print("could not synchronize message archive for:", account, "got", error as Any);
        }
    }
}
