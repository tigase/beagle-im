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
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved(_:)), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
        //NotificationCenter.default.addObserver(self, selector: #selector(messagesMarkedAsRead), name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: nil);
    }
    
    func getItem(at row: Int) -> ChatViewItemProtocol? {
        let store = self.store;
        let item = store.item(at: row);
        if item != nil {
            if row >= (store.count - (1 + 10)) && row < store.count {
                if let it = store.item(at: store.count - 1) {
                    loadItems(before: it.id, limit: 100, completionHandler: nil);
                }
//            } else if (row == 0) {
                // this causes issues!! we are loading row 0 during initial scrollRowToVisible!
                //trimStore();
            }
        } else {
            print("no item for row:", row, "index:", 0, "store.count:", store.count);
        }
        return item;
    }
    
    func getItem(withId id: Int) -> ChatViewItemProtocol? {
        return self.store.items.first { (item) -> Bool in
            return item.id == id;
        };
    }
    
    func getItems(fromId: Int, toId: Int, inRange: NSRange) -> [ChatViewItemProtocol] {
        let store = self.store;
        guard store.items.count > inRange.upperBound-1 else {
            return [];
        }
        let sublist = store.items[inRange.lowerBound..<inRange.upperBound];
        
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

    func add(items newItems: [ChatViewItemProtocol], markUnread: Bool = false, completionHandler: ((Int?)->Void)? = nil) {
        queue.async {
            let start = Date();
            var store = DispatchQueue.main.sync { return self.store };
            var newRows = [Int]();
            newItems.forEach({ item in
                guard var idx = store.add(item: item, force: false) else {
                    return;
                }
                while newRows.contains(idx) {
                    idx = idx + 1;
                }
                newRows.append(idx);
            })
            var firstUnread: Int?;
            if markUnread {
                if let idx = store.items.firstIndex(where: { (it) -> Bool in
                    return it.state != .outgoing_unsent && !it.state.isUnread;
                }) {
                    if idx > 0, let it = store.item(at: idx - 1) {
                        if var unreadIdx = store.add(item: SystemMessage(nextItem: it, kind: .unreadMessages), force: true) {
                            firstUnread = unreadIdx;
                            while newRows.contains(unreadIdx) {
                                unreadIdx = unreadIdx + 1;
                            }
                            newRows.append(unreadIdx);
                        }
                    }
                }
            }
            // duplicated row idx in new rows when "unread" is part of the set!!
            print("new rows:", newRows);
            print("added", newItems.count, store.count, "items in:", Date().timeIntervalSince(start))
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemAdded(at: IndexSet(newRows), shouldScroll: firstUnread == nil);
                completionHandler?(firstUnread);
            }
            
            //        if newItems.first(where: { item -> Bool in return item.state.isUnread }) != nil {
            //            if let delegate = self.delegate {
            //                if delegate.hasFocus {
            //                    //DBChatHistoryStore.instance.markAsRead(for: delegate.account, with: delegate.jid);
            //                }
            //            }
            //        }
            print("added items 2 in:", Date().timeIntervalSince(start));
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
            guard let oldIdx = store.remove(item: item) else {
                if let newIdx = store.add(item: item) {
                    DispatchQueue.main.async {
                        self.store = store;
                        self.delegate?.itemAdded(at: IndexSet([newIdx]), shouldScroll: true);
                    }
                }
                return;
            }

            let storeRemoved = store;
            if let newIdx = store.add(item: item) {
                DispatchQueue.main.async {
                    if oldIdx == newIdx {
                        self.store = store;
                        self.delegate?.itemUpdated(indexPath: IndexPath(item: newIdx, section: 0));
                    } else {
                        self.store = storeRemoved;
                        self.delegate?.itemsRemoved(at: IndexSet([oldIdx]));
                        if oldIdx > 0 && self.store.count > 0 {
                            self.delegate?.itemUpdated(indexPath: IndexPath(item: oldIdx - 1, section: 0));
                        }
                        self.store = store;
                        self.delegate?.itemAdded(at: IndexSet([newIdx]), shouldScroll: true);
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.store = storeRemoved;
                    self.delegate?.itemsRemoved(at: IndexSet([oldIdx]));
                    if oldIdx != 0 {
                        self.delegate?.itemUpdated(indexPath: IndexPath(item: oldIdx, section: 0));
                    }
                }
            }
            
            // notify that we finished
        }
    }
    
    func remove(item: ChatViewItemProtocol) {
        queue.async {
            var store = DispatchQueue.main.sync { return self.store; };
            
            // do something when item needs to be updated, ie. marked as delivered or read..
            //            items[idx] = item;
            guard let oldIdx = store.remove(item: item) else {
                return;
            }
            
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemsRemoved(at: IndexSet([oldIdx]));
                if oldIdx != 0 && self.store.count > 0 {
                    self.delegate?.itemUpdated(indexPath: IndexPath(item: oldIdx, section: 0));
                }
            }
        }
    }
    
    func refreshDataNoReload() {
        queue.async {
            let store = DispatchQueue.main.sync { return self.store; };
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
    
    @objc fileprivate func messageRemoved(_ notification: Notification) {
        guard let item = notification.object as? ChatViewItemProtocol else {
            return;
        }
        guard let account = delegate?.account, let jid = delegate?.jid else {
            return;
        }
        guard account == item.account && jid == item.jid else {
            return;
        }
        remove(item: item);
    }
    
    func refreshData(unread: Int, completionHandler: ((Int?)->Void)? = nil) {
        queue.async {
            DispatchQueue.main.async {
                self.store = MessagesStore(items: []);
                self.delegate?.itemsReloaded();
                self.loadItems(before: nil, limit: max(unread + 20, 100), unread: unread, completionHandler: { firstUnread in
//                    if unread > 0 {
//                        if let item = self.store.item(at: unread - 1) {
//                            let unreadItem = SystemMessage(nextItem: item, kind: .unreadMessages);
//                            self.add(items: [unreadItem], force: true, completionHandler: completionHandler);
//                        }
//                    } else {
                        completionHandler?(firstUnread);
//                    }
                });
            }
        }
    }
    
    fileprivate var loadInProgress = false;
    fileprivate var waitingToLoad: (()->Void)? = nil;
    
    func loadItems(before: Int? = nil, limit: Int, awaitIfInProgress: Bool = false, unread: Int = 0, completionHandler: ((Int?)->Void)? = nil) {
        guard let account = delegate?.account, let jid = delegate?.jid else {
            return;
        }
        guard !loadInProgress else {
            if awaitIfInProgress {
                waitingToLoad = { [weak self] in
                    self?.loadItems(before: before, limit: limit, awaitIfInProgress: awaitIfInProgress, unread: unread, completionHandler: completionHandler);
                }
            }
            return;
        }
        loadInProgress = true;
        
        self.queue.async {
            let start = Date();
            DBChatHistoryStore.instance.history(for: account, jid: jid, before: before, limit: limit) { dbItems in
                print("load completed in:", Date().timeIntervalSince(start));
                self.add(items: dbItems, markUnread: unread > 0, completionHandler: { (firstUnread) in
                    self.loadInProgress = false;
                    if self.waitingToLoad != nil {
                        self.waitingToLoad!();
                        self.waitingToLoad = nil;
                    }
                    completionHandler?(firstUnread);
                });
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
            guard row < self.items.count && row >= 0 else {
                return nil;
            }
            return self.items[row];
        }
        
        func indexOf(itemId id: Int) -> Int? {
            guard let idx = self.items.firstIndex(where: { (item) -> Bool in
                return item.id == id && !(item is SystemMessage);
            }) else {
                return nil;
            }
            return idx;
        }
                
        mutating func remove(item: ChatViewItemProtocol) -> Int? {
            guard let idx = self.items.firstIndex(where: { (it) -> Bool in
                return it.id == item.id && !(item is SystemMessage);
            }) else {
                return nil;
            }
            self.items.remove(at: idx);
            self.knownItems.remove(item.id);
            return idx;
        }
        
        mutating func add(item: ChatViewItemProtocol, force: Bool = false) -> Int? {
            guard !knownItems.contains(item.id) || force else {
                return nil;
            }
            knownItems.insert(item.id);
            guard !items.isEmpty else {
                items.append(item);
                return 0;
            }
            
            if compare(items.first!, item) == .orderedAscending {
                items.insert(item, at: 0);
                return 0;
            } else if let last = items.last {
                if compare(last, item) == .orderedDescending {
                    let idx = items.count;
                    // append to the end
                    items.append(item);
                    return idx;
                } else {
                    // insert into the items
                    var idx = searchPosition(for: item);
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
        
        func compare(_ it1: ChatViewItemProtocol, _ it2: ChatViewItemProtocol) -> ComparisonResult {
            let unsent1 = it1.state == .outgoing_unsent;
            let unsent2 = it2.state == .outgoing_unsent;
            if unsent1 == unsent2 {
                return it1.timestamp.compare(it2.timestamp);
            } else {
                if unsent1 {
                    return .orderedDescending;
                }
                return .orderedAscending;
            }
        }
        
        mutating func trim() -> [Int] {
            let removed = Array(100..<items.count);
            self.items = Array(items[0..<100]);
            knownItems = Set(items.map({ it -> Int in return it.id; }));
            return removed;
        }

        fileprivate func searchPosition(for item: ChatViewItemProtocol) -> Int {
            var start = 0;
            var end = items.count - 1;
            while start != end {
                let idx: Int = Int(ceil(Double(start+end)/2.0));
                if compare(items[idx], item) == .orderedAscending {
                    end = idx - 1;
                } else {
                    start = idx;
                }
            }
            return compare(items[start], item) == .orderedAscending  ? (start) : start + 1;
        }
    }
    
}
