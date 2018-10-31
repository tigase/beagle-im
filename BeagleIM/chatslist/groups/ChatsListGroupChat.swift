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
        super.init(name: "Direct messages", dispatcher: QueueDispatcher(label: "chats_list_group_chats_queue"), delegate: delegate, canOpenChat: true);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func newChatItem(chat: DBChatStore.DBChat) -> ChatItemProtocol? {
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
                guard let messageModule: MessageModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageModule.ID) else {
                    return;
                }
                
                guard let dbChat = messageModule.chatManager.getChat(with: rosterItem.jid.withoutResource, thread: nil) as? DBChatStore.DBChat else {
                    return;
                }
                
                self.addItem(chat: dbChat);
            });
        }
    }
}

class ChatsListGroupChatUnknown: ChatsListGroupAbstractChat<DBChatStore.DBChat> {
    
    init(delegate: ChatsListViewDataSourceDelegate) {
        super.init(name: "From unknown", dispatcher: QueueDispatcher(label: "chats_list_group_chats_unkonwn_queue"), delegate: delegate, canOpenChat: false);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func newChatItem(chat: DBChatStore.DBChat) -> ChatItemProtocol? {
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
                guard let messageModule: MessageModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageModule.ID) else {
                    return;
                }
                
                guard let dbChat = messageModule.chatManager.getChat(with: rosterItem.jid.withoutResource, thread: nil) as? DBChatStore.DBChat else {
                    return;
                }
                
                self.addItem(chat: dbChat);
            });
        }
    }
}
