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
import Martin
import Combine

struct ConversationItem: ChatsListItemProtocol, Hashable {
    
    static func == (lhs: ConversationItem, rhs: ConversationItem) -> Bool {
        return lhs.chat.id == rhs.chat.id;
    }
    
    var name: String {
        return chat.displayName;
    }
    let chat: Conversation;
    
    let timestamp: Date;
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(chat.id);
    }
}

class ChatsListGroupAbstractChat: ChatsListGroupProtocol {
    
    let name: String;
    weak var delegate: ChatsListViewDataSourceDelegate?;
    fileprivate var items: [ConversationItem] = [];
    let queue: DispatchQueue;
    
    let canOpenChat: Bool;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    init(name: String, queue: DispatchQueue, delegate: ChatsListViewDataSourceDelegate, canOpenChat: Bool) {
        self.name = name;
        self.delegate = delegate;
        self.queue = queue;
        self.canOpenChat = canOpenChat;

        DBChatStore.instance.conversationsPublisher.throttleFixed(for: 0.1, scheduler: self.queue, latest: true).sink(receiveValue: { [weak self] items in
            self?.update(items: items);
        }).store(in: &cancellables);
    }
    
    func update(items: [Conversation]) {
        let newItems = items.filter(self.isAccepted(chat:)).map({ conversation in ConversationItem(chat: conversation, timestamp: conversation.timestamp) }).sorted(by: { (c1,c2) in c1.timestamp > c2.timestamp });
        let oldItems = self.items;
        
        let changes: [CollectionChange] = newItems.calculateChanges(from: oldItems);
        
        guard !changes.isEmpty else {
            return;
        }
        
        DispatchQueue.main.sync {
            self.items = newItems;
            self.delegate?.beginUpdates();
            
            for change in changes {
                switch change {
                case .insert(let idx):
                    self.delegate?.itemsInserted(at: IndexSet(integer: idx), inParent: self);
                case .remove(let idx):
                    self.delegate?.itemsRemoved(at: IndexSet(integer: idx), inParent: self);
                case .move(let from, let to):
                    self.delegate?.itemMoved(from: from, fromParent: self, to: to, toParent: self);
                }
            }
            self.delegate?.endUpdates();
        }
    }
    
    var count: Int {
        return items.count;
    }
    
    func getItem(at index: Int) -> ChatsListItemProtocol? {
        return items[index];
    }
    
    func forChat(_ chat: Conversation, execute: @escaping (ConversationItem) -> Void) {
        self.queue.async {
            let items = self.items;
            guard let item = items.first(where: { (it) -> Bool in
                it.chat.id == chat.id
            }) else {
                return;
            }

            execute(item);
        }
    }

    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ConversationItem) -> Void) {
        self.queue.async {
            let items = self.items;
            guard let item = items.first(where: { (it) -> Bool in
                it.chat.account == account && it.chat.jid == jid
            }) else {
                return;
            }

            execute(item);
        }
    }

    func isAccepted(chat: Conversation) -> Bool {
        return false;
    }
    
}
