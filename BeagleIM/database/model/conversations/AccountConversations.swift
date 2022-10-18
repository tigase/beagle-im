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
import Martin

public class AccountConversations {

    private var conversations = [BareJID: Conversation]();

    var count: Int {
        return self.conversations.count;
    }

    var items: [Conversation] {
        return self.conversations.values.map({ (chat) -> Conversation in
            return chat;
        });
    }

    init(items: [Conversation]) {
        items.forEach { item in
            self.conversations[item.jid] = item;
        }
    }

    func add(_ conversation: Conversation) {
        self.conversations[conversation.jid] = conversation;
    }

    func remove(_ conversation: Conversation) -> Bool {
        var chats = self.conversations;
        let removed = chats.removeValue(forKey: conversation.jid) != nil;
        self.conversations = chats;
        return removed;
    };

    func get(with jid: BareJID) -> Conversation? {
        return self.conversations[jid];
    }

    func lastMessageTimestamp() -> Date {
        return self.conversations.values.filter({ $0.lastActivity.payload != nil }).map({ $0.timestamp }).max() ?? Date(timeIntervalSince1970: 0);
    }
}
