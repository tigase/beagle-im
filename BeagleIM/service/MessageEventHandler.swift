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

        guard (message.type ?? .chat) != .error else {
            guard let body = message.body else {
                return (message.to?.resource == nil ? nil : "", encryption, nil);
            }
            return (body, encryption, nil);
        }

        var encryptionErrorBody: String?;
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

    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE, MessageDeliveryReceiptsModule.ReceiptEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, DiscoveryModule.AccountFeaturesReceivedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE, MessageArchiveManagementModule.ArchivedMessageReceivedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, OMEMOModule.AvailabilityChangedEvent.TYPE];

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

            DBChatHistoryStore.instance.append(for: account, message: e.message, source: .stream);
        case let e as MessageDeliveryReceiptsModule.ReceiptEvent:
            guard let from = e.message.from?.bareJid, let account = e.sessionObject.userBareJid else {
                return;
            }
            DBChatHistoryStore.instance.updateItemState(for: account, with: from, stanzaId: e.messageId, from: .outgoing, to: .outgoing_delivered);
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            let account = e.sessionObject.userBareJid!;
            MessageEventHandler.scheduleMessageSync(for: account);
            DBChatHistoryStore.instance.loadUnsentMessage(for: account, completionHandler: { (account, jid, data, stanzaId, encryption, type) in

                var chat = DBChatStore.instance.getChat(for: account, with: jid);
                if chat == nil {
                    switch DBChatStore.instance.createChat(for: account, jid: JID(jid), thread: nil) {
                    case .success(let newChat):
                        chat = newChat;
                    case .failure(let err):
                        return;
                    }
                }

                if let dbChat = chat as? DBChatStore.DBChat {
                    if type == .message {
                        MessageEventHandler.sendMessage(chat: dbChat, body: data, url: nil, stanzaId: stanzaId);
                    } else if type == .attachment {
                        MessageEventHandler.sendMessage(chat: dbChat, body: data, url: data, stanzaId: stanzaId);
                    }
                }
            });
        case let e as DiscoveryModule.AccountFeaturesReceivedEvent:
            if let account = e.sessionObject.userBareJid, let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageArchiveManagementModule.ID), mamModule.isAvailable {
                MessageEventHandler.syncMessagesScheduled(for: account);
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
            
            DBChatHistoryStore.instance.append(for: account, message: e.message, source: .carbons(action: e.action));
        case let e as MessageArchiveManagementModule.ArchivedMessageReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from, let to = e.message.to else {
                return;
            }
            
            DBChatHistoryStore.instance.append(for: account, message: e.message, source: .archive(source: e.source, version: e.version, messageId: e.messageId, timestamp: e.timestamp));
        case let e as OMEMOModule.AvailabilityChangedEvent:
            NotificationCenter.default.post(name: MessageEventHandler.OMEMO_AVAILABILITY_CHANGED, object: e);
        default:
            break;
        }
    }
    
    static func sendAttachment(chat: DBChatStore.DBChat, originalUrl: URL?, uploadedUrl: String, appendix: ChatAttachmentAppendix, completionHandler: (()->Void)?) {
        
        self.sendMessage(chat: chat, body: nil, url: uploadedUrl, chatAttachmentAppendix: appendix, messageStored: { (msgId) in
            DispatchQueue.main.async {
                if originalUrl != nil {
                    _ = DownloadStore.instance.store(originalUrl!, filename: originalUrl!.lastPathComponent, with: "\(msgId)");
                }
                completionHandler?();
            }
        })
    }

    static func sendMessage(chat: DBChatStore.DBChat, body: String?, url: String?, encrypted: ChatEncryption? = nil, stanzaId: String? = nil, chatAttachmentAppendix: ChatAttachmentAppendix? = nil, messageStored: ((Int)->Void)? = nil) {
            guard let msg = body ?? url else {
                return;
            }

            let encryption = encrypted ?? chat.options.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!;

            let message = chat.createMessage(msg);
            message.id = stanzaId ?? UUID().uuidString;
            if let id = message.id, UUID(uuidString: id) != nil {
                message.originId = id;
            }
            message.messageDelivery = .request;

            let account = chat.account;
            let jid = chat.jid.bareJid;

            switch encryption {
            case .omemo:
                if stanzaId == nil {
                    let fingerprint = DBOMEMOStore.instance.identityFingerprint(forAccount: account, andAddress: SignalAddress(name: account.stringValue, deviceId: Int32(bitPattern: DBOMEMOStore.instance.localRegistrationId(forAccount: account)!)));
                    DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing_unsent, authorNickname: nil, authorJid: nil, recipientNickname: nil, participantId: nil, type: url == nil ? .message : .attachment, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: msg, encryption: .decrypted, encryptionFingerprint: fingerprint, appendix: chatAttachmentAppendix, linkPreviewAction: .none, completionHandler: messageStored);
                }
                XmppService.instance.tasksQueue.schedule(for: jid, task: { (completionHandler) in
                    sendEncryptedMessage(message, from: account, completionHandler: { result in
                        switch result {
                        case .success(_):
                            let timestamp = Date();
                            DBChatHistoryStore.instance.updateItemState(for: account, with: jid, stanzaId: message.id!, from: .outgoing_unsent, to: .outgoing, withTimestamp: timestamp);
                            
                            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing, authorNickname: nil, authorJid: nil, recipientNickname: nil, participantId: nil, type: url == nil ? .message : .attachment, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: msg, encryption: .decrypted, encryptionFingerprint: nil, appendix: chatAttachmentAppendix, linkPreviewAction: .only, completionHandler: messageStored);
                        case .failure(let err):
                            let condition = (err is ErrorCondition) ? (err as? ErrorCondition) : nil;
                            guard condition == nil || condition! != .gone else {
                                completionHandler();
                                return;
                            }

                            var errorMessage: String? = nil;
                            if let encryptionError = err as? SignalError {
                                switch encryptionError {
                                case .noSession:
                                    errorMessage = "There is no trusted device to send message to";
                                default:
                                    errorMessage = "It was not possible to send encrypted message due to encryption error";
                                }
                            }

                            DBChatHistoryStore.instance.markOutgoingAsError(for: account, with: jid, stanzaId: message.id!, errorCondition: .undefined_condition, errorMessage: errorMessage);
                        }
                        completionHandler();
                    });
                });
            case .none:
                message.oob = url;
                let type: ItemType = url == nil ? .message : .attachment;
                if stanzaId == nil {
                    DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing_unsent, authorNickname: nil, authorJid: nil, recipientNickname: nil, participantId: nil, type: type, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: msg, encryption: .none, encryptionFingerprint: nil, appendix: chatAttachmentAppendix, linkPreviewAction: .none, completionHandler: messageStored);
                }
                XmppService.instance.tasksQueue.schedule(for: jid, task: { (completionHandler) in
                    sendUnencryptedMessage(message, from: account, completionHandler: { result in
                        switch result {
                        case .success(_):
                            let timestamp = Date();
                            DBChatHistoryStore.instance.updateItemState(for: account, with: jid, stanzaId: message.id!, from: .outgoing_unsent, to: .outgoing, withTimestamp: timestamp);
                            
                            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing, authorNickname: nil, authorJid: nil, recipientNickname: nil, participantId: nil, type: type, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: msg, encryption: .none, encryptionFingerprint: nil, appendix: chatAttachmentAppendix, linkPreviewAction: .only, completionHandler: nil);
                        case .failure(let err):
                            guard let condition = err as? ErrorCondition, condition != .gone else {
                                completionHandler();
                                return;
                            }
                            DBChatHistoryStore.instance.markOutgoingAsError(for: account, with: jid, stanzaId: message.id!, errorCondition: err as? ErrorCondition ?? .undefined_condition, errorMessage: "Could not send message");
                        }
                        completionHandler();
                    });
                });
            }
        }

        fileprivate static func sendUnencryptedMessage(_ message: Message, from account: BareJID, completionHandler: (Result<Void,Error>)->Void) {
            guard let client = XmppService.instance.getClient(for: account), client.state == .connected else {
                completionHandler(.failure(ErrorCondition.gone));
                return;
            }

            client.context.writer?.write(message);

            completionHandler(.success(Void()));
        }


        fileprivate static func sendEncryptedMessage(_ message: Message, from account: BareJID, completionHandler resultHandler: @escaping (Result<Void,Error>)->Void) {

            let msg = message.body!;

            guard let omemoModule: OMEMOModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(OMEMOModule.ID) else {
                DBChatHistoryStore.instance.updateItemState(for: account, with: message.to!.bareJid, stanzaId: message.id!, from: .outgoing_unsent, to: .outgoing_error);
                resultHandler(.failure(ErrorCondition.unexpected_request));
                return;
            }

            guard let client = XmppService.instance.getClient(for: account), client.state == .connected else {
                resultHandler(.failure(ErrorCondition.gone));
                return;
            }

            let jid = message.to!.bareJid;
            let stanzaId = message.id!;

            let completionHandler: ((EncryptionResult<Message, SignalError>)->Void)? = { (result) in
                switch result {
                case .failure(let error):
                    // FIXME: add support for error handling!!
                    resultHandler(.failure(error));
                case .successMessage(let encryptedMessage, let fingerprint):
                    guard let client = XmppService.instance.getClient(for: account) else {
                        resultHandler(.failure(ErrorCondition.gone));
                        return;
                    }
                    client.context.writer?.write(encryptedMessage);
                    resultHandler(.success(Void()));
                }
            };

            omemoModule.encode(message: message, completionHandler: completionHandler!);
        }

    static func calculateDirection(direction: MessageDirection, for account: BareJID, with jid: BareJID, authorNickname: String?, authorJid: BareJID?) -> MessageDirection {
        if let authorJid = authorJid {
            return account == authorJid ? .outgoing : .incoming;
        }
        
        guard let senderNickname = authorNickname else {
            return direction;
        }
        
        if let conversation = DBChatStore.instance.getChat(for: account, with: jid) {
            switch conversation {
            case let channel as DBChatStore.DBChannel:
                return channel.participantId == senderNickname ? .outgoing : .incoming;
            case let room as DBChatStore.DBRoom:
                return room.nickname == senderNickname ? .outgoing : .incoming;
            default:
                break;
            }
        }
        return direction;
    }

    static func calculateState(direction: MessageDirection, isError error: Bool, isUnread unread: Bool) -> MessageState {
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
    
    private static var syncSinceQueue = DispatchQueue(label: "syncSinceQueue");
    private static var syncSince: [BareJID: Date] = [:];
    
    static func scheduleMessageSync(for account: BareJID) {
        if AccountSettings.messageSyncAuto(account).bool() {
            var syncPeriod = AccountSettings.messageSyncPeriod(account).double();
            if syncPeriod == 0 {
                syncPeriod = 72;
            }
            let syncMessagesSince = max(DBChatStore.instance.lastMessageTimestamp(for: account), Date(timeIntervalSinceNow: -1 * syncPeriod * 3600));
            // use last "received" stable stanza id for account MAM archive in case of MAM:2?
            syncSinceQueue.async {
                self.syncSince[account] = syncMessagesSince;
            }
        } else {
            syncSinceQueue.async {
                syncSince.removeValue(forKey: account);
            }
        }
    }
    
    static func syncMessagesScheduled(for account: BareJID) {
        syncSinceQueue.async {
            guard AccountSettings.messageSyncAuto(account).bool(), let syncMessagesSince = syncSince[account] else {
                return;
            }
            syncMessages(for: account, since: syncMessagesSince);
        }
    }

    static func syncMessages(for account: BareJID, since: Date, rsmQuery: RSM.Query? = nil) {
        guard let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageArchiveManagementModule.ID) else {
            return;
        }

        let queryId = UUID().uuidString;
        mamModule.queryItems(start: since, queryId: queryId, rsm: rsmQuery ?? RSM.Query(lastItems: 100), completionHandler: { (result) in
            switch result {
            case .success(let queryId, let completed, let rsmResponse):
                if rsmResponse != nil && rsmResponse!.index != 0 && rsmResponse?.first != nil {
                    DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.2) {
                        self.syncMessages(for: account, since: since, rsmQuery: rsmResponse?.previous(100));
                    }
                }
            case .failure(let errorCondition, let response):
                print("could not synchronize message archive for:", errorCondition, "got", response as Any);
            }
        });
    }
    
    static func extractRealAuthor(from message: Message, for account: BareJID, with jid: JID) -> (String?, BareJID?, String?, String?) {
        if message.type == .groupchat {
            if let mix = message.mix {
                let authorNickname = mix.nickname;
                let authorJid = mix.jid;
                return (authorNickname, authorJid, nil, jid.resource);
            } else {
                // in this case it is most likely MUC groupchat message..
                return (message.from?.resource, nil, nil, nil);
            }
        } else {
            // this can be 1-1 message from MUC..
            if let room = DBChatStore.instance.getChat(for: account, with: jid.bareJid) as? DBChatStore.DBRoom {
                if room.nickname == message.from?.resource {
                    return (message.from?.resource, nil, message.to?.resource, nil);
                } else {
                    return (message.from?.resource, nil, message.to?.resource, nil);
                }
            }
        }
        return (nil, nil, nil, nil);
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
