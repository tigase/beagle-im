//
// ChatsListGroupGroupchat.swift
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

class ChatsListGroupGroupchat: ChatsListGroupAbstractChat<DBChatStore.DBRoom> {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: "Groupchats", dispatcher: QueueDispatcher(label: "chats_list_group_groupchats_queue"), delegate: delegate, canOpenChat: true);
        
        NotificationCenter.default.addObserver(self, selector: #selector(roomStatusChanged), name: MucEventHandler.ROOM_STATUS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(roomNameChanged), name: MucEventHandler.ROOM_NAME_CHANGED, object: nil);
    }

    override func newChatItem(chat: DBChatStore.DBRoom) -> ChatItemProtocol? {
        return GroupchatItem(chat: chat);
    }

    @objc func roomNameChanged(_ notification: Notification) {
        guard let room = notification.object as? DBChatStore.DBRoom else {
            return;
        }
        
        self.updateItem(for: room.account, jid: room.roomJid, executeIfExists: { (item: ChatItemProtocol)->Void in
            (item as? GroupchatItem)?.name = room.name ?? room.roomJid.stringValue;
        }, executeIfNotExists: nil);
    }
    
    @objc func roomStatusChanged(_ notification: Notification) {
        guard let room = notification.object as? DBChatStore.DBRoom else {
            return;
        }
        
        self.updateItem(for: room.account, jid: room.roomJid, executeIfExists: nil, executeIfNotExists: nil);
    }
}
