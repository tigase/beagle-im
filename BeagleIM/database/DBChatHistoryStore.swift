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

    fileprivate let appendMessageStmt: DBStatement = try! DBConnection.main.prepareStatement("INSERT INTO chat_history (account, jid, timestamp, item_type, data, stanza_id, state, author_nickname, author_jid, error, encryption, fingerprint) VALUES (:account, :jid, :timestamp, :item_type, :data, :stanza_id, :state, :author_nickname, :author_jid, :error, :encryption, :fingerprint)");
    fileprivate let checkItemAlreadyAddedStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND (:data IS NULL OR data = :data) AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (state % 2 == :direction) AND (:author_nickname is null OR author_nickname = :author_nickname)");
    fileprivate let markAsReadStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let markAsReadBeforeStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let markMessageAsReadStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE id = :id AND account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let updateItemStateStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = :newState, timestamp = COALESCE(:newTimestamp, timestamp) WHERE id = :id AND (:oldState IS NULL OR state = :oldState)");
    fileprivate let updateItemStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET preview = coalesce(:preview, preview) WHERE id = :id");
    fileprivate let markAsErrorStmt: DBStatement = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = :state, error = :error WHERE id = :id");
    fileprivate let countItemsStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid")

    fileprivate let getItemIdByStanzaId: DBStatement = try! DBConnection.main.prepareStatement("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND stanza_id = :stanza_id ORDER BY timestamp DESC");
    fileprivate let getChatMessagesStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error FROM chat_history WHERE account = :account AND jid = :jid AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");
    fileprivate let getChatMessageWithIdStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error FROM chat_history WHERE id = :id");

    fileprivate let getChatMessagePosition: DBStatement = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)")
    fileprivate let removeChatHistoryStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE account = :account AND (:jid IS NULL OR jid = :jid)");

    fileprivate let searchHistoryStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT chat_history.id as id, chat_history.account as account, chat_history.jid as jid, author_nickname, author_jid, chat_history.timestamp as timestamp, item_type, chat_history.data as data, state, preview, chat_history.encryption as encryption, fingerprint FROM chat_history INNER JOIN chat_history_fts_index ON chat_history.id = chat_history_fts_index.rowid LEFT JOIN chats ON chats.account = chat_history.account AND chats.jid = chat_history.jid WHERE (chats.id IS NOT NULL OR chat_history.author_nickname is NULL) AND chat_history_fts_index MATCH :query AND (:account IS NULL OR chat_history.account = :account) AND (:jid IS NULL OR chat_history.jid = :jid) AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) ORDER BY chat_history.timestamp DESC")

    fileprivate let getUnsentMessagesForAccountStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT ch.account as account, ch.jid as jid, ch.item_type as item_type, ch.data as data, ch.stanza_id as stanza_id, ch.encryption as encryption FROM chat_history ch WHERE ch.account = :account AND ch.state = \(MessageState.outgoing_unsent.rawValue) ORDER BY timestamp ASC");

    fileprivate let removeItemStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE id = :id");

    fileprivate let dispatcher: QueueDispatcher;

    public init() {
        dispatcher = QueueDispatcher(label: "chat_history_store");
    }

    open func process(chatState: ChatState, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            DBChatStore.instance.process(chatState: chatState, for: account, with: jid);
        }
    }

    open func appendItem(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String? = nil, authorJid: BareJID? = nil, type: ItemType, timestamp: Date, stanzaId: String?, data: String, chatState: ChatState? = nil, errorCondition: ErrorCondition? = nil, errorMessage: String? = nil, encryption: MessageEncryption, encryptionFingerprint: String?, completionHandler: ((Int) -> Void)?) {
        dispatcher.async {
            guard !state.isError || stanzaId == nil || !self.processOutgoingError(for: account, with: jid, stanzaId: stanzaId!, errorCondition: errorCondition, errorMessage: errorMessage) else {
                return;
            }

            guard !self.checkItemAlreadyAdded(for: account, with: jid, authorNickname: authorNickname, type: type, timestamp: timestamp, direction: state.direction, stanzaId: stanzaId, data: data) else {
                if chatState != nil {
                    DBChatStore.instance.process(chatState: chatState!, for: account, with: jid);
                }
                return;
            }

            let params: [String:Any?] = ["account": account, "jid": jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.rawValue, "stanza_id": stanzaId, "author_nickname": authorNickname, "author_jid": authorJid, "encryption": encryption.rawValue, "fingerprint": encryptionFingerprint, "error": state.isError ? (errorMessage ?? errorCondition?.rawValue ?? "Unknown error") : nil];
            guard let msgId = try! self.appendMessageStmt.insert(params) else {
                return;
            }
            completionHandler?(msgId);

            
            var item: ChatViewItemProtocol?;
            switch type {
            case .message:
                item = ChatMessage(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
            case .attachment:
                item = ChatAttachment(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: ChatAttachmentAppendix(), error: errorMessage);
            case .linkPreview:
                item = ChatLinkPreview(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, url: data, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: errorMessage);
            }
            if item != nil {
                DBChatStore.instance.newMessage(for: account, with: jid, timestamp: timestamp, message: encryption.message() ?? data, state: state, remoteChatState: state.direction == .incoming ? chatState : nil) {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: item);
                }
            }
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
        DBChatStore.instance.newMessage(for: account, with: jid, timestamp: Date(timeIntervalSince1970: 0), message: nil, state: .outgoing_error_unread) {
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

    open func removeItem(for account: BareJID, with jid: BareJID, itemId: Int) {
        dispatcher.async {
            let params: [String: Any?] = ["id": itemId];
            guard (try! self.removeItemStmt.update(params)) > 0 else {
                return;
            }
            self.itemRemoved(withId: itemId, for: account, with: jid);
        }
    }

    open func updateItem(for account: BareJID, with jid: BareJID, id: Int, preview: [String:String]? = nil) {
        dispatcher.async {
            var params: [String: Any?] = ["id": id];
            if preview != nil {
                params["preview"] = preview!.map({ (k,v) -> String in
                    return "\(k)\t\(v)";
                }).joined(separator: "\n");
            }
            if try! self.updateItemStmt.update(params) > 0 {
                self.itemUpdated(withId: id, for: account, with: jid);
            }
        }
    }

//    open func updateAppendix(for account: BareJID, with jid: BareJID, id: Int, update)
    
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
            let params: [String: Any?] = ["account": account, "jid": jid, "query": query, "showLinkPreviews": self.linkPreviews];
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

    public func checkItemAlreadyAdded(for account: BareJID, with jid: BareJID, authorNickname: String?, type: ItemType, timestamp: Date, direction: MessageDirection, stanzaId: String?, data: String?) -> Bool {
        let range = stanzaId == nil ? 5.0 : 60.0;
        let ts_from = timestamp.addingTimeInterval(-60 * range);
        let ts_to = timestamp.addingTimeInterval(60 * range);

        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": type.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];

        return (try! checkItemAlreadyAddedStmt.scalar(params) ?? 0) > 0;
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

            return ChatMessage(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error);
        case .attachment:
            let url: String = cursor["data"]!;

            return ChatAttachment(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, appendix: ChatAttachmentAppendix(), error: error);
        case .linkPreview:
            let url: String = cursor["data"]!;
            return ChatLinkPreview(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, url: url, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error)
        }

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
