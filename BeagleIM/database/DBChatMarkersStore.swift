//
// DBChatMarkersStore.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import TigaseSQLite3

extension Query {
    static let markerFind = Query("SELECT type, timestamp FROM chat_markers WHERE account = :account AND jid = :jid AND sender_nick = :sender_nick AND sender_id = :sender_id AND sender_jid = :sender_jid");
    static let markerUpdate = Query("UPDATE chat_markers SET timestamp = :timestamp, type = :type WHERE account = :account AND jid = :jid AND sender_nick = :sender_nick AND sender_id = :sender_id AND sender_jid = :sender_jid");
    static let markerInsert = Query("INSERT INTO chat_markers (account, jid, sender_nick, sender_id, sender_jid, timestamp, type) VALUES (:account, :jid, :sender_nick, :sender_id, :sender_jid, :timestamp, :type)");
    static let markersList = Query("SELECT sender_nick, sender_id, sender_jid, timestamp, type FROM chat_markers WHERE account = :account AND jid = :jid");
}

public class DBChatMarkersStore {
    
    public static let instance = DBChatMarkersStore();
    
    private func queryParams(conversation: ConversationKey, sender: ConversationEntrySender) -> [String: Any?]? {
        switch sender {
        case .none:
            return nil;
        case .me(_):
            return ["account": conversation.account, "jid": conversation.jid, "sender_nick": "", "sender_id": "", "sender_jid": conversation.account];
        case .buddy(_):
            return ["account": conversation.account, "jid": conversation.jid, "sender_nick": "", "sender_id": "", "sender_jid": conversation.jid];
        case .occupant(let nickname, let jid):
            return ["account": conversation.account, "jid": conversation.jid, "sender_nick": nickname, "sender_id": "", "sender_jid": jid];
        case .participant(let id, let nickname, let jid):
            return ["account": conversation.account, "jid": conversation.jid, "sender_nick": nickname, "sender_id": id, "sender_jid": jid];
        }
    }
    
    public func mark(conversation: ConversationKey, before id: String, as type: ChatMarker.MarkerType, by sender: ConversationEntrySender) {
        guard var params = queryParams(conversation: conversation, sender: sender) else {
            return;
        }
        
        guard let msgId =  DBChatHistoryStore.instance.findItemId(for: conversation, originId: id, sender: .none) else {
            return;
        }

        guard let message = DBChatHistoryStore.instance.message(for: conversation, withId: msgId) else {
            return;
        }
        
        let timestamp: Date = message.timestamp;
        
        if let (oldType, oldTimestamp) = try! Database.main.reader({ database in
            try database.select(query: .markerFind, params: params).mapFirst({ (ChatMarker.MarkerType(rawValue: $0.int(for: "type")!)!, $0.date(for: "timestamp")!) });
        }) {
            switch type {
            case .received:
                guard oldTimestamp < timestamp else {
                    return;
                }
            case .displayed:
                guard oldTimestamp < timestamp || (oldTimestamp == timestamp && oldType < type) else {
                    return;
                }
            }
            
            try! Database.main.writer({ database in
                params["type"] = type.rawValue;
                params["timestamp"] = timestamp;
                try database.update(query: .markerUpdate, params: params);
            })
        } else {
            try! Database.main.writer({ database in
                params["type"] = type.rawValue;
                params["timestamp"] = timestamp;
                try database.insert(query: .markerInsert, params: params);
            })
        }
        
        if let conv = (conversation as? Conversation) ?? DBChatStore.instance.conversation(for: conversation.account, with: conversation.jid) {
            conv.mark(as: type, before: message.timestamp, by: sender);
            if conv.isLocal(sender: sender) {
                DBChatHistoryStore.instance.markAsRead(for: conv, before: timestamp);
            }
        }
    }
    
    public func markers(for conversation: ConversationKey) -> [ChatMarker] {
       return try! Database.main.reader({ database in
            try database.select(query: .markersList, params: ["account": conversation.account, "jid": conversation.jid]).mapAll({ self.charMarker(fromCursor: $0, conversation: conversation)});
       });
    }
    
    private func charMarker(fromCursor c: Cursor, conversation: ConversationKey) -> ChatMarker? {
        guard let type = ChatMarker.MarkerType(rawValue: c.int(for: "type")!), let timestamp = c.date(for: "timestamp"), let jid = BareJID(c.string(for: "sender_jid")), let nick = c.string(for: "sender_nick"), let id = c.string(for: "sender_id") else {
            return nil;
        }
        
        if nick.isEmpty {
            if conversation.account == jid {
                return ChatMarker(sender: .me(conversation: conversation), timestamp: timestamp, type: type);
            } else {
                return ChatMarker(sender: .buddy(conversation: conversation), timestamp: timestamp, type: type);
            }
        } else {
            if id.isEmpty {
                return ChatMarker(sender: .occupant(nickname: nick, jid: jid), timestamp: timestamp, type: type);
            } else {
                return ChatMarker(sender: .participant(id: id, nickname: nick, jid: jid), timestamp: timestamp, type: type);
            }
        }
    }
}
