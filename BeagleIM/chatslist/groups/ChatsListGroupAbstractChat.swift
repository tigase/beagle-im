//
// ChatsListGroupAbstractChat.swift
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

class ChatsListGroupAbstractChat: ChatsListGroupProtocol {
    
    let name: String;
    weak var delegate: ChatsListViewDataSourceDelegate?;
    fileprivate var items: [ChatItemProtocol] = [];
    let dispatcher: QueueDispatcher;
    
    let canOpenChat: Bool;
    
    init(name: String, dispatcher: QueueDispatcher, delegate: ChatsListViewDataSourceDelegate, canOpenChat: Bool) {
        self.name = name;
        self.delegate = delegate;
        self.dispatcher = dispatcher;
        self.canOpenChat = canOpenChat;
        
        NotificationCenter.default.addObserver(self, selector: #selector(chatOpened), name: DBChatStore.CHAT_OPENED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(chatClosed), name: DBChatStore.CHAT_CLOSED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(chatUpdated), name: DBChatStore.CHAT_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);

        dispatcher.async {
            DispatchQueue.main.sync {
                self.items = DBChatStore.instance.getChats().filter(self.isAccepted(chat:)).map(self.newChatItem(chat:)).filter({ (item) -> Bool in
                    item != nil
                }).map({ item -> ChatItemProtocol in item! }).sorted(by: self.chatsSorter);
                print("loaded", self.items.count, "during initialization of the view");
                self.delegate?.reload();
            }
        }
    }
    
    var count: Int {
        return items.count;
    }
    
    func newChatItem(chat: DBChatProtocol) -> ChatItemProtocol? {
        return nil;
    }
    
    func getItem(at index: Int) -> ChatsListItemProtocol? {
        return items[index];
    }
    
    func forChat(_ chat: DBChatProtocol, execute: @escaping (ChatItemProtocol) -> Void) {
        self.dispatcher.async {
            let items = DispatchQueue.main.sync { return self.items; };
            guard let item = items.first(where: { (it) -> Bool in
                it.chat.id == chat.id
            }) else {
                return;
            }
            
            execute(item);
        }
    }
    
    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ChatItemProtocol) -> Void) {
        self.dispatcher.async {
            let items = DispatchQueue.main.sync { return self.items; };
            guard let item = items.first(where: { (it) -> Bool in
                it.chat.account == account && it.chat.jid.bareJid == jid
            }) else {
                return;
            }
            
            execute(item);
        }
    }
    
    func chatsSorter(i1: ChatItemProtocol, i2: ChatItemProtocol) -> Bool {
        return i1.lastMessageTs.compare(i2.lastMessageTs) == .orderedDescending;
    }

    @objc func avatarChanged(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
            return;
        }
        self.updateItem(for: account, jid: jid, executeIfExists: nil, executeIfNotExists: nil);
    }
    
    func isAccepted(chat: DBChatProtocol) -> Bool {
        return false;
    }
    
    @objc func chatOpened(_ notification: Notification) {
        guard let opened = notification.object as? DBChatProtocol, isAccepted(chat: opened) else {
            return;
        }
        
        addItem(chat: opened);
    }
    
    @objc func chatClosed(_ notification: Notification) {
        guard let opened = notification.object as? DBChatProtocol, isAccepted(chat: opened) else {
            return;
        }
        
        dispatcher.async {
            var items = DispatchQueue.main.sync { return self.items };
            guard let idx = items.firstIndex(where: { (item) -> Bool in
                item.chat.id == opened.id
            }) else {
                return;
            }
            
            _ = items.remove(at: idx);
            
            DispatchQueue.main.async {
                self.items = items;
                self.delegate?.itemsRemoved(at: IndexSet(integer: idx), inParent: self);
            }
        }
    }
    
    @objc func chatUpdated(_ notification: Notification) {
        guard let e = notification.object as? DBChatProtocol, isAccepted(chat: e) else {
            return;
        }
        
        dispatcher.async {
            var items = DispatchQueue.main.sync { return self.items };
            guard let oldIdx = items.firstIndex(where: { (item) -> Bool in
                item.chat.id == e.id;
            }) else {
                return;
            }
            
            let item = items.remove(at: oldIdx);
            
            let newIdx = items.firstIndex(where: { (it) -> Bool in
                it.lastMessageTs.compare(item.lastMessageTs) == .orderedAscending;
            }) ?? items.count;
            items.insert(item, at: newIdx);
            
            if oldIdx == newIdx {
                DispatchQueue.main.async {
                    self.delegate?.itemChanged(item: item);
                }
            } else {
                DispatchQueue.main.async {
                    self.items = items;
                    self.delegate?.itemMoved(from: oldIdx, fromParent: self, to: newIdx, toParent: self);
                    self.delegate?.itemChanged(item: item);
                }
            }
        }
    }

    func addItem(chat opened: DBChatProtocol) {
        dispatcher.async {
            print("opened chat account =", opened.account, ", jid =", opened.jid)
            
            var items = DispatchQueue.main.sync { return self.items };
            
            guard items.firstIndex(where: { (item) -> Bool in
                item.chat.id == opened.id
            }) == nil else {
                return;
            }
            
            guard let item = self.newChatItem(chat: opened) else {
                return;
            }
            let idx = items.firstIndex(where: { (it) -> Bool in
                it.lastMessageTs.compare(item.lastMessageTs) == .orderedAscending;
            }) ?? items.count;
            items.insert(item, at: idx);
            
            DispatchQueue.main.async {
                self.items = items;
                self.delegate?.itemsInserted(at: IndexSet(integer: idx), inParent: self);
            }
        }
    }
    
    func removeItem(for account: BareJID, jid: BareJID) {
        dispatcher.async {
            var items = DispatchQueue.main.sync { return self.items };
            guard let idx = items.firstIndex(where: { (item) -> Bool in
                item.chat.account == account && item.chat.jid.bareJid == jid;
            }) else {
                return;
            }
            
            _ = items.remove(at: idx);
            
            DispatchQueue.main.async {
                self.items = items;
                self.delegate?.itemsRemoved(at: IndexSet(integer: idx), inParent: self);
            }
        }
    }
    
    func updateItem(for account: BareJID, jid: BareJID, onlyIf: ((ChatItemProtocol)->Bool)? = nil, executeIfExists: ((ChatItemProtocol) -> Void)?, executeIfNotExists: (()->Void)?) {
        dispatcher.async {
            let items = DispatchQueue.main.sync { return self.items };
            guard let idx = items.firstIndex(where: { (item) -> Bool in
                item.chat.account == account && item.chat.jid.bareJid == jid
            }) else {
                executeIfNotExists?();
                return;
            }
            
            let item = self.items[idx];
            if let filter = onlyIf {
                guard filter(item) else {
                    return
                }
            }
            if let chat = item.chat as? DBChatStore.DBChat, chat.remoteChatState == .composing {
                chat.update(remoteChatState: .active);
            }
            
            executeIfExists?(item);
            
            DispatchQueue.main.async {
                self.delegate?.itemChanged(item: item);
            }
        }
    }
}
