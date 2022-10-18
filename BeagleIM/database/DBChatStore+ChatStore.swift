//
// DBChatStore+ChatStore.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import Martin

extension DBChatStore: ChatStore {
    
    public typealias Chat = BeagleIM.Chat
    
    public func chats(for context: Context) -> [Chat] {
        return convert(items: self.conversations(for: context.userBareJid));
    }
    
    public func chat(for context: Context, with jid: BareJID) -> Chat? {
        return conversation(for: context.userBareJid, with: jid) as? Chat;
    }
    
    public func createChat(for context: Context, with jid: BareJID) -> ConversationCreateResult<Chat> {
        let account = context.userBareJid;
        return self.queue.sync {
            guard let conversation = self.accountsConversations.conversation(for: account, with: jid) else {
                let timestamp = Date();
                let id = try! self.openConversation(account: context.userBareJid, jid: jid, type: .chat, timestamp: timestamp, options: nil);
                let chat = Chat(context: context, jid: jid, id: id, lastActivity: lastActivity(for: account, jid: jid, conversationType: .chat) ?? .none(timestamp: timestamp), unread: 0, options: ChatOptions());
                if self.accountsConversations.add(chat) {
                    self.conversationsEventsPublisher.send(.created(chat));
                    return .created(chat);
                } else {
                    return .none;
                }
            }
            guard let chat = conversation as? Chat else {
                return .none;
            }
            return .found(chat);
        }
    }
    
    public func close(chat: Chat) -> Bool {
        return close(conversation: chat);
    }
 
}
