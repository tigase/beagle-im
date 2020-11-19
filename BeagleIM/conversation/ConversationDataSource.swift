//
//  ConversationDataSource.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 18/11/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import Foundation

protocol ConversationDataSourceDelegate: class {
    
    var conversation: Conversation! { get }
    
    func itemAdded(at: IndexSet);

    func itemsUpdated(forRowIndexes: IndexSet);
    
    func itemUpdated(indexPath: IndexPath);
    
    func itemsRemoved(at: IndexSet);
    
    func itemsReloaded();
    
    func isVisible(row: Int) -> Bool;
    
    func scrollRowToVisible(_ row: Int);
}

public enum ConversationLoadType {
    case unread(overhead: Int)
    case before(entry: ConversationEntry, limit: Int)
    
    var markUnread: Bool {
        switch self {
        case .unread(_):
            return true;
        default:
            return false;
        }
    }
}

class ConversationDataSource {

    enum State {
        case uninitialized
        case loading
        case loaded
    }
    
    private var store = MessagesStore();
    private let queue = DispatchQueue(label: "chat_datasource");
    
    weak var delegate: ConversationDataSourceDelegate?;
    
    private var state: State = .uninitialized;
    
    var count: Int {
        return store.count;
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(messageNew), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated(_:)), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved(_:)), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
        if #available(macOS 10.15, *) {
            NotificationCenter.default.addObserver(self, selector: #selector(settingChanged), name: Settings.CHANGED, object: nil);
        }
    }
    
    @objc fileprivate func messageNew(_ notification: NSNotification) {
        guard let item = notification.object as? ConversationEntry else {
            return;
        }
        guard let conversation = delegate?.conversation else {
            return;
        }
        guard conversation.id == (item.conversation as? Conversation)?.id else {
            return;
        }
        
        DispatchQueue.main.async {
            let isNewestMessageVisible = self.delegate?.isVisible(row: 0) ?? false;
            self.add(item: item);
//            , completionHandler: { [weak self] (newRows, unread) in
//                if isNewestMessageVisible && newRows.contains(0) {
//                    self?.delegate?.scrollRowToVisible(0);
//                }
//            });
        }
    }
    
    @objc fileprivate func messageUpdated(_ notification: Notification) {
        guard let item = notification.object as? ConversationEntry else {
            return;
        }
        guard let conversation = delegate?.conversation else {
            return;
        }
        guard conversation.id == (item.conversation as? Conversation)?.id else {
            return;
        }
        
        DispatchQueue.main.async {
            let isNewestMessageVisible = self.delegate?.isVisible(row: 0) ?? false;
            self.update(item: item, completionHandler: nil);
//            , completionHandler: { [weak self] (newRows) in
//                if isNewestMessageVisible && newRows.contains(0) {
//                    self?.delegate?.scrollRowToVisible(0);
//                }
//            });
        }
    }
    
    @objc fileprivate func messageRemoved(_ notification: Notification) {
        guard let item = notification.object as? ConversationEntry else {
            return;
        }
        guard let conversation = delegate?.conversation else {
            return;
        }
        guard conversation.id == (item.conversation as? Conversation)?.id else {
            return;
        }
        remove(item: item);
    }

    @available(macOS 10.15, *)
    @objc func settingChanged(_ notification: Notification) {
        guard let setting = notification.object as? Settings, setting == .linkPreviews else {
            return;
        }
        // FIXME:!!!
//        self.refreshData(unread: 0, completionHandler: nil);
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
    
    // should be called from the main dispatch queue!!
    func loadItems(_ type: ConversationLoadType) {
        // do not load if load is already in progress..
        guard state != .loading, let conversation = self.delegate?.conversation else {
            return;
        }
        state = .loading;
        queue.async {
            let items: [ConversationEntry] = conversation.loadItems(type);
            self.add(items: items, markUnread: type.markUnread);
            DispatchQueue.main.async {
                self.state = .loaded;
            }
        }
    }
    
    private func add(item: ConversationEntry) {
        queue.async {
            self.add(items: [item], markUnread: false);
        }
    }
    
    func getItem(at row: Int) -> ConversationEntry? {
        let store = self.store;
        let item = store.item(at: row);
        if item != nil {
            if row >= (store.count - 10) && row < store.count {
                if let it = store.item(at: store.count - 1) {
                    self.loadItems(.before(entry: it, limit: 100))
                }
            }
        } else {
            print("no item for row:", row, "index:", 0, "store.count:", store.count);
        }
        return item;
    }
    
    func getItem(withId id: Int) -> ConversationEntry? {
        return self.store.items.first { (item) -> Bool in
            return item.id == id;
        };
    }
    
    func getItems(fromId: Int, toId: Int, inRange: NSRange) -> [ConversationEntry] {
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
    
    func remove(item: ConversationEntry) {
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
                if oldIdx > 0 && self.store.count > 0 {
                    self.delegate?.itemUpdated(indexPath: IndexPath(item: oldIdx - 1, section: 0));
                }
            }
        }
    }

    func update(item: ConversationEntry, completionHandler: ((IndexSet)->Void)?) {
        queue.async {
            var store = DispatchQueue.main.sync { return self.store; };
            
            // do something when item needs to be updated, ie. marked as delivered or read..
            //            items[idx] = item;
            guard let oldIdx = store.remove(item: item) else {
                if let newIdx = store.add(item: item) {
                    DispatchQueue.main.async {
                        self.store = store;
                        self.delegate?.itemAdded(at: IndexSet([newIdx]));
                        completionHandler?(IndexSet([newIdx]));
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
                        self.delegate?.itemAdded(at: IndexSet([newIdx]));
                        completionHandler?(IndexSet([newIdx]));
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

    
    func isAnyMatching(_ fn: (ConversationEntry)->Bool, in range: Range<Int>) -> Bool {
        for i in range {
            if let item = store.item(at: i), fn(item) {
                return true;
            }
        }
        return false;
    }
    
    // should be called from internal queue!
    private func add(items newItems: [ConversationEntry], markUnread: Bool) {
        var store = DispatchQueue.main.sync { return self.store };
        var newRows = [Int]();
        var oldestUnreadIdx: Int?;
        for item in newItems {
            if var idx = store.add(item: item, force: false) {
                while newRows.contains(idx) {
                    idx = idx + 1;
                }
                newRows.append(idx);
                if markUnread && (item as? ConversationEntryWithSender)?.state.isUnread ?? false {
                    if let current = oldestUnreadIdx {
                        if current < idx {
                            oldestUnreadIdx = idx;
                        }
                    } else {
                        oldestUnreadIdx = idx;
                    }
                }
            }
        }
            
        if let oldestUnreadIdx = oldestUnreadIdx {
            let item = store.item(at: oldestUnreadIdx)!;
            if var unreadIdx = store.add(item: ConversationMessageSystem(nextItem: item, kind: .unreadMessages), force: true) {
                while newRows.contains(unreadIdx) {
                    unreadIdx = unreadIdx + 1;
                }
                newRows.append(unreadIdx);
            }
        }
        
        DispatchQueue.main.async {
            self.store = store;
            self.delegate?.itemAdded(at: IndexSet(newRows));
            if let oldestUnreadIdx = oldestUnreadIdx {
                self.delegate?.scrollRowToVisible(oldestUnreadIdx);
            }
        }
    }
    
    struct MessagesStore {

        var knownItems: Set<Int>;
        var items: [ConversationEntry] = [];
        var count: Int {
            return items.count;
        }
        
        init() {
            self.knownItems = Set<Int>();
        }
        
        init(items: [ConversationEntry]) {
            self.items = items;
            self.knownItems = Set<Int>(items.map({ it -> Int in return it.id; }));
        }
        
        func item(at row: Int) -> ConversationEntry? {
            guard row < self.items.count && row >= 0 else {
                return nil;
            }
            return self.items[row];
        }
        
        func indexOf(itemId id: Int) -> Int? {
            guard let idx = self.items.firstIndex(where: { (item) -> Bool in
                return item.id == id && !(item is ConversationMessageSystem);
            }) else {
                return nil;
            }
            return idx;
        }
                
        mutating func remove(item: ConversationEntry) -> Int? {
            guard let idx = self.items.firstIndex(where: { (it) -> Bool in
                return it.id == item.id && !(item is ConversationMessageSystem);
            }) else {
                return nil;
            }
            self.items.remove(at: idx);
            self.knownItems.remove(item.id);
            return idx;
        }
        
        mutating func add(item: ConversationEntry, force: Bool = false) -> Int? {
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
        
        func compare(_ it1: ConversationEntry, _ it2: ConversationEntry) -> ComparisonResult {
            let unsent1 = (it1 as? ConversationEntryWithSender)?.state.isUnsent ?? false;
            let unsent2 = (it2 as? ConversationEntryWithSender)?.state.isUnsent ?? false;
            if unsent1 == unsent2 {
                let result = it1.timestamp.compare(it2.timestamp);
                guard result == .orderedSame else {
                    return result;
                }
                return it1.id < it2.id ? .orderedAscending : .orderedDescending;
            } else {
                if unsent1 {
                    return .orderedDescending;
                }
                return .orderedAscending;
            }
        }
        
        mutating func trim() -> [Int] {
            guard items.count > 100 else {
                return [];
            }
            let removed = Array(100..<items.count);
            self.items = Array(items[0..<100]);
            knownItems = Set(items.map({ it -> Int in return it.id; }));
            return removed;
        }

        fileprivate func searchPosition(for item: ConversationEntry) -> Int {
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
