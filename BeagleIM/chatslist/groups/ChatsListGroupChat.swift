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
import TigaseSwift

class ChatsListGroupChat: ChatsListGroupAbstractChat {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: "Direct messages", dispatcher: QueueDispatcher(label: "chats_list_group_chats_queue"), delegate: delegate, canOpenChat: true);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func isAccepted(chat: Conversation) -> Bool {
        return chat is Chat;
    }

    override func newChatItem(chat: Conversation) -> ChatItemProtocol? {
        let item = ChatItem(chat: chat);
        guard item.isInRoster else {
            return nil;
        }
        return item;
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let jid = e.presence.from?.bareJid else {
            return;
        }
        
        self.updateItem(for: account, jid: jid, executeIfExists: nil, executeIfNotExists: nil);
    }
    
    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let rosterItem = e.rosterItem else {
            return;
        }
        
        if e.action == .removed {
            removeItem(for: account, jid: rosterItem.jid.bareJid);
        } else {
            self.updateItem(for: account, jid: rosterItem.jid.bareJid, executeIfExists: { (item) in
                (item as? ChatItem)?.name = ((e.action != .removed) ? rosterItem.name : nil) ?? rosterItem.jid.stringValue;
            }, executeIfNotExists: {
                guard let chat = DBChatStore.instance.conversation(for: account, with: rosterItem.jid.bareJid) as? Chat else {
                    return;
                }
                
                self.addItem(chat: chat);
            });
        }
    }
}

class ChatsListGroupChatUnknown: ChatsListGroupAbstractChat {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: "From unknown", dispatcher: QueueDispatcher(label: "chats_list_group_chats_unkonwn_queue"), delegate: delegate, canOpenChat: false);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func isAccepted(chat: Conversation) -> Bool {
        return chat is Chat;
    }
    
    override func newChatItem(chat: Conversation) -> ChatItemProtocol? {
        let item = ChatItem(chat: chat);
        guard !item.isInRoster else {
            return nil;
        }
        return item;
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let jid = e.presence.from?.bareJid else {
            return;
        }
        
        self.updateItem(for: account, jid: jid, executeIfExists: nil, executeIfNotExists: nil);
    }
    
    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let rosterItem = e.rosterItem else {
            return;
        }

        if e.action != .removed {
            removeItem(for: account, jid: rosterItem.jid.bareJid);
        } else {
            self.updateItem(for: account, jid: rosterItem.jid.bareJid, executeIfExists: { (item) in
                (item as? ChatItem)?.name = ((e.action != .removed) ? rosterItem.name : nil) ?? rosterItem.jid.stringValue;
            }, executeIfNotExists: {
                guard let chat = DBChatStore.instance.conversation(for: account, with: rosterItem.jid.bareJid) as? Chat else {
                    return;
                }
                
                self.addItem(chat: chat);
            });
        }
    }
}
