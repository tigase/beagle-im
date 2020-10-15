//
// DBChatHistoryStore.swift
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

import Foundation
import TigaseSwift

class DBChatHistoryStore {

    static let MESSAGE_NEW = Notification.Name("messageAdded");
    // TODO: it looks like it is not working as expected. We should remove this notification in the future
    static let MESSAGES_MARKED_AS_READ = Notification.Name("messagesMarkedAsRead");
    static let MESSAGE_UPDATED = Notification.Name("messageUpdated");
    static let MESSAGE_REMOVED = Notification.Name("messageRemoved");
    static var instance: DBChatHistoryStore = DBChatHistoryStore.init();

    fileprivate let appendMessageStmt: DBStatement = try! DBConnection.main.prepareStatement("INSERT INTO chat_history (account, jid, timestamp, item_type, data, stanza_id, state, author_nickname, author_jid, recipient_nickname, participant_id, error, encryption, fingerprint, appendix, server_msg_id, remote_msg_id, master_id) VALUES (:account, :jid, :timestamp, :item_type, :data, :stanza_id, :state, :author_nickname, :author_jid, :recipient_nickname, :participant_id, :error, :encryption, :fingerprint, :appendix, :server_msg_id, :remote_msg_id, :master_id)");
    // if server has MAM:2 then use server_msg_id for checking
    // if there is no result, try to match using origin-id/stanza-id (if there is one in a form of UUID) and update server_msg_id if message is found
    // if there is was no origin-id/stanza-id then use old check with timestamp range and all of that..
//    fileprivate let findItemFallback: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND (:data IS NULL OR data = :data) AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (state % 2 == :direction) AND (:author_nickname is null OR author_nickname = :author_nickname) order by timestamp desc");
    fileprivate let findItemByServerMsgId: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND server_msg_id = :server_msg_id");
    fileprivate let findItemByOriginId: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND (stanza_id = :stanza_id OR correction_stanza_id = :stanza_id) AND (:author_nickname IS NULL OR author_nickname = :author_nickname) AND (:participant_id IS NULL OR participant_id = :participant_id) ORDER BY timestamp DESC");
    fileprivate let updateServerMsgId: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET server_msg_id = :server_msg_id WHERE id = :id AND server_msg_id is null");
    fileprivate let markAsReadStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let markAsReadBeforeStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let markMessageAsReadStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE id = :id AND account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let updateItemStateStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = :newState, timestamp = COALESCE(:newTimestamp, timestamp) WHERE id = :id AND (:oldState IS NULL OR state = :oldState)");
    fileprivate let updateItemStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET appendix = :appendix WHERE id = :id");
    fileprivate let markAsErrorStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = :state, error = :error WHERE id = :id");
    fileprivate let countItemsStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid")

    fileprivate let getChatMessagesStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_timestamp FROM chat_history WHERE account = :account AND jid = :jid AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.messageRetracted.rawValue), \(ItemType.attachment.rawValue))) ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");
    fileprivate let getChatMessageWithIdStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_stanza_id, correction_timestamp FROM chat_history WHERE id = :id");
    fileprivate let getChatAttachmentsStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_timestamp FROM chat_history WHERE account = :account AND jid = :jid AND item_type = \(ItemType.attachment.rawValue) ORDER BY timestamp DESC");

    fileprivate let getChatMessagePosition: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)")
    fileprivate let removeChatHistoryStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE account = :account AND (:jid IS NULL OR jid = :jid)");

    fileprivate let searchHistoryStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT chat_history.id as id, chat_history.account as account, chat_history.jid as jid, author_nickname, author_jid, participant_id,  chat_history.timestamp as timestamp, item_type, chat_history.data as data, state, preview, chat_history.encryption as encryption, fingerprint FROM chat_history INNER JOIN chat_history_fts_index ON chat_history.id = chat_history_fts_index.rowid LEFT JOIN chats ON chats.account = chat_history.account AND chats.jid = chat_history.jid WHERE (chats.id IS NOT NULL OR chat_history.author_nickname is NULL) AND chat_history_fts_index MATCH :query AND (:account IS NULL OR chat_history.account = :account) AND (:jid IS NULL OR chat_history.jid = :jid) AND item_type = \(ItemType.message.rawValue) ORDER BY chat_history.timestamp DESC")

    fileprivate let getUnsentMessagesForAccountStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT ch.account as account, ch.jid as jid, ch.item_type as item_type, ch.data as data, ch.stanza_id as stanza_id, ch.encryption as encryption FROM chat_history ch WHERE ch.account = :account AND ch.state = \(MessageState.outgoing_unsent.rawValue) ORDER BY timestamp ASC");

    fileprivate let removeItemStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE id = :id");

    private let correctLastMessageStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET data = :data, state = :state, correction_stanza_id = :correction_stanza_id, correction_timestamp = :correction_timestamp, remote_msg_id = :remote_msg_id, server_msg_id = COALESCE(:server_msg_id, server_msg_id) WHERE id = :id AND (correction_stanza_id IS NULL OR correction_stanza_id <> :correction_stanza_id) AND (correction_timestamp IS NULL OR correction_timestamp < :correction_timestamp)");
    
    private let retractMessageStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET item_type = :item_type, correction_stanza_id = :correction_stanza_id, correction_timestamp = :correction_timestamp, remote_msg_id = :remote_msg_id, server_msg_id = COALESCE(:server_msg_id, server_msg_id) WHERE id = :id AND (correction_stanza_id IS NULL OR correction_stanza_id <> :correction_stanza_id) AND (correction_timestamp IS NULL OR correction_timestamp < :correction_timestamp)");
    
    fileprivate let dispatcher: QueueDispatcher;
    
    static func convertToAttachments() {
        let diskCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("download", isDirectory: true);
        guard FileManager.default.fileExists(atPath: diskCacheUrl.path) else {
            return;
        }
        
        let previewsToConvert = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE preview IS NOT NULL").query(map: { cursor -> Int in
            return cursor["id"]!;
        });
        let convertStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, account, jid, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, preview, stanza_id, correction_timestamp FROM chat_history WHERE id = ?");
        let removePreviewStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET preview = NULL WHERE id = ?");
                        
        previewsToConvert.forEach { id in
            guard let (item, previews, stanzaId) = try! convertStmt.findFirst(id, map: { (cursor) -> (ChatMessage, [String:String], String?)? in
                let account: BareJID = cursor["account"]!;
                let jid: BareJID = cursor["jid"]!;
                let stanzaId: String? = cursor["stanza_id"];
                guard let item = DBChatHistoryStore.instance.itemFrom(cursor: cursor, for: account, with: jid) as? ChatMessage, let previewStr: String = cursor["preview"] else {
                    return nil;
                }
                var previews: [String:String] = [:];
                previewStr.split(separator: "\n").forEach { (line) in
                    let tmp = line.split(separator: "\t").map({String($0)});
                    if (!tmp[1].starts(with: "ERROR")) && (tmp[1] != "NONE") {
                        previews[tmp[0]] = tmp[1];
                    }
                }
                return (item, previews, stanzaId);
            }) else {
                return;
            }
            
            if previews.isEmpty {
                _ = try! removePreviewStmt.update(item.id);
            } else {
                print("converting for:", item.account, "with:", item.jid, "previews:", previews);
                if previews.count == 1 {
                    let isAttachmentOnly = URL(string: item.message) != nil;
                    
                    if isAttachmentOnly {
                        let appendix = ChatAttachmentAppendix();
                        DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .attachment, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, appendix: appendix, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                DBChatHistoryStore.instance.remove(item: item);
                        });
                    } else {
                        if #available(macOS 10.15, *) {
                            DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: previews.keys.first ?? item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                    _ = try! removePreviewStmt.update(item.id);
                            });
                        } else {
                            _ = try! removePreviewStmt.update(item.id);
                        }
                    }
                } else {
                    if #available(macOS 10.15, *) {
                        let group = DispatchGroup();
                        group.enter();
                    
                        group.notify(queue: DispatchQueue.main, execute: {
                            _ = try! removePreviewStmt.update(item.id);
                        })
                    
                        for (url, _) in previews {
                            group.enter();
                            DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: url, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                    group.leave();
                            });
                        }
                        group.leave();
                    } else {
                        _ = try! removePreviewStmt.update(item.id);
                    }
                }
            }
        }
        
        try? FileManager.default.removeItem(at: diskCacheUrl);
    }
    
    
    public init() {
        dispatcher = QueueDispatcher(label: "chat_history_store");
    }

    open func process(chatState: ChatState, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            DBChatStore.instance.process(chatState: chatState, for: account, with: jid);
        }
    }
    
    enum MessageSource {
        case stream
        case archive(source: BareJID, version: MessageArchiveManagementModule.Version, messageId: String, timestamp: Date)
        case carbons(action: MessageCarbonsModule.Action)
    }
    private var enqueuedItems = 0;
    
        
    open func append(for account: BareJID, message: Message, source: MessageSource) {
        let direction: MessageDirection = account == message.from?.bareJid ? .outgoing : .incoming;
        guard let jidFull = direction == .outgoing ? message.to : message.from else {
            // sender jid should always be there..
            return;
        }
        
        let jid = jidFull.bareJid;
        
        let (decryptedBody, encryption, fingerprint) = MessageEventHandler.prepareBody(message: message, forAccount: account);
        let mixInvitation = message.mixInvitation;
        
        var itemType = MessageEventHandler.itemType(fromMessage: message);
        let stanzaId = message.originId ?? message.id;
        var stableIds = message.stanzaId;
        var fromArchive = false;

        var inTimestamp: Date?;

        switch source {
        case .archive(let source, let version, let messageId, let timestamp):
            if version == .MAM2 {
                if stableIds == nil {
                    stableIds = [source: messageId];
                } else {
                    stableIds?[source] = messageId;
                }
            }
            inTimestamp = timestamp;
            fromArchive = true;
        default:
            inTimestamp = message.delay?.stamp;
            break;
        }

        let serverMsgId: String? = stableIds?[account];
        let remoteMsgId: String? = stableIds?[jid];
                
        let (authorNickname, authorJid, recipientNickname, participantId) = MessageEventHandler.extractRealAuthor(from: message, for: account, with: jidFull);
                
        let state = MessageEventHandler.calculateState(direction: MessageEventHandler.calculateDirection(direction: direction, for: account, with: jid, authorNickname: authorNickname, authorJid: authorJid), isError: (message.type ?? .chat) == .error, isFromArchive: fromArchive, isMuc: message.type == .groupchat && message.mix == nil);
        
        var appendix: AppendixProtocol? = nil;
        if itemType == .message, let mixInivation = mixInvitation {
            itemType = .invitation;
            appendix = ChatInvitationAppendix(mixInvitation: mixInivation);
        }
        
        let timestamp = Date(timeIntervalSince1970: Double(Int64((inTimestamp ?? Date()).timeIntervalSince1970 * 1000)) / 1000);

        guard let body = decryptedBody ?? (mixInvitation != nil ? "Invitation" : nil) else {
            if let retractedId = message.messageRetractionId, let originId = stanzaId {
                dispatcher.async {
                    self.retractMessageSync(for: account, with: jid, stanzaId: retractedId, authorNickname: authorNickname, participantId: participantId, retractionStanzaId: originId, retractionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
                }
                return;
            }
            // only if carbon!!
            switch source {
            case .carbons(let action):
                if Settings.markMessageDeliveredToOtherResourceAsRead.bool(), action == .sent, let delivery = message.messageDelivery {
                    switch delivery {
                    case .received(let msgId):
                        DBChatHistoryStore.instance.markAsRead(for: account, with: jid, messageId: msgId);
                        break;
                    default:
                        break;
                    }
                }
                if action == .received {
                    if (message.type ?? .normal) != .error, let chatState = message.chatState, message.delay == nil {
                        DBChatHistoryStore.instance.process(chatState: chatState, for: account, with: jid);
                    }
                }
            default:
                if (message.type ?? .normal) != .error, let chatState = message.chatState, message.delay == nil {
                    DBChatHistoryStore.instance.process(chatState: chatState, for: account, with: jid);
                }
                break;
            }
            return;
        }
        
        dispatcher.async {
            guard !state.isError || stanzaId == nil || !self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId!, errorCondition: message.errorCondition, errorMessage: message.errorText) else {
                return;
            }
            
            if let retractedId = message.messageRetractionId, let originId = stanzaId {
                self.retractMessageSync(for: account, with: jid, stanzaId: retractedId, authorNickname: authorNickname, participantId: participantId, retractionStanzaId: originId, retractionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
                return;
            }
            if let originId = stanzaId, let correctedMessageId = message.lastMessageCorrectionId, self.correctMessageSync(for: account, with: jid, stanzaId: correctedMessageId, authorNickname: authorNickname, participantId: participantId, data: body, correctionStanzaId: originId, correctionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, newState: state) {
                if let chatState = message.chatState {
                    DBChatStore.instance.process(chatState: chatState, for: account, with: jid);
                }
                return;
            }

            if let stableId = serverMsgId, let existingMessageId = self.findItemId(for: account, serverMsgId: stableId) {
                return;
            }
            
            if let originId = stanzaId, let existingMessageId = self.findItemId(for: account, with: jid, originId: originId, authorNickname: authorNickname, participantId: participantId) {
                if let stableId = serverMsgId {
                    _ = try! self.updateServerMsgId.update(["id": existingMessageId, "server_msg_id": serverMsgId] as [String: Any?]);
                }
                return;
            }
                        
            self.appendItemSync(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: itemType, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: body, chatState: message.chatState, errorCondition: message.errorCondition, errorMessage: message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, appendix: appendix, linkPreviewAction: .auto, masterId: nil, completionHandler: nil);
        }
    }
    
    enum LinkPreviewAction {
        case auto
        case none
        case only
    }
    
    private func findItemId(for account: BareJID, serverMsgId: String) -> Int? {
        return try! self.findItemByServerMsgId.findFirst(["server_msg_id": serverMsgId, "account": account] as [String: Any?], map: { cursor -> Int? in
            return cursor["id"];
        });
    }
    
    private func findItemId(for account: BareJID, with jid: BareJID, originId: String, authorNickname: String?, participantId: String?) -> Int? {
        return try! self.findItemByOriginId.findFirst(["stanza_id": originId, "account": account, "jid": jid, "author_nickname": authorNickname, "participant_id": participantId] as [String: Any?], map: { cursor -> Int? in
            return cursor["id"];
        });
    }
    
//    private func findItemId(for account: BareJID, with jid: BareJID, timestamp: Date, direction: MessageDirection, itemType: ItemType, stanzaId: String?, authorNickname: String?, data: String?) -> Int? {
//        let range = stanzaId == nil ? 5.0 : 60.0;
//        let ts_from = timestamp.addingTimeInterval(-60 * range);
//        let ts_to = timestamp.addingTimeInterval(60 * range);
//
//        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": itemType.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];
//
//        return try! self.findItemFallback.findFirst(params, map: { cursor -> Int? in
//            return cursor["id"];
//        })
//    }
        
    private func appendItemSync(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, type: ItemType, timestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState?, errorCondition: ErrorCondition?, errorMessage: String? , encryption: MessageEncryption, encryptionFingerprint: String?, appendix: AppendixProtocol?, linkPreviewAction: LinkPreviewAction, masterId: Int? = nil, completionHandler: ((Int) -> Void)?) {
        var item: ChatViewItemProtocol?;
        if linkPreviewAction != .only {
            let  appendixStr: String? = appendix?.string();

            let params: [String:Any?] = ["account": account, "jid": jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.rawValue, "stanza_id": stanzaId, "author_nickname": authorNickname, "author_jid": authorJid, "recipient_nickname": recipientNickname, "participant_id": participantId, "encryption": encryption.rawValue, "fingerprint": encryptionFingerprint, "error": state.isError ? (errorMessage ?? errorCondition?.rawValue ?? "Unknown error") : nil, "appendix": appendixStr, "server_msg_id": serverMsgId, "remote_msg_id": remoteMsgId, "master_id": masterId];
            guard let msgId = try! self.appendMessageStmt.insert(params) else {
                return;
            }
            completionHandler?(msgId);

            switch type {
            case .message:
                item = ChatMessage(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage, correctionTimestamp: nil);
            case .invitation:
                item = ChatInvitation(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix as! ChatInvitationAppendix, error: errorMessage);
            case .attachment:
                item = ChatAttachment(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: (appendix as? ChatAttachmentAppendix) ?? ChatAttachmentAppendix(), error: errorMessage);
            case .linkPreview:
                if #available(macOS 10.15, *), Settings.linkPreviews.bool() {
                    item = ChatLinkPreview(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
                }
            case .messageRetracted, .attachmentRetracted:
                // nothing to do, as we do not want notifications for that (at least for now and no item of that type would be created in here!
                break;
            }
            if item != nil {
                DBChatStore.instance.newMessage(for: account, with: jid, timestamp: timestamp, itemType: type, message: encryption.message() ?? data, state: state, remoteChatState: state.direction == .incoming ? chatState : nil, senderNickname: authorNickname) {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: item);
                }
            }
        }
        if linkPreviewAction != .none && type == .message, let id = item?.id {
            self.generatePreviews(forItem: id, account: account, jid: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, timestamp: timestamp, data: data);
        }
    }
    
    open func appendItem(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, type: ItemType, timestamp inTimestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState? = nil, errorCondition: ErrorCondition? = nil, errorMessage: String? = nil, encryption: MessageEncryption, encryptionFingerprint: String?, appendix: AppendixProtocol? = nil, linkPreviewAction: LinkPreviewAction, masterId: Int? = nil, completionHandler: ((Int) -> Void)?) {
        
        let timestamp = Date(timeIntervalSince1970: Double(Int64(inTimestamp.timeIntervalSince1970 * 1000)) / 1000);
        dispatcher.async {
            self.appendItemSync(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: type, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: data, chatState: chatState, errorCondition: errorCondition, errorMessage: errorMessage, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, linkPreviewAction: linkPreviewAction, masterId: masterId, completionHandler: completionHandler);
        }
    }

    open func removeHistory(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            let params: [String: Any?] = ["account": account, "jid": jid];
            _ = try! self.removeChatHistoryStmt.update(params);
        }
    }
    
    open func correctMessage(for account: BareJID, with jid: BareJID, stanzaId: String, authorNickname: String?, participantId: String?, data: String, correctionStanzaId: String?, correctionTimestamp: Date, newState: MessageState) {
        let timestamp = Date(timeIntervalSince1970: Double(Int64((correctionTimestamp).timeIntervalSince1970 * 1000)) / 1000);
        dispatcher.async {
            _ = self.correctMessageSync(for: account, with: jid, stanzaId: stanzaId,  authorNickname: authorNickname, participantId: participantId, data: data, correctionStanzaId: correctionStanzaId, correctionTimestamp: timestamp, serverMsgId: nil, remoteMsgId: nil, newState: newState);
        }
    }
    
    private func correctMessageSync(for account: BareJID, with jid: BareJID, stanzaId: String, authorNickname: String?, participantId: String?, data: String, correctionStanzaId: String?, correctionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?, newState: MessageState) -> Bool {
        // we need to check participant-id/sender nickname to make it work correctly
        // moreover, stanza-id should be checked with origin-id for MUC/MIX (not message id)
        // MIX/MUC should send origin-id if they assume to use last message correction!
        if let itemId = self.findItemId(for: account, with: jid, originId: stanzaId, authorNickname: authorNickname, participantId: participantId) {
            if let oldItem: ChatViewItemProtocol = try! self.getChatMessageWithIdStmt.findFirst(["id": itemId] as [String: Any?], map: {
                return self.itemFrom(cursor: $0, for: account, with: jid)
            }) {
                let params: [String: Any?] = ["id": itemId, "data": data, "state": newState.rawValue, "correction_stanza_id": correctionStanzaId, "remote_msg_id": remoteMsgId, "server_msg_id": serverMsgId, "correction_timestamp": correctionTimestamp];
                let updated = try! self.correctLastMessageStmt.update(params);
                if updated > 0 {
                    let newMessageState: MessageState = (oldItem.state.direction == .incoming) ? (oldItem.state.isUnread ? .incoming : (newState.isUnread ? .incoming_unread : .incoming)) : (.outgoing);
                    DBChatStore.instance.newMessage(for: account, with: jid, timestamp: oldItem.timestamp, itemType: .message, message: data, state: newMessageState, completionHandler: {
                        print("chat store state updated with message state:", newMessageState.rawValue, "old state:", oldItem.state.rawValue, "new state:", newState.rawValue);
                    })
                    
                    print("correcing previews for master id:", itemId);
                    self.itemUpdated(withId: itemId, for: account, with: jid);
                    self.previewGenerationDispatcher.async(flags: .barrier, execute: {
                        self.dispatcher.sync {
                            print("removing previews for master id:", itemId);
                            self.removePreviews(idOfRelatedToItem: itemId);
                    
                            if newState != .outgoing_unsent {
                                self.generatePreviews(forItem: itemId, account: account, jid: jid, state: newState);
                            }
                        }
                    })
                }
            }
            return true;
        } else {
            return false;
        }
    }
    
    public func retractMessage(for account: BareJID, with jid: BareJID, stanzaId: String, authorNickname: String?, participantId: String?, retractionStanzaId: String?, retractionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?) {
        dispatcher.async {
            _ = self.retractMessageSync(for: account, with: jid, stanzaId: stanzaId, authorNickname: authorNickname, participantId: participantId, retractionStanzaId: retractionStanzaId, retractionTimestamp: retractionTimestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
        }
    }
    
    private func retractMessageSync(for account: BareJID, with jid: BareJID, stanzaId: String, authorNickname: String?, participantId: String?, retractionStanzaId: String?, retractionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?) -> Bool {
        if let itemId = self.findItemId(for: account, with: jid, originId: stanzaId, authorNickname: authorNickname, participantId: participantId) {
            if let oldItem: ChatViewItemProtocol = try! self.getChatMessageWithIdStmt.findFirst(["id": itemId] as [String: Any?], map: {
                return self.itemFrom(cursor: $0, for: account, with: jid)
            }) {
                var itemType: ItemType = .messageRetracted;
                if oldItem is ChatAttachment {
                    itemType = .attachmentRetracted;
                }
                let params: [String: Any?] = ["id": itemId, "item_type": itemType.rawValue, "correction_stanza_id": retractionStanzaId, "remote_msg_id": remoteMsgId, "server_msg_id": serverMsgId, "correction_timestamp": retractionTimestamp];
                let updated = try! self.retractMessageStmt.update(params);
                if updated > 0 {
                    // what should be sent to "newMessage" how to reatract message from there??
                    let activity: LastChatActivity = DBChatStore.instance.getLastActivity(for: account, jid: jid) ?? .message("", direction: .incoming, sender: nil);
                    DBChatStore.instance.newMessage(for: account, with: jid, timestamp: oldItem.timestamp, lastActivity: activity, state: oldItem.state.direction == .incoming ? .incoming : .outgoing, completionHandler: {
                        print("chat store state updated with message retraction");
                    })
                    if oldItem.state.isUnread {
                        DBChatStore.instance.markAsRead(for: account, with: jid, count: 1);
                    }
                    
                    self.itemUpdated(withId: itemId, for: account, with: jid);
//                    self.itemRemoved(withId: itemId, for: account, with: jid);
                    self.previewGenerationDispatcher.async(flags: .barrier, execute: {
                        self.dispatcher.sync {
                            print("removing previews for master id:", itemId);
                            self.removePreviews(idOfRelatedToItem: itemId);
                        }
                    })
                }
            }
            return true;
        } else {
            return false;
        }

    }
    
    private func generatePreviews(forItem masterId: Int, account: BareJID, jid: BareJID, state: MessageState) {
        if #available(macOS 10.15, *) {
            let params: [String: Any?] = ["id": masterId];
            guard let item = try! self.getChatMessageWithIdStmt.findFirst(params, map: { (cursor) in
                return self.itemFrom(cursor: cursor, for: account, with: jid) as? ChatMessage
            }) else {
                return;
            }
        
            self.generatePreviews(forItem: item.id, account: item.account, jid: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: item.recipientNickname, participantId: item.participantId, timestamp: item.timestamp, data: item.message);
        }
    }
    
    private var previewsInProgress: [Int: UUID] = [:];
    private let previewGenerationDispatcher = QueueDispatcher(label: "chat_history_store", attributes: [.concurrent]);
    
    private func generatePreviews(forItem masterId: Int, account: BareJID, jid: BareJID, state messageState: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, timestamp: Date, data: String) {
        if #available(macOS 10.15, *) {
            let state = messageState == .incoming_unread ? .incoming : messageState;
            let uuid = UUID();
            previewsInProgress[masterId] = uuid;
        previewGenerationDispatcher.async {
            print("generating previews for master id:", masterId, "uuid:", uuid);
        // if we may have previews, we should add them here..
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
            let matches = detector.matches(in: data, range: NSMakeRange(0, data.utf16.count));
            
            guard self.dispatcher.sync(execute: {
                let valid =  self.previewsInProgress[masterId] == uuid;
                if valid {
                    self.previewsInProgress.removeValue(forKey: masterId);
                }
                return valid;
            }) else {
                return;
            }
            print("adding previews for master id:", masterId, "uuid:", uuid);
            matches.forEach { match in
                if let url = match.url, let scheme = url.scheme, ["https", "http"].contains(scheme) {
                    if (data as NSString).range(of: "http", options: .caseInsensitive, range: match.range).location == match.range.location {
                        DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: url.absoluteString, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .none, masterId: masterId, completionHandler: nil);
                    }
                }
                if let address = match.components {
                    let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                    let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                    DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: mapUrl.absoluteString, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .none, masterId: masterId, completionHandler: nil);
                }
            }
        }
        }
        }
    }

    fileprivate func processOutgoingError(for account: BareJID, with jid: BareJID, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) -> Bool {
        guard let itemId = DBChatHistoryStore.instance.getItemId(for: account, with: jid, stanzaId: stanzaId) else {
            return false;
        }

        let params: [String: Any?] = ["id": itemId, "state": MessageState.outgoing_error_unread.rawValue, "error": errorMessage ?? errorCondition?.rawValue ?? "Unknown error"];
        guard try! self.markAsErrorStmt.update(params) > 0 else {
            return false;
        }
        DBChatStore.instance.newMessage(for: account, with: jid, timestamp: Date(timeIntervalSince1970: 0), itemType: nil, message: nil, state: .outgoing_error_unread) {
            self.itemUpdated(withId: itemId, for: account, with: jid);
        }
        return true;
    }

    open func markOutgoingAsError(for account: BareJID, with jid: BareJID, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) {
        dispatcher.async {
            _ = self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId, errorCondition: errorCondition, errorMessage: errorMessage);
        }
    }

    open func markAsRead(for account: BareJID, with jid: BareJID, messageId: String? = nil) {
        dispatcher.async {
            if let id = messageId {
                if let msgId = self.findItemId(for: account, with: jid, originId: id, authorNickname: nil, participantId: nil) {
                    let params: [String: Any?] = ["account": account, "jid": jid, "id": msgId];
                    let updateRecords = try! self.markMessageAsReadStmt.update(params);
                    if updateRecords > 0 {
                        DBChatStore.instance.markAsRead(for: account, with: jid, count: 1);
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: self, userInfo: ["account": account, "jid": jid]);
                        }
                    }
                }
            } else {
                let params: [String: Any?] = ["account": account, "jid": jid];
                let updateRecords = try! self.markAsReadStmt.update(params);
                if updateRecords > 0 {
                    DBChatStore.instance.markAsRead(for: account, with: jid);
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: self, userInfo: ["account": account, "jid": jid]);
                    }
                }
            }
        }
    }

    open func markAsRead(for account: BareJID, with jid: BareJID, before: Date) {
        dispatcher.async {
            let params: [String: Any?] = ["account": account, "jid": jid, "before": before];
            let updateRecords = try! self.markAsReadBeforeStmt.update(params);
            if updateRecords > 0 {
                DBChatStore.instance.markAsRead(for: account, with: jid, count: updateRecords);
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: self, userInfo: ["account": account, "jid": jid]);
                }
            }
        }
    }

    open func getItemId(for account: BareJID, with jid: BareJID, stanzaId: String) -> Int? {
        return dispatcher.sync {
            return self.findItemId(for: account, with: jid, originId: stanzaId, authorNickname: nil, participantId: nil);
        }
    }

    open func itemPosition(for account: BareJID, with jid: BareJID, msgId: Int) -> Int? {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account, "jid": jid, "msgId": msgId, "showLinkPreviews": linkPreviews];
            return try! self.getChatMessagePosition.scalar(params);
        }
    }

    open func updateItemState(for account: BareJID, with jid: BareJID, stanzaId: String, from oldState: MessageState, to newState: MessageState, withTimestamp timestamp: Date? = nil) {
        dispatcher.async {
            guard let msgId = self.getItemId(for: account, with: jid, stanzaId: stanzaId) else {
                return;
            }

            self.updateItemState(for: account, with: jid, itemId: msgId, from: oldState, to: newState, withTimestamp: timestamp);
        }
    }

    open func updateItemState(for account: BareJID, with jid: BareJID, itemId msgId: Int, from oldState: MessageState, to newState: MessageState, withTimestamp timestamp: Date?) {
        dispatcher.async {
            let params: [String: Any?] = ["id": msgId, "oldState": oldState.rawValue, "newState": newState.rawValue, "newTimestamp": timestamp];
            guard (try! self.updateItemStateStmt.update(params)) > 0 else {
                return;
            }
            self.itemUpdated(withId: msgId, for: account, with: jid);
            if oldState == .outgoing_unsent && newState != .outgoing_unsent {
                self.generatePreviews(forItem: msgId, account: account, jid: jid, state: newState);
            }
        }
    }

    fileprivate var findLinkPreviewsForMessageStmt: DBStatement?;
    
    open func remove(item: ChatViewItemProtocol) {
        dispatcher.async {
            let params: [String: Any?] = ["id": item.id];
            guard (try! self.removeItemStmt.update(params)) > 0 else {
                return;
            }
            self.itemRemoved(withId: item.id, for: item.account, with: item.jid);
            self.removePreviews(idOfRelatedToItem: item.id);
        }
    }
    
    private func removePreviews(idOfRelatedToItem masterId: Int) {
        if #available(macOS 10.15, *) {
            if self.findLinkPreviewsForMessageStmt == nil {
                self.findLinkPreviewsForMessageStmt = try! DBConnection.main.prepareStatement("SELECT id, account, jid, data FROM chat_history WHERE master_id = :master_id AND item_type = \(ItemType.linkPreview.rawValue)");
            }
            // for chat message we might have a link previews which we need to remove..
            let linkParams: [String: Any?] = ["master_id": masterId];
            guard let linkPreviews = try? self.findLinkPreviewsForMessageStmt?.query(linkParams, map: { cursor -> (Int, BareJID, BareJID)? in
                guard let id: Int = cursor["id"], let account: BareJID = cursor["account"], let jid: BareJID = cursor["jid"] else {
                    return nil;
                }
                return (id, account, jid);
            }), !linkPreviews.isEmpty else {
                return;
            }
            for (id, account, jid) in linkPreviews {
                // this is a preview and needs to be removed..
                let removeLinkParams: [String: Any?] = ["id": id];
                if (try! self.removeItemStmt.update(removeLinkParams)) > 0 {
                    self.itemRemoved(withId: id, for: account, with: jid);
                }
            }
        }
    }
    
    func originId(for account: BareJID, with jid: BareJID, id: Int, completionHandler: @escaping (String)->Void ){
        dispatcher.async {
            let stmt = try! DBConnection.main.prepareStatement("select stanza_id from chat_history where id = ?");
            if let stanzaId: String = try! stmt.findFirst(id, map: { $0["stanza_id"] }) {
                DispatchQueue.main.async {
                    completionHandler(stanzaId);
                }
            }
        }
    }
    
    open func updateItem(for account: BareJID, with jid: BareJID, id: Int, updateAppendix updateFn: @escaping (inout ChatAttachmentAppendix)->Void) {
        dispatcher.async {
            var params: [String: Any?] = ["id": id];
            guard let item = try! self.getChatMessageWithIdStmt.findFirst(params, map: { (cursor) in
                return self.itemFrom(cursor: cursor, for: account, with: jid)
            }) as? ChatAttachment else {
                return;
            }
            updateFn(&item.appendix);
            if let data = try? JSONEncoder().encode(item.appendix), let dataStr = String(data: data, encoding: .utf8) {
                params["appendix"] = dataStr;
                _ = try! self.updateItemStmt.update(params)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
            }
        }
    }

    func loadUnsentMessage(for account: BareJID, completionHandler: @escaping (BareJID,BareJID,String,String,MessageEncryption,String?,ItemType)->Void) {
        dispatcher.async {
            try! self.getUnsentMessagesForAccountStmt.query(["account": account] as [String : Any?], forEach: { (cursor) in
                let jid: BareJID = cursor["jid"]!;
                let type = ItemType(rawValue: cursor["item_type"]!)!;
                let data: String = cursor["data"]!;
                let stanzaId: String = cursor["stanza_id"]!;
                let encryption: MessageEncryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
                let correctionStanzaId: String? = cursor["correction_stanza_id"];
                
                completionHandler(account, jid, data, stanzaId, encryption, correctionStanzaId, type);
            });
        }
    }

    fileprivate func itemUpdated(withId id: Int, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            let params: [String: Any?] = ["id": id]
            try! self.getChatMessageWithIdStmt.query(params, forEach: { (cursor) in
                guard let item = self.itemFrom(cursor: cursor, for: account, with: jid) else {
                    return;
                }
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
            });
        }
    }

    fileprivate func itemRemoved(withId id: Int, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_REMOVED, object: DeletedMessage(id: id, account: account, jid: jid));
        }
    }

    open func history(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int, completionHandler: @escaping (([ChatViewItemProtocol]) -> Void)) {
        dispatcher.async {
            if before != nil {
                let params: [String: Any?] = ["account": account, "jid": jid, "msgId": before!, "showLinkPreviews": self.linkPreviews];
                let offset = try! self.getChatMessagePosition.scalar(params)!;
                completionHandler(self.history(for: account, jid: jid, offset: offset, limit: limit));
            } else {
                completionHandler(self.history(for: account, jid: jid, offset: 0, limit: limit));
            }
        }
    }

    open func history(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int) -> [ChatViewItemProtocol] {
        return dispatcher.sync {
            if before != nil {
                let offset = try! getChatMessagePosition.scalar(["account": account, "jid": jid, "msgId": before!, "showLinkPreviews": linkPreviews])!;
                return history(for: account, jid: jid, offset: offset, limit: limit);
            } else {
                return history(for: account, jid: jid, offset: 0, limit: limit);
            }
        }
    }

    open func searchHistory(for account: BareJID? = nil, with jid: BareJID? = nil, search: String, completionHandler: @escaping ([ChatViewItemProtocol])->Void) {
        dispatcher.async {
            let tokens = search.unicodeScalars.split(whereSeparator: { (c) -> Bool in
                return CharacterSet.punctuationCharacters.contains(c) || CharacterSet.whitespacesAndNewlines.contains(c);
            }).map({ (s) -> String in
                return String(s) + "*";
            });
            let query = tokens.joined(separator: " + ");
            print("searching for:", tokens, "query:", query);
            let params: [String: Any?] = ["account": account, "jid": jid, "query": query];
            let items = (try? self.searchHistoryStmt.query(params, map: { (cursor) -> ChatViewItemProtocol? in
                guard let account: BareJID = cursor["account"], let jid: BareJID = cursor["jid"] else {
                    return nil;
                }
                return self.itemFrom(cursor: cursor, for: account, with: jid);
            })) ?? [];
            completionHandler(items);
        }
    }

    fileprivate func history(for account: BareJID, jid: BareJID, offset: Int, limit: Int) -> [ChatViewItemProtocol] {
        let params: [String: Any?] = ["account": account, "jid": jid, "offset": offset, "limit": limit, "showLinkPreviews": linkPreviews];
        return try! getChatMessagesStmt.query(params) { (cursor) -> ChatViewItemProtocol? in
            return itemFrom(cursor: cursor, for: account, with: jid);
        }
    }

//    public func checkItemAlreadyAdded(for account: BareJID, with jid: BareJID, authorNickname: String?, type: ItemType, timestamp: Date, direction: MessageDirection, stanzaId: String?, data: String?) -> Bool {
//        let range = stanzaId == nil ? 5.0 : 60.0;
//        let ts_from = timestamp.addingTimeInterval(-60 * range);
//        let ts_to = timestamp.addingTimeInterval(60 * range);
//
//        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": type.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];
//
//        return (try! checkItemAlreadyAddedStmt.scalar(params) ?? 0) > 0;
//    }
    
    public func loadAttachments(for account: BareJID, with jid: BareJID, completionHandler: @escaping ([ChatAttachment])->Void) {
        let params: [String: Any?] = ["account": account, "jid": jid];
        dispatcher.async {
            let attachments: [ChatAttachment] = try! self.getChatAttachmentsStmt.query(params, map: { cursor -> ChatAttachment? in
                return self.itemFrom(cursor: cursor, for: account, with: jid) as? ChatAttachment;
            });
            completionHandler(attachments);
        }
    }
    
    fileprivate var linkPreviews: Bool {
        if #available(macOS 10.15, *) {
            return Settings.linkPreviews.bool();
        } else {
            return false;
        }
    }

    fileprivate func itemFrom(cursor: DBCursor, for account: BareJID, with jid: BareJID) -> ChatViewItemProtocol? {
        let id: Int = cursor["id"]!;
        let stateInt: Int = cursor["state"]!;
        let timestamp: Date = cursor["timestamp"]!;

        guard let entryType = ItemType(rawValue: cursor["item_type"]!) else {
            return nil;
        }

        var correctionTimestamp: Date? = cursor["correction_timestamp"];
        if correctionTimestamp?.timeIntervalSince1970 == 0 {
            correctionTimestamp = nil;
        }
        
        let authorNickname: String? = cursor["author_nickname"];
        let authorJid: BareJID? = cursor["author_jid"];
        let recipientNickname: String? = cursor["recipient_nickname"];
        let participantId: String? = cursor["participant_id"];

        let encryption: MessageEncryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
        let encryptionFingerprint: String? = cursor["fingerprint"];
        let error: String? = cursor["error"];

        //let appendix: String? = cursor["appendix"];
        // maybe we should have a "supplement" object which would provide additional info? such as additional data, etc..
        switch entryType {
        case .message:
            let message: String = cursor["data"]!;

            var preview: [String: String]? = nil;
            if let previewStr: String = cursor["preview"] {
                preview = [:];
                previewStr.split(separator: "\n").forEach { (line) in
                    let tmp = line.split(separator: "\t");
                    preview?[String(tmp[0])] = String(tmp[1]);
                }
            }

            return ChatMessage(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error, correctionTimestamp: correctionTimestamp);
        case .messageRetracted:
            return ChatMessageRetracted(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error);
        case .invitation:
            let message: String? = cursor["data"];
            guard let appendix = ChatInvitationAppendix.decode(ChatInvitationAppendix.self, fromString: cursor["appendix"]) else {
                return nil;
            }
            return ChatInvitation(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, error: error)
        case .attachment:
            let url: String = cursor["data"]!;

            let appendix = parseAttachmentAppendix(string: cursor["appendix"]);
            
            return ChatAttachment(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, error: error);
        case .linkPreview:
            let url: String = cursor["data"]!;
            return ChatLinkPreview(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error)
        case .attachmentRetracted:
            // nothing in here, as were are removing retracted messages from the UI
            return nil;
        }

    }
    
    fileprivate func parseAttachmentAppendix(string: String?) -> ChatAttachmentAppendix {
        guard let appendix = ChatAttachmentAppendix.decode(ChatAttachmentAppendix.self, fromString: string) else {
            return ChatAttachmentAppendix();
        }
        return appendix;
    }
}

public enum ItemType: Int {
    case message = 0
    case attachment = 1
    // how about new type called link preview? this way we would have a far less data kept in a single item..
    // we could even have them separated to the new item/entry during adding message to the store..
    @available(macOS 10.15, *)
    case linkPreview = 2
    // with that in place we can have separate metadata kept "per" message as it is only one, so message id can be id of associated metadata..
    case invitation = 3
    case messageRetracted = 4
    case attachmentRetracted = 5;
}
