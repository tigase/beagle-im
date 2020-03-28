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

    fileprivate let appendMessageStmt: DBStatement = try! DBConnection.main.prepareStatement("INSERT INTO chat_history (account, jid, timestamp, item_type, data, stanza_id, state, author_nickname, author_jid, recipient_nickname, participant_id, error, encryption, fingerprint, appendix, server_msg_id, remote_msg_id) VALUES (:account, :jid, :timestamp, :item_type, :data, :stanza_id, :state, :author_nickname, :author_jid, :recipient_nickname, :participant_id, :error, :encryption, :fingerprint, :appendix, :server_msg_id, :remote_msg_id)");
    // if server has MAM:2 then use server_msg_id for checking
    // if there is no result, try to match using origin-id/stanza-id (if there is one in a form of UUID) and update server_msg_id if message is found
    // if there is was no origin-id/stanza-id then use old check with timestamp range and all of that..
    fileprivate let findItemFallback: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND (:data IS NULL OR data = :data) AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (state % 2 == :direction) AND (:author_nickname is null OR author_nickname = :author_nickname) order by timestamp desc");
    fileprivate let findItemByServerMsgId: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND server_msg_id = :server_msg_id");
    fileprivate let findItemByOriginId: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND stanza_id = :stanza_id");
    fileprivate let updateServerMsgId: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET server_msg_id = :server_msg_id WHERE id = :id");
    fileprivate let markAsReadStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let markAsReadBeforeStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let markMessageAsReadStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE id = :id AND account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let updateItemStateStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = :newState, timestamp = COALESCE(:newTimestamp, timestamp) WHERE id = :id AND (:oldState IS NULL OR state = :oldState)");
    fileprivate let updateItemStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET appendix = :appendix WHERE id = :id");
    fileprivate let markAsErrorStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = :state, error = :error WHERE id = :id");
    fileprivate let countItemsStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid")

    fileprivate let getItemIdByStanzaId: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND stanza_id = :stanza_id ORDER BY timestamp DESC");
    fileprivate let getChatMessagesStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix FROM chat_history WHERE account = :account AND jid = :jid AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");
    fileprivate let getChatMessageWithIdStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix FROM chat_history WHERE id = :id");
    fileprivate let getChatAttachmentsStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix FROM chat_history WHERE account = :account AND jid = :jid AND item_type = \(ItemType.attachment.rawValue) ORDER BY timestamp DESC");

    fileprivate let getChatMessagePosition: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)")
    fileprivate let removeChatHistoryStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE account = :account AND (:jid IS NULL OR jid = :jid)");

    fileprivate let searchHistoryStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT chat_history.id as id, chat_history.account as account, chat_history.jid as jid, author_nickname, author_jid, participant_id,  chat_history.timestamp as timestamp, item_type, chat_history.data as data, state, preview, chat_history.encryption as encryption, fingerprint FROM chat_history INNER JOIN chat_history_fts_index ON chat_history.id = chat_history_fts_index.rowid LEFT JOIN chats ON chats.account = chat_history.account AND chats.jid = chat_history.jid WHERE (chats.id IS NOT NULL OR chat_history.author_nickname is NULL) AND chat_history_fts_index MATCH :query AND (:account IS NULL OR chat_history.account = :account) AND (:jid IS NULL OR chat_history.jid = :jid) AND item_type = \(ItemType.message.rawValue) ORDER BY chat_history.timestamp DESC")

    fileprivate let getUnsentMessagesForAccountStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT ch.account as account, ch.jid as jid, ch.item_type as item_type, ch.data as data, ch.stanza_id as stanza_id, ch.encryption as encryption FROM chat_history ch WHERE ch.account = :account AND ch.state = \(MessageState.outgoing_unsent.rawValue) ORDER BY timestamp ASC");

    fileprivate let removeItemStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE id = :id");

    fileprivate let dispatcher: QueueDispatcher;
    
    static func convertToAttachments() {
        let diskCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("download", isDirectory: true);
        guard FileManager.default.fileExists(atPath: diskCacheUrl.path) else {
            return;
        }
        
        let previewsToConvert = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE preview IS NOT NULL").query(map: { cursor -> Int in
            return cursor["id"]!;
        });
        let convertStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, account, jid, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, preview, stanza_id FROM chat_history WHERE id = ?");
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
                        DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .attachment, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, chatAttachmentAppendix: appendix, linkPreviewAction: .none, completionHandler: { newId in
                                DBChatHistoryStore.instance.remove(item: item);
                        });
                    } else {
                        if #available(macOS 10.15, *) {
                            DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: previews.keys.first ?? item.message, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, linkPreviewAction: .none, completionHandler: { newId in
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
                    
                        for (url, previewId) in previews {
                            group.enter();
                            DBChatHistoryStore.instance.appendItem(for: item.account, with: item.jid, state: item.state, authorNickname: item.authorNickname, authorJid: item.authorJid, recipientNickname: nil, participantId: nil, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: url, encryption: item.encryption, encryptionFingerprint: item.encryptionFingerprint, linkPreviewAction: .none, completionHandler: { newId in
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
        
    open func append(for account: BareJID, message: Message, source: MessageSource) {
        let direction: MessageDirection = account == message.from?.bareJid ? .outgoing : .incoming;
        guard let jidFull = direction == .outgoing ? message.to : message.from else {
            // sender jid should always be there..
            return;
        }
        
        let jid = jidFull.bareJid;
        
        let (decryptedBody, encryption, fingerprint) = MessageEventHandler.prepareBody(message: message, forAccount: account);
        guard let body = decryptedBody else {
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
        
        let itemType = MessageEventHandler.itemType(fromMessage: message);
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
        
        var originId: String?;
        if let tmp = message.originId, UUID(uuidString: tmp) != nil {
            originId = tmp;
        }
        
        let (authorNickname, authorJid, recipientNickname, participantId) = MessageEventHandler.extractRealAuthor(from: message, for: account, with: jidFull);
                
        let state = MessageEventHandler.calculateState(direction: MessageEventHandler.calculateDirection(direction: direction, for: account, with: jid, authorNickname: authorNickname, authorJid: authorJid), isError: (message.type ?? .chat) == .error, isUnread: !fromArchive);
        
        dispatcher.async {
            let timestamp = Date(timeIntervalSince1970: Double(Int64((inTimestamp ?? Date()).timeIntervalSince1970 * 1000)) / 1000);

            guard !state.isError || stanzaId == nil || !self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId!, errorCondition: message.errorCondition, errorMessage: message.errorText) else {
                return;
            }

            if let id = self.findItemId(for: account, with: jid, serverMsgId: serverMsgId, originId: originId, timestamp: timestamp, direction: state.direction, itemType: itemType, stanzaId: message.id, authorNickname: authorNickname, data: body) {
                // this message was already added to the store..
                // should this be here...?
                if let chatState = message.chatState {
                    DBChatStore.instance.process(chatState: chatState, for: account, with: jid);
                }
                return;
            }
            
            self.appendItemSync(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: itemType, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: body, chatState: message.chatState, errorCondition: message.errorCondition, errorMessage: message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, chatAttachmentAppendix: nil, linkPreviewAction: .auto, completionHandler: nil);
        }
    }
    
    enum LinkPreviewAction {
        case auto
        case none
        case only
    }
    
    private func findItemId(for account: BareJID, with jid: BareJID, serverMsgId: String?, originId: String?, timestamp: Date, direction: MessageDirection, itemType: ItemType, stanzaId: String?, authorNickname: String?, data: String?) -> Int? {
        if serverMsgId != nil {
            if let id = try! self.findItemByServerMsgId.findFirst(["server_msg_id": serverMsgId, "account": account] as [String: Any?], map: { cursor -> Int? in
                return cursor["id"];
            }) {
                return id;
            }
        }
        
        var id: Int?;
        if originId != nil {
            id = try! self.findItemByOriginId.findFirst(["stanza_id": originId, "account": account, "jid": jid] as [String: Any?], map: { cursor -> Int? in
                return cursor["id"];
            })
        }
        if id == nil {
            let range = stanzaId == nil ? 5.0 : 60.0;
            let ts_from = timestamp.addingTimeInterval(-60 * range);
            let ts_to = timestamp.addingTimeInterval(60 * range);

            let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": itemType.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];

            id = try! self.findItemFallback.findFirst(params, map: { cursor -> Int? in
                return cursor["id"];
            })
        }
        if id != nil && serverMsgId != nil {
            _ = try! self.updateServerMsgId.update(["id": id, "server_msg_id": serverMsgId] as [String: Any?]);
        }
        
        return id;
    }
    
    private func appendItemSync(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, type: ItemType, timestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState?, errorCondition: ErrorCondition?, errorMessage: String? , encryption: MessageEncryption, encryptionFingerprint: String?, chatAttachmentAppendix: ChatAttachmentAppendix?, linkPreviewAction: LinkPreviewAction, completionHandler: ((Int) -> Void)?) {
        if linkPreviewAction != .only {
            var appendix: String? = nil;
            if let attachmentAppendix = chatAttachmentAppendix {
                if let appendixData = try? JSONEncoder().encode(attachmentAppendix) {
                    appendix = String(data: appendixData, encoding: .utf8);
                }
            }

            let params: [String:Any?] = ["account": account, "jid": jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.rawValue, "stanza_id": stanzaId, "author_nickname": authorNickname, "author_jid": authorJid, "recipient_nickname": recipientNickname, "participant_id": participantId, "encryption": encryption.rawValue, "fingerprint": encryptionFingerprint, "error": state.isError ? (errorMessage ?? errorCondition?.rawValue ?? "Unknown error") : nil, "appendix": appendix, "server_msg_id": serverMsgId, "remote_msg_id": remoteMsgId];
            guard let msgId = try! self.appendMessageStmt.insert(params) else {
                return;
            }
            completionHandler?(msgId);

            
            var item: ChatViewItemProtocol?;
            switch type {
            case .message:
                item = ChatMessage(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
            case .attachment:
                item = ChatAttachment(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: chatAttachmentAppendix ?? ChatAttachmentAppendix(), error: errorMessage);
            case .linkPreview:
                if #available(macOS 10.15, *), Settings.linkPreviews.bool() {
                    item = ChatLinkPreview(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
                }
            }
            if item != nil {
                DBChatStore.instance.newMessage(for: account, with: jid, timestamp: timestamp, itemType: type, message: encryption.message() ?? data, state: state, remoteChatState: state.direction == .incoming ? chatState : nil, senderNickname: authorNickname) {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: item);
                }
            }
        }
        if linkPreviewAction != .none && type == .message, #available(macOS 10.15, *) {
            DispatchQueue.global(qos: .background).async {
            // if we may have previews, we should add them here..
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
                let matches = detector.matches(in: data, range: NSMakeRange(0, data.utf16.count));
                matches.forEach { match in
                    if let url = match.url, let scheme = url.scheme, ["https", "http"].contains(scheme) {
                        if (data as NSString).range(of: "http", options: .caseInsensitive, range: match.range).location == match.range.location {
                            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: url.absoluteString, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .none, completionHandler: nil);
                        }
                    }
                    if let address = match.components {
                        let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                        let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                        DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: mapUrl.absoluteString, encryption: .none, encryptionFingerprint: nil, linkPreviewAction: .none, completionHandler: nil);
                    }
                }
            }
            }
        }
    }
    
    open func appendItem(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, type: ItemType, timestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState? = nil, errorCondition: ErrorCondition? = nil, errorMessage: String? = nil, encryption: MessageEncryption, encryptionFingerprint: String?, chatAttachmentAppendix: ChatAttachmentAppendix? = nil, linkPreviewAction: LinkPreviewAction, completionHandler: ((Int) -> Void)?) {
        dispatcher.async {
            self.appendItemSync(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, type: type, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: data, chatState: chatState, errorCondition: errorCondition, errorMessage: errorMessage, encryption: encryption, encryptionFingerprint: encryptionFingerprint, chatAttachmentAppendix: chatAttachmentAppendix, linkPreviewAction: linkPreviewAction, completionHandler: completionHandler);
        }
    }

    open func removeHistory(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            let params: [String: Any?] = ["account": account, "jid": jid];
            _ = try! self.removeChatHistoryStmt.update(params);
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
                var params: [String: Any?] = ["account": account, "jid": jid, "stanza_id": id];
                if let msgId = try! self.getItemIdByStanzaId.scalar(params) {
                    params = ["account": account, "jid": jid, "id": msgId];
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
            let params: [String: Any?] = ["account": account, "jid": jid, "stanza_id": stanzaId];
            return try! self.getItemIdByStanzaId.scalar(params);
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
            
            if #available(macOS 10.15, *), let item = item as? ChatMessage {
                if self.findLinkPreviewsForMessageStmt == nil {
                    self.findLinkPreviewsForMessageStmt = try! DBConnection.main.prepareStatement("SELECT id, data FROM chat_history WHERE account = :account AND jid = :jid AND timestamp = :timestamp AND item_type = \(ItemType.linkPreview.rawValue) AND id > :afterId");
                }
                // for chat message we might have a link previews which we need to remove..
                let linkParams: [String: Any?] = ["account": item.account, "jid": item.jid, "timestamp": item.timestamp, "afterId": item.id];
                guard let linkPreviews = try? self.findLinkPreviewsForMessageStmt?.query(linkParams, map: { cursor -> (Int, String)? in
                    guard let id: Int = cursor["id"], let url: String = cursor["data"] else {
                        return nil;
                    }
                    return (id, url);
                }), !linkPreviews.isEmpty else {
                    return;
                }
                for (id, url) in linkPreviews {
                    if item.message.contains(url) {
                        // this is a preview and needs to be removed..
                        let removeLinkParams: [String: Any?] = ["id": id];
                        if (try! self.removeItemStmt.update(removeLinkParams)) > 0 {
                            self.itemRemoved(withId: id, for: item.account, with: item.jid);
                        }
                    }
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
                try! self.updateItemStmt.update(params)
            }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
            }
        }
    }

    func loadUnsentMessage(for account: BareJID, completionHandler: @escaping (BareJID,BareJID,String,String,MessageEncryption, ItemType)->Void) {
        dispatcher.async {
            try! self.getUnsentMessagesForAccountStmt.query(["account": account] as [String : Any?], forEach: { (cursor) in
                let jid: BareJID = cursor["jid"]!;
                let type = ItemType(rawValue: cursor["item_type"]!)!;
                let data: String = cursor["data"]!;
                let stanzaId: String = cursor["stanza_id"]!;
                let encryption: MessageEncryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;

                completionHandler(account, jid, data, stanzaId, encryption, type);
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

            return ChatMessage(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error);
        case .attachment:
            let url: String = cursor["data"]!;

            let appendix = parseAttachmentAppendix(string: cursor["appendix"]);
            
            return ChatAttachment(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: appendix, error: error);
        case .linkPreview:
            let url: String = cursor["data"]!;
            return ChatLinkPreview(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: recipientNickname, participantId: participantId, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error)
        }

    }
    
    fileprivate func parseAttachmentAppendix(string: String?) -> ChatAttachmentAppendix {
        guard let data = string?.data(using: .utf8) else {
            return ChatAttachmentAppendix();
        }
        return (try? JSONDecoder().decode(ChatAttachmentAppendix.self, from: data)) ?? ChatAttachmentAppendix();
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
}
