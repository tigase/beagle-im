//
// ChatsListGroupChat.swift
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
import Martin

class ChatsListGroupChat: ChatsListGroupAbstractChat {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: NSLocalizedString("Direct messages", comment: "Chats list group name"), queue: DispatchQueue(label: "chats_list_group_chats_queue"), delegate: delegate, canOpenChat: true);
    }
    
    override func isAccepted(chat: Conversation) -> Bool {
        return chat is Chat && DBRosterStore.instance.item(for: chat.account, jid: JID(chat.jid)) != nil;
    }

}

class ChatsListGroupChatUnknown: ChatsListGroupAbstractChat {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: NSLocalizedString("From unknown", comment: "Chats list group name"), queue: DispatchQueue(label: "chats_list_group_chats_unkonwn_queue"), delegate: delegate, canOpenChat: false);
    }
    
    override func isAccepted(chat: Conversation) -> Bool {
        return chat is Chat && DBRosterStore.instance.item(for: chat.account, jid: JID(chat.jid)) == nil
    }
    
}
