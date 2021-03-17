//
//  ConversationDataSource.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 18/11/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import Foundation
import Combine

protocol ConversationDataSourceDelegate: class {
    
    var conversation: Conversation! { get }
    
    func itemAdded(at: IndexSet);

    func itemsUpdated(forRowIndexes: IndexSet);
    
    func itemUpdated(indexPath: IndexPath);
    
    func itemsRemoved(at: IndexSet);
    
    func itemsReloaded();
    
    func isVisible(row: Int) -> Bool;
    
    func scrollRowToVisible(_ row: Int);
    
    func markAsReadUpToNewestVisibleRow();
}

public enum ConversationLoadType {
    case with(id: Int, overhead: Int)
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
    
    private var store: [ConversationEntry] = [];
    private let queue = DispatchQueue(label: "chat_datasource");
    
    weak var delegate: ConversationDataSourceDelegate? {
        didSet {
            delegate?.conversation.markersPublisher.receive(on: self.queue).sink(receiveValue: { [weak self] markers in
                self?.update(markers: markers);
            }).store(in: &cancellables);
        }
    }
    
    public var defaultPageSize = 100;
    
    private var state: State = .uninitialized;
    
    var count: Int {
        return store.count;
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    private var knownItems: Set<Int> = [];
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(messageNew), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated(_:)), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved(_:)), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
        Settings.$linkPreviews.dropFirst().sink(receiveValue: { [weak self] _ in
            guard let that = self else {
                return;
            }
            that.loadItems(.unread(overhead: that.count))
        }).store(in: &cancellables);
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
        
        self.add(item: item);
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
        
        self.update(item: item);
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
            self.add(items: items, scrollTo: .from(loadType: type), completionHandler: {
                self.state = .loaded;
            });
        }
    }
    
    private var markers: [ChatMarker] = [];
    
    private static func sortConversationEntries(it1: ConversationEntry, it2: ConversationEntry) -> Bool {
        let unsent1 = (it1 as? ConversationEntryWithSender)?.state.isUnsent ?? false;
        let unsent2 = (it2 as? ConversationEntryWithSender)?.state.isUnsent ?? false;
        if unsent1 == unsent2 {
            let result = it1.timestamp.compare(it2.timestamp);
            guard result == .orderedSame else {
                return result == .orderedAscending ? false : true;
            }
            if it1.id == it2.id || (it1.id == -1 || it2.id == -1) {
                if let i1 = it1 as? ConversationEntryRelated {
                    switch i1.order {
                    case .first:
                        return false;
                    case .last:
                        return true;
                    }
                }
                if let i2 = it2 as? ConversationEntryRelated {
                    switch i2.order {
                    case .first:
                        return true;
                    case .last:
                        return false;
                    }
                }
            }
            // this does not work well if id is -1..
            return it1.id < it2.id ? false : true;
        } else {
            if unsent1 {
                return false;
            }
            return true;
        }
    }
    
    private func update(markers: [ChatMarker]) {
        guard let conversation = self.delegate?.conversation else {
            return;
        }
        
        let oldStore = DispatchQueue.main.sync { return self.store; };
        var store = oldStore.filter({ !($0 is ConversationMarker)});
        store.append(contentsOf: markers.map({ ConversationMarker(markedMessageId: -1, conversationKey: conversation, timestamp: $0.timestamp, sender: .buddy(conversation: conversation), marker: $0.type) }));
        store = store.sorted(by: ConversationDataSource.sortConversationEntries);
        
        let changes = store.calculateChanges(from: oldStore);
        
        DispatchQueue.main.async {
            self.store = store;
//            if changes.removed == 0 && changes.inserted == 0 {
//                self.delegate?.itemsUpdated(forRowIndexes: <#T##IndexSet#>)
//            } else {
                self.delegate?.itemsRemoved(at: changes.removed);
                self.delegate?.itemAdded(at: changes.inserted);
//            }
        }
    }
 
    private func add(item: ConversationEntry) {
        queue.async {
            self.add(items: [item], scrollTo: .none, completionHandler: nil);
        }
    }
    
    func getItem(at row: Int) -> ConversationEntry? {
        guard store.count > row else {
            return nil;
        }
        let store = self.store;
        let item = store[row];
        // load more if remaining equals ChatMarkers!
        if row >= (store.count - 1) && row < store.count {
            if store.count > 0 {
                let it = store[store.count - 1];
                self.loadItems(.before(entry: it, limit: self.defaultPageSize))
            }
        }
        return item;
    }
    
    func getItem(withId id: Int) -> ConversationEntry? {
        return self.store.first { (item) -> Bool in
            return item.id == id;
        };
    }
    
    func getItems(fromId: Int, toId: Int, inRange: NSRange) -> [ConversationEntry] {
        let store = self.store;
        guard store.count > inRange.upperBound-1 else {
            return [];
        }
        let sublist = store[inRange.lowerBound..<inRange.upperBound];
        
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
            guard self.knownItems.contains(item.id), let oldIdx = store.firstIndex(of: item) else {
                return;
            }
            self.knownItems.remove(item.id);
            store.remove(at: oldIdx);
            
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemsRemoved(at: IndexSet([oldIdx]));
                if oldIdx > 0 && self.store.count > 0 {
                    self.delegate?.itemUpdated(indexPath: IndexPath(item: oldIdx - 1, section: 0));
                }
            }
        }
    }

    func update(item: ConversationEntry) {
        queue.async {
            let oldStore = DispatchQueue.main.sync { return self.store; };
            
            var store = oldStore;
            // do something when item needs to be updated, ie. marked as delivered or read..
            //            items[idx] = item;
            if self.knownItems.contains(item.id), let oldIdx = store.firstIndex(of: item) {
                store.remove(at: oldIdx);
            } else {
                self.knownItems.insert(item.id);
            }
            store.append(item);
            store = store.sorted(by: ConversationDataSource.sortConversationEntries(it1:it2:));

            let changes = store.calculateChanges(from: oldStore);
            
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemsRemoved(at: changes.removed);
                self.delegate?.itemAdded(at: changes.inserted);
            }
        }
    }

    func trimStore() {
        guard store.count > 100 else {
            return;
        }
        
        queue.async {
            let oldStore = DispatchQueue.main.sync { return self.store; };
            guard oldStore.count > 100 else {
                return;
            }
            let store = Array(oldStore[0..<100]);
            let changes = store.calculateChanges(from: oldStore);
            self.knownItems = Set(store.map({ $0.id }));
            
            DispatchQueue.main.async {
                self.store = store;
                self.delegate?.itemsRemoved(at: changes.removed);
                self.delegate?.itemAdded(at: changes.inserted);
            }
        }
    }
    
    func isAnyMatching(_ fn: (ConversationEntry)->Bool, in range: Range<Int>) -> Bool {
        for i in range {
            let item = store[i]
            if fn(item) {
                return true;
            }
        }
        return false;
    }
    
    // should be called from internal queue!
    private func add(items: [ConversationEntry], scrollTo: ScrollTo, completionHandler: (()->Void)?) {
        let oldStore = DispatchQueue.main.sync { return self.store };
        let newItems = items.filter({ !self.knownItems.contains($0.id) });
        let store = (oldStore + newItems).sorted(by: ConversationDataSource.sortConversationEntries(it1:it2:));
        
        let changes = store.calculateChanges(from: oldStore);
        
        var scrollToIdx: Int?;
        
        switch scrollTo {
        case .oldestUnread:
            if let lastUnreadIdx = store.lastIndex(where: { ($0 as? ConversationEntryWithSender)?.state.isUnread ?? false }) {
                scrollToIdx = lastUnreadIdx;
            }
        case .message(let id):
            scrollToIdx = store.firstIndex(where: { $0.id == id });
        case .none:
            break;
        }
        self.knownItems = Set(newItems.map({ $0.id }) + knownItems);
        
        DispatchQueue.main.async {
            self.store = store;
            if items.count == 1, let entry = (items.first as? ConversationEntryWithSender), entry.state.isUnsent {
                print("calculated position:", store.firstIndex(of: entry));
            }
            completionHandler?();
            self.delegate?.itemsRemoved(at: changes.removed);
            self.delegate?.itemAdded(at: changes.inserted);
            if let scrollToIdx = scrollToIdx {
                self.delegate?.scrollRowToVisible(scrollToIdx);
            } else {
                self.delegate?.markAsReadUpToNewestVisibleRow();
            }
        }
    }
    
    enum ScrollTo {
        case none
        case oldestUnread
        case message(withId: Int)
        
        static func from(loadType: ConversationLoadType) -> ScrollTo {
            switch loadType {
            case .unread(_):
                return .oldestUnread;
            case .with(let id, _):
                return .message(withId: id);
            case .before(_, _):
                return .none;
            }
        }
    }
    
//    struct MessagesStore {
//
//        var knownItems: Set<Int>;
//        var items: [ConversationEntry] = [];
//        var count: Int {
//            return items.count;
//        }
//
//        var timestampRange: ClosedRange<Date>?? {
//            guard let first = items.first, let last = items.last else {
//                return nil;
//            }
//            return min(first.timestamp, last.timestamp)...max(first.timestamp, last.timestamp);
//        }
//
//        init() {
//            self.knownItems = Set<Int>();
//        }
//
//        init(items: [ConversationEntry]) {
//            self.items = items;
//            self.knownItems = Set<Int>(items.map({ it -> Int in return it.id; }));
//        }
//
//        func item(at row: Int) -> ConversationEntry? {
//            guard row < self.items.count && row >= 0 else {
//                return nil;
//            }
//            return self.items[row];
//        }
//
//        func indexOf(itemId id: Int) -> Int? {
//            guard let idx = self.items.firstIndex(where: { (item) -> Bool in
//                return item.id == id && !(item is ConversationEntryRelated);
//            }) else {
//                return nil;
//            }
//            return idx;
//        }
//
//        mutating func remove(item: ConversationEntry) -> Int? {
//            let removeRelated = item is ConversationEntryRelated;
//            guard let idx = self.items.firstIndex(where: { (it) -> Bool in
//                // in most cases we should remove "both"?
//                return it.id == item.id && ((it is ConversationEntryRelated) == removeRelated);
//            }) else {
//                return nil;
//            }
//            self.items.remove(at: idx);
//            if !removeRelated {
//                self.knownItems.remove(item.id);
//            }
//            return idx;
//        }
//
//        mutating func add(item: ConversationEntry) -> Int? {
//            if !(item is ConversationEntryRelated) {
//                guard !knownItems.contains(item.id) else {
//                    return nil;
//                }
//                knownItems.insert(item.id);
//
//            }
//            guard !items.isEmpty else {
//                items.append(item);
//                return 0;
//            }
//
//            if compare(items.first!, item) == .orderedAscending {
//                items.insert(item, at: 0);
//                return 0;
//            } else if let last = items.last {
//                if compare(last, item) == .orderedDescending {
//                    let idx = items.count;
//                    // append to the end
//                    items.append(item);
//                    return idx;
//                } else {
//                    // insert into the items
//                    var idx = searchPosition(for: item);
//                    if idx == (items.count - 1) && items[idx].timestamp == item.timestamp {
//                        idx = idx + 1;
////                        if items[idx].id < item.id {
////                            idx = idx + 1;
////                        }
//                    }
//                    items.insert(item, at: idx);
//                    return idx;
//                }
//            } else {
//                return nil;
//            }
//        }
//
//        func compare(_ it1: ConversationEntry, _ it2: ConversationEntry) -> ComparisonResult {
//            let unsent1 = (it1 as? ConversationEntryWithSender)?.state.isUnsent ?? false;
//            let unsent2 = (it2 as? ConversationEntryWithSender)?.state.isUnsent ?? false;
//            if unsent1 == unsent2 {
//                let result = it1.timestamp.compare(it2.timestamp);
//                guard result == .orderedSame else {
//                    return result;
//                }
//                if it1.id == it2.id {
//                    if let i1 = it1 as? ConversationEntryRelated {
//                        switch i1.order {
//                        case .first:
//                            return .orderedAscending;
//                        case .last:
//                            return .orderedDescending;
//                        }
//                    }
//                    if let i2 = it2 as? ConversationEntryRelated {
//                        switch i2.order {
//                        case .first:
//                            return .orderedDescending;
//                        case .last:
//                            return .orderedAscending;
//                        }
//                    }
//                }
//                return it1.id < it2.id ? .orderedAscending : .orderedDescending;
//            } else {
//                if unsent1 {
//                    return .orderedDescending;
//                }
//                return .orderedAscending;
//            }
//        }
//
//        mutating func trim() -> [Int] {
//            guard items.count > 100 else {
//                return [];
//            }
//            let removed = Array(100..<items.count);
//            self.items = Array(items[0..<100]);
//            knownItems = Set(items.filter({ !($0 is ConversationEntryRelated) }).map({ it -> Int in return it.id; }));
//            return removed;
//        }
//
//        fileprivate func searchPosition(for item: ConversationEntry) -> Int {
//            var start = 0;
//            var end = items.count - 1;
//            while start != end {
//                let idx: Int = Int(ceil(Double(start+end)/2.0));
//                if compare(items[idx], item) == .orderedAscending {
//                    end = idx - 1;
//                } else {
//                    start = idx;
//                }
//            }
//            return compare(items[start], item) == .orderedAscending  ? (start) : start + 1;
//        }
//    }

    
}
