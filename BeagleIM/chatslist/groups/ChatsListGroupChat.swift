//
//  ChatsListGroupChat.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 20.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ChatsListGroupChat: ChatsListGroupAbstractChat<DBChatStore.DBChat> {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: "Direct messages", dispatcher: QueueDispatcher(label: "chats_list_group_chats_queue"), delegate: delegate);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func newChatItem(chat: DBChatStore.DBChat) -> ChatItemProtocol? {
        return ChatItem(chat: chat);
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let jid = e.presence.from?.bareJid else {
            return;
        }
        
        self.updateItem(for: account, jid: jid, execute: nil);
    }
    
    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let rosterItem = e.rosterItem else {
            return;
        }
        
        self.updateItem(for: account, jid: rosterItem.jid.bareJid) { (item) in
            (item as? ChatItem)?.name = ((e.action != .removed) ? rosterItem.name : nil) ?? rosterItem.jid.stringValue;
        }
    }
}
