//
//  ChatViewDataSource.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 21.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ChatViewDataSource {
    
    // we are keeping all items from the time view is opened and we are loading older items if needed
    fileprivate var items = [ChatViewItemProtocol]();
    
    fileprivate var queue = DispatchQueue(label: "chat_datasource");
    
    weak var delegate: ChatViewDataSourceDelegate?;
    
    var count: Int {
        return items.count;
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(messageNew), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated(_:)), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
        //NotificationCenter.default.addObserver(self, selector: #selector(messagesMarkedAsRead), name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: nil);
    }
    
    func getItem(at row: Int) -> ChatViewItemProtocol {
        return items[row];
    }
    
    func add(item: ChatViewItemProtocol) {
        add(items: [item]);
    }
    
    func add(items newItems: [ChatViewItemProtocol]) {
        queue.async {
            var items = DispatchQueue.main.sync { return self.items; }
            var newRows = [Int]();
            //            var appendedItemsCounter = 0;
            newItems.forEach({ item in
                guard items.index(where: { (it) -> Bool in
                    it.id == item.id;
                }) == nil else {
                    return;
                }
                
                let idx = items.index(where: { it -> Bool in it.timestamp.compare(item.timestamp) == .orderedAscending });
                if idx != nil {
                    if (items[idx!].id == item.id) {
                        // we skip items which are already there
                        return;
                    }
                    items.insert(item, at: idx!);
                } else {
                    items.append(item);
                }
                newRows.append(idx ?? (items.count - 1));
                //                appendedItemsCounter = appendedItemsCounter.advanced(by: 1);
            })
            DispatchQueue.main.async {
                self.items = items;
                self.delegate?.itemAdded(at: IndexSet(newRows));
            }
            
            if newItems.first(where: { item -> Bool in return item.state.isUnread }) != nil {
                if let delegate = self.delegate {
                    if delegate.hasFocus {
                        DBChatHistoryStore.instance.markAsRead(for: delegate.account, with: delegate.jid);
                    }
                }
            }
        }
    }
    
    func update(itemId: Int, data: [String:Any]) {
        queue.async {
            let items = DispatchQueue.main.sync { return self.items; }
            guard let idx = items.index(where: { (it) -> Bool in
                it.id == itemId;
            }) else {
                return;
            }
            // do something when item needs to be updated, ie. marked as delivered or read..
            let item = items[idx];
            
            // notify that we finished
            DispatchQueue.main.async {
                self.delegate?.itemUpdated(indexPath: IndexPath(item: idx, section: 0));
            }
        }
    }

    func update(item: ChatViewItemProtocol) {
        queue.async {
            var items = DispatchQueue.main.sync { return self.items; }
            guard let idx = items.index(where: { (it) -> Bool in
                it.id == item.id;
            }) else {
                return;
            }
            // do something when item needs to be updated, ie. marked as delivered or read..
            items[idx] = item;
            
            // notify that we finished
            DispatchQueue.main.async {
                self.items = items;
                self.delegate?.itemUpdated(indexPath: IndexPath(item: idx, section: 0));
            }
        }
    }

    @objc fileprivate func messageNew(_ notification: NSNotification) {
        guard let item = notification.object as? ChatViewItemProtocol else {
            return;
        }
        guard let account = delegate?.account, let jid = delegate?.jid else {
            return;
        }
        guard account == item.account && jid == item.jid else {
            return;
        }
        add(item: item);
    }
    
    @objc fileprivate func messageUpdated(_ notification: Notification) {
        guard let item = notification.object as? ChatViewItemProtocol else {
            return;
        }
        guard let account = delegate?.account, let jid = delegate?.jid else {
            return;
        }
        guard account == item.account && jid == item.jid else {
            return;
        }
        update(item: item);
    }
    
    func refreshData() {
        DispatchQueue.main.async {
            self.items = [];
            self.delegate?.itemsReloaded();
        }
        DispatchQueue.global().async {
            self.loadItems(before: nil, limit: 20);
        }
    }
    
    func loadItems(before: Int? = nil, limit: Int) {
        guard let account = delegate?.account, let jid = delegate?.jid else {
            return;
        }
        DBChatHistoryStore.instance.getHistory(for: account, jid: jid, before: before, limit: limit) { items in
            self.add(items: items);
        }
    }
}
