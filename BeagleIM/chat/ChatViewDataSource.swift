//
// ChatViewDataSource.swift
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

class ChatViewDataSource {
    
    // we are keeping all items from the time view is opened and we are loading older items if needed
    //fileprivate var items = [ChatViewItemProtocol]();
    fileprivate var store = MessagesStore(items: []);
    
    fileprivate var queue = DispatchQueue(label: "chat_datasource");
    
    weak var delegate: ChatViewDataSourceDelegate?;
    
    var count: Int {
        return store.count;
        //return items.count;
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(messageNew), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated(_:)), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
        //NotificationCenter.default.addObserver(self, selector: #selector(messagesMarkedAsRead), name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: nil);
    }
    
    func getItem(at row: Int) -> ChatViewItemProtocol? {
        let item = store.item(at: row);
        if item != nil {
            if row >= (store.count - (1 + 10)) && row < store.count {
                if let it = store.item(at: store.count - 1) {
                    loadItems(before: it.id, limit: 100, completionHandler: nil);
                }
            } else if (row == 0) {
                trimStore();
            }
        } else {
            print("no item for row:", row, "index:", 0, "store.count:", store.count);
        }
        return item;
    }
    
    func getItems(fromId: Int, toId: Int, inRange: NSRange) -> [ChatViewItemProtocol] {
        let sublist = store.items[inRange.lowerBound...inRange.upperBound];
        
        let edges = sublist.filter { (item) -> Bool in
            return item.id == fromId || item.id == toId;
        }.sorted { (i1, i2) -> Bool in
            return i1.timestamp.compare(i2.timestamp) == .orderedAscending;
        };
        
        let start = edges[0].timestamp;
        let end = edges.count == 1 ? start : edges[1].timestamp;

        return sublist.filter { (i) -> Bool in
            (i.timestamp.compare(start) != .orderedAscending)
            &&
            (i.timestamp.compare(end) != .orderedDescending)
        }.sorted { (i1, i2) -> Bool in
            return i1.timestamp.compare(i2.timestamp) == .orderedAscending;
        };
    }
        
    func add(item: ChatViewItemProtocol) {
        add(items: [item]);
    }

    func add(items newItems: [ChatViewItemProtocol], completionHandler: (()->Void)? = nil) {
        queue.async {
            let start = Date();
            var store = DispatchQueue.main.sync { return self.store };
            var newRows = [Int]();
            newItems.forEach({ item in
                guard let idx = store.add(item: item) else {
                    return;
                }
                newRows.append(idx);
            })
            print("added items in:", Date().timeIntervalSince(start))
            DispatchQueue.main.async {
                self.store = store;
                if newItems.count > 3030 {
                    for i in 3028...3031 {
                        print("item:", i, ", ts:", newItems[i].timestamp, ", id:", newItems[i].id);
                    }
                }
                self.delegate?.itemAdded(at: IndexSet(newRows));
            }
            
            if newItems.first(where: { item -> Bool in return item.state.isUnread }) != nil {
                if let delegate = self.delegate {
                    if delegate.hasFocus {
                        DBChatHistoryStore.instance.markAsRead(for: delegate.account, with: delegate.jid);
                    }
                }
            }
            print("added items 2 in:", Date().timeIntervalSince(start));
            completionHandler?();
        }
    }

    func update(itemId: Int, data: [String:Any]) {
        queue.async {
            let store = DispatchQueue.main.sync { return self.store; };
            if let idx = store.indexOf(itemId: itemId) {
                // notify that we finished
                DispatchQueue.main.async {
                    self.delegate?.itemUpdated(indexPath: IndexPath(item: idx, section: 0));
                }
            }
        }
    }

    func update(item: ChatViewItemProtocol) {
        queue.async {
            var store = DispatchQueue.main.sync { return self.store; };
            
            // do something when item needs to be updated, ie. marked as delivered or read..
            //            items[idx] = item;
            guard let idx = store.update(item: item) else {
                return;
            }
            
            // notify that we finished
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemUpdated(indexPath: IndexPath(item: idx, section: 0));
            }
        }
    }
    
    func refreshDataNoReload() {
        queue.async {
            var store = DispatchQueue.main.sync { return self.store; };
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemsReloaded();
            }
        }
    }
    
    func trimStore() {
        guard store.count > 100 else {
            return;
        }
        
        queue.async {
            var store = DispatchQueue.main.sync { return self.store; };
            let arr = store.trim();
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemsRemoved(at: IndexSet(arr));
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
        queue.async {
            _ = DispatchQueue.main.sync { self.store };
            DispatchQueue.main.async {
                self.store = MessagesStore(items: []);
                self.delegate?.itemsReloaded();
            }
            DispatchQueue.global().async {
                self.loadItems(before: nil, limit: 100);
            }
        }
    }
    
    fileprivate var loadInProgress = false;
    fileprivate var waitingToLoad: (()->Void)? = nil;
    
    func loadItems(before: Int? = nil, limit: Int, awaitIfInProgress: Bool = false, completionHandler: (()->Void)? = nil) {
        guard let account = delegate?.account, let jid = delegate?.jid else {
            return;
        }
        guard !loadInProgress else {
            if awaitIfInProgress {
                waitingToLoad = { [weak self] in
                    self?.loadItems(before: before, limit: limit, awaitIfInProgress: awaitIfInProgress, completionHandler: completionHandler);
                }
            }
            return;
        }
        loadInProgress = true;
        
        self.queue.async {
            let start = Date();
            DBChatHistoryStore.instance.getHistory(for: account, jid: jid, before: before, limit: limit) { items in
                print("load completed in:", Date().timeIntervalSince(start));
                self.add(items: items, completionHandler: completionHandler);
                DispatchQueue.main.async {
                    self.loadInProgress = false;
                    if self.waitingToLoad != nil {
                        self.waitingToLoad!();
                        self.waitingToLoad = nil;
                    }
                }
            }
        }
    }
    
    struct MessagesStore {

        var knownItems: Set<Int>;
        var items: [ChatViewItemProtocol] = [];
        var count: Int {
            return items.count;
        }
        
        init(items: [ChatViewItemProtocol]) {
            self.items = items;
            self.knownItems = Set<Int>(items.map({ it -> Int in return it.id; }));
        }
        
        func item(at row: Int) -> ChatViewItemProtocol? {
            return self.items[row];
        }
        
        func indexOf(itemId id: Int) -> Int? {
            guard let idx = self.items.firstIndex(where: { (item) -> Bool in
                return item.id == id;
            }) else {
                return nil;
            }
            return idx;
        }
        
        mutating func update(item: ChatViewItemProtocol) -> Int? {
            guard let idx = self.items.firstIndex(where: { (it) -> Bool in
                return it.id == item.id;
            }) else {
                return nil;
            }
            self.items[idx] = item;
            return idx;
        }
        
        mutating func add(item: ChatViewItemProtocol) -> Int? {
            guard !knownItems.contains(item.id) else {
                return nil;
            }
            knownItems.insert(item.id);
            guard !items.isEmpty else {
                items.append(item);
                return 0;
            }
            
            if items.first!.timestamp < item.timestamp {
                items.insert(item, at: 0);
                return 0;
            } else if let last = items.last {
                if last.timestamp > item.timestamp {
                    let idx = items.count;
                    // append to the end
                    items.append(item);
                    return idx;
                } else  {
                    // insert into the items
                    var idx = searchPosition(byTimestamp: item.timestamp);
                    if idx == (items.count - 1) && items[idx].timestamp == item.timestamp {
                        idx = idx + 1;
//                        if items[idx].id < item.id {
//                            idx = idx + 1;
//                        }
                    }
                    items.insert(item, at: idx);
                    return idx;
                }
            } else {
                return nil;
            }
        }
        
        mutating func trim() -> [Int] {
            let removed = Array(100..<items.count);
            self.items = Array(items[0..<100]);
            knownItems = Set(items.map({ it -> Int in return it.id; }));
            return removed;
        }

        fileprivate func searchPosition(byTimestamp timestamp: Date) -> Int {
            var start = 0;
            var end = items.count - 1;
            while start != end {
                let idx: Int = Int(ceil(Double(start+end)/2.0));
                if items[idx].timestamp < timestamp {
                    end = idx - 1;
                } else {
                    start = idx;
                }
            }
            return items[start].timestamp < timestamp  ? (start - 1) : start;
        }
    }
    
}
