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
    let dispatcher: QueueDispatcher;
    
    let canOpenChat: Bool;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    init(name: String, dispatcher: QueueDispatcher, delegate: ChatsListViewDataSourceDelegate, canOpenChat: Bool) {
        self.name = name;
        self.delegate = delegate;
        self.dispatcher = dispatcher;
        self.canOpenChat = canOpenChat;

        DBChatStore.instance.$conversations.throttle(for: 0.1, scheduler: self.dispatcher.queue, latest: true).sink(receiveValue: { [weak self] items in
            self?.update(items: items);
        }).store(in: &cancellables);
    }
    
    func update(items: [Conversation]) {
        let newItems = items.filter(self.isAccepted(chat:)).map({ conversation in ConversationItem(chat: conversation, timestamp: conversation.timestamp) }).sorted(by: { (c1,c2) in c1.timestamp > c2.timestamp });
        let oldItems = self.items;
        
        let diffs = newItems.difference(from: oldItems).inferringMoves();
        var removed: [Int] = [];
        var inserted: [Int] = [];
        var moved: [(Int,Int)] = [];
        for action in diffs {
            switch action {
            case .remove(let offset, _, let to):
                if let idx = to {
                    moved.append((offset, idx));
                } else {
                    removed.append(offset);
                }
            case .insert(let offset, _, let from):
                if from == nil {
                    inserted.append(offset);
                }
            }
        }
        
        guard (!removed.isEmpty) || (!moved.isEmpty) || (!inserted.isEmpty) else {
            return;
        }
        
        DispatchQueue.main.sync {
            self.items = newItems;
            self.delegate?.beginUpdates();
            if !removed.isEmpty {
                self.delegate?.itemsRemoved(at: IndexSet(removed), inParent: self);
            }
            for (from,to) in moved {
                self.delegate?.itemMoved(from: from, fromParent: self, to: to, toParent: self);
            }
            if !inserted.isEmpty {
                self.delegate?.itemsInserted(at: IndexSet(inserted), inParent: self);
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
        self.dispatcher.async {
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
        self.dispatcher.async {
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
