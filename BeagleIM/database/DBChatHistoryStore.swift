//
//  DBChatHistoryStore.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 14.04.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

class DBChatHistoryStore {
    
    static let MESSAGE_NEW = Notification.Name("messageAdded");
    static let MESSAGES_MARKED_AS_READ = Notification.Name("messagesMarkedAsRead");
    static var instance: DBChatHistoryStore = DBChatHistoryStore.init();

    fileprivate let appendMessageStmt: DBStatement! = try! DBConnection.main.prepareStatement("INSERT INTO chat_history (account, jid, timestamp, item_type, data, stanza_id, state, author_nickname, author_jid) VALUES (:account, :jid, :timestamp, :item_type, :data, :stanza_id, :state, :author_nickname, :author_jid)");
    fileprivate let checkItemAlreadyAddedStmt: DBStatement! = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND timestamp BETWEEN :ts_from AND :ts_to AND item_type = :item_type AND data = :data AND (:stanza_id IS NULL OR (stanza_id IS NOT NULL AND stanza_id = :stanza_id)) AND (state % 2 == :direction) AND (:author_nickname is null OR author_nickname = :author_nickname)");
    fileprivate let markAsReadStmt: DBStatement! = try! DBConnection.main.prepareStatement("UPDATE chat_history SET state = case state when \(MessageState.incoming_error_unread.rawValue) then \(MessageState.incoming_error.rawValue) when \(MessageState.outgoing_error_unread.rawValue) then \(MessageState.outgoing_error.rawValue) else \(MessageState.incoming.rawValue) end WHERE account = :account AND jid = :jid AND state in (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))");
    fileprivate let getChatMessagesStmt: DBStatement! = try! DBConnection.main.prepareStatement("SELECT id, author_nickname, author_jid, timestamp, item_type, data, state, preview FROM chat_history WHERE account = :account AND jid = :jid ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");

    fileprivate let getChatMessagePosition: DBStatement! = try! DBConnection.main.prepareStatement("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)")
    fileprivate let removeChatHistoryStmt: DBStatement! = try! DBConnection.main.prepareStatement("DELETE FROM chat_history WHERE account = :account AND (:jid IS NULL OR jid = :jid)");
    
    fileprivate let dispatcher: QueueDispatcher;
    
    public init() {
        dispatcher = QueueDispatcher(label: "chat_history_store");
    }
    
    open func appendItem(for account: BareJID, with jid: BareJID, state: MessageState, authorNickname: String? = nil, authorJid: BareJID? = nil, type: ItemType = .message, timestamp: Date, stanzaId: String?, data: String, completionHandler: ((Int) -> Void)?) {
        dispatcher.async {
            guard !self.checkItemAlreadyAdded(for: account, with: jid, authorNickname: authorNickname, type: type, timestamp: timestamp, direction: state.direction, stanzaId: stanzaId, data: data) else {
                return;
            }
            
            let params: [String:Any?] = ["account": account, "jid": jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.rawValue, "stanza_id": stanzaId, "author_nickname": authorNickname, "author_jid": authorJid];
            guard let msgId = try! self.appendMessageStmt.insert(params) else {
                return;
            }
            completionHandler?(msgId);
            
            let item = ChatMessage(id: msgId, timestamp: timestamp, account: account, jid: jid, state: state, message: data, authorNickname: authorNickname, authorJid: authorJid);
            NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: item);
            
            DBChatStore.instance.newMessage(for: account, with: jid, timestamp: timestamp, message: data, state: state);
        }
    }
    
    open func removeHistory(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            let params: [String: Any?] = ["account": account, "jid": jid];
            _ = try! self.removeChatHistoryStmt.update(params);
        }
    }
    
    open func markAsRead(for account: BareJID, with jid: BareJID) {
        dispatcher.async {
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
    
    open func getHistory(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int, completionHandler: @escaping (([ChatViewItemProtocol]) -> Void)) {
        dispatcher.async {
            if before != nil {
                let params: [String: Any?] = ["account": account, "jid": jid, "msgId": before!];
                let offset = try! self.getChatMessagePosition.scalar(params)!;
                completionHandler(self.getHistory(for: account, jid: jid, offset: offset, limit: limit));
            } else {
                completionHandler(self.getHistory(for: account, jid: jid, offset: 0, limit: limit));
            }
        }
    }
    
    open func getHistory(for account: BareJID, jid: BareJID, before: Int? = nil, limit: Int) -> [ChatViewItemProtocol] {
        return dispatcher.sync {
            if before != nil {
                let offset = try! getChatMessagePosition.scalar(["account": account, "jid": jid, "msgId": before!])!;
                return getHistory(for: account, jid: jid, offset: offset, limit: limit);
            } else {
                return getHistory(for: account, jid: jid, offset: 0, limit: limit);
            }
        }
    }
    
    fileprivate func getHistory(for account: BareJID, jid: BareJID, offset: Int, limit: Int) -> [ChatViewItemProtocol] {
        let params: [String: Any?] = ["account": account, "jid": jid, "offset": offset, "limit": limit];
        return try! getChatMessagesStmt.query(params) { (cursor) -> ChatViewItemProtocol? in
            let id: Int = cursor["id"]!;
            let stateInt: Int = cursor["state"]!;
            let timestamp: Date = cursor["timestamp"]!;
            let message: String = cursor["data"]!;
            let authorNickname: String? = cursor["author_nickname"];
            let authorJid: BareJID? = cursor["author_jid"];
            return ChatMessage(id: id, timestamp: timestamp, account: account, jid: jid, state: MessageState(rawValue: stateInt)!, message: message, authorNickname: authorNickname, authorJid: authorJid);
        }
    }
    
    fileprivate func checkItemAlreadyAdded(for account: BareJID, with jid: BareJID, authorNickname: String?, type: ItemType, timestamp: Date, direction: MessageDirection, stanzaId: String?, data: String) -> Bool {
        let range = stanzaId == nil ? 5.0 : 60.0;
        let ts_from = timestamp.addingTimeInterval(-60 * range);
        let ts_to = timestamp.addingTimeInterval(60 * range);
        
        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": type.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];
        
        return (try! checkItemAlreadyAddedStmt.scalar(params) ?? 0) > 0;
    }
}

public enum ItemType: Int {
    case message = 0
}
