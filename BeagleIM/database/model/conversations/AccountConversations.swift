//
// AccountConversations.swift
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
import TigaseSwift

public class AccountConversations {

    private var conversations = [BareJID: Conversation]();

    private let queue = DispatchQueue(label: "accountChats");

    var count: Int {
        return self.queue.sync(execute: {
            return self.conversations.count;
        })
    }

    var items: [Conversation] {
        return self.queue.sync(execute: {
            return self.conversations.values.map({ (chat) -> Conversation in
                return chat;
            });
        });
    }

    init(items: [Conversation]) {
        items.forEach { item in
            self.conversations[item.jid] = item;
        }
    }

    func open(with jid: BareJID, execute: () -> Conversation) -> Conversation? {
        return self.queue.sync(execute: {
            var chats = self.conversations;
            guard let existingChat = chats[jid] else {
                let conversation = execute();
                chats[jid] = conversation;
                self.conversations = chats;
                return conversation;
            }
            return existingChat;
        });
    }

    func close(conversation: Conversation, execute: ()->Void) -> Bool {
        return self.queue.sync(execute: {
            var chats = self.conversations;
            let removed = chats.removeValue(forKey: conversation.jid) != nil;
            self.conversations = chats;
            if removed {
                execute();
            }
            return removed;
        });
    }

    func get(with jid: BareJID) -> Conversation? {
        return self.queue.sync(execute: {
            let chats = self.conversations;
            return chats[jid];
        });
    }

    func lastMessageTimestamp() -> Date {
        return self.queue.sync(execute: {
            var timestamp = Date(timeIntervalSince1970: 0);
            self.conversations.values.forEach { (chat) in
                guard chat.lastActivity != nil else {
                    return;
                }
                timestamp = max(timestamp, chat.timestamp);
            }
            return timestamp;
        });
    }
}
