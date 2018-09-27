//
//  ChatsListGroupGroupchat.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 20.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ChatsListGroupGroupchat: ChatsListGroupAbstractChat<DBChatStore.DBRoom> {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: "Groupchats", dispatcher: QueueDispatcher(label: "chats_list_group_groupchats_queue"), delegate: delegate);
        
        NotificationCenter.default.addObserver(self, selector: #selector(roomStatusChanged), name: XmppService.ROOM_STATUS_CHANGED, object: nil);
    }

    override func newChatItem(chat: DBChatStore.DBRoom) -> ChatItemProtocol? {
        return GroupchatItem(chat: chat);
    }
    
    @objc func roomStatusChanged(_ notification: Notification) {
        guard let room = notification.object as? DBChatStore.DBRoom else {
            return;
        }
        
        self.updateItem(for: room.account, jid: room.roomJid, execute: nil);
    }
}
