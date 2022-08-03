//
// ConversationDataSource.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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


import Foundation
import Combine
import Martin
import TigaseLogging

protocol ConversationDataSourceDelegate: AnyObject {
    
    var conversation: Conversation! { get }
    
    func beginUpdates();
    
    func endUpdates();
    
    func itemsAdded(at: IndexSet, initial: Bool);

    func itemsUpdated(forRowIndexes: IndexSet);

    func itemUpdated(indexPath: IndexPath);

    func itemsRemoved(at: IndexSet);
    
    func itemsReloaded();
    
    func isVisible(row: Int) -> Bool;
    
    func scrollRowToVisible(_ row: Int);
    
    func markAsReadUpToNewestVisibleRow();
}

extension ConversationDataSourceDelegate {

    func update(_ block: (ConversationDataSourceDelegate)->Void) {
        beginUpdates();
        block(self);
        endUpdates();
    }

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
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ConversationDataSource");
    private let queue = DispatchQueue(label: "chat_datasource");
    
    weak var delegate: ConversationDataSourceDelegate? {
        didSet {
            delegate?.conversation.markersPublisher.receive(on: self.queue).sink(receiveValue: { [weak self] markers in
                self?.update(markers: markers);
            }).store(in: &cancellables);
        }
    }
    
    public var defaultPageSize = 80;
    
    private var state: State = .uninitialized;
    
    var count: Int {
        return store.count;
    }
    
    private var oldestEntry: ConversationEntry?;
    private var entries: [ConversationEntry] = [];
    private var entriesCount: Int = 0;
    private var markers: [ConversationEntry] = [];
    private var unreads: [ConversationEntry] = [];
    
    private var cancellables: Set<AnyCancellable> = [];
    private var knownItems: Set<Int> = [];
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(messageNew), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageUpdated(_:)), name: DBChatHistoryStore.MESSAGE_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved(_:)), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
        Settings.$linkPreviews.dropFirst().receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] _ in
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
            let store = self.store;
            DispatchQueue.main.sync {
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
        let initialLoad = self.state == .uninitialized;
        state = .loading;
        queue.async {
            let items: [ConversationEntry] = conversation.loadItems(type);
            self.add(items: items, scrollTo: .from(loadType: type), initial: initialLoad, completionHandler: {
                self.state = .loaded;
            });
        }
    }
        
    private struct ChatMarkerKey: Hashable {
        let type: ChatMarker.MarkerType;
        let timestamp: Date;
    }
    
    // call only from local dispatch queue
    private func updateStore(scrollTo: ScrollTo = .none, completionHandler: (()->Void)? = nil) {
        let entriesCount = entries.count;

        let oldStore = store;
        let newStore = (entries + unreads + markers).sorted();
        
        var scrollToIdx: Int?;
        switch scrollTo {
        case .oldestUnread:
            if let lastUnreadIdx = newStore.lastIndex(where: { $0.state.isUnread }) {
                scrollToIdx = lastUnreadIdx;
            }
        case .message(let id):
            scrollToIdx = newStore.firstIndex(where: { $0.id == id });
        case .none:
            break;
        }

        let oldestEntry = newStore.last(where: { $0.sender != .none });
        
        let changes = newStore.calculateChanges(from: oldStore);
        DispatchQueue.main.sync {
            let initial = self.state != .loaded;
            self.store = newStore;
            self.entriesCount = entriesCount;
            self.oldestEntry = oldestEntry;
            completionHandler?();
            self.delegate?.update({ delegate in
                // it looks like insert/removed are not detected at all!
                delegate.itemsRemoved(at: changes.removed);
                delegate.itemsAdded(at: changes.inserted, initial: initial);
            })
            
            if let scrollToIdx = scrollToIdx {
                self.delegate?.scrollRowToVisible(scrollToIdx);
            } else {
                self.delegate?.markAsReadUpToNewestVisibleRow();
            }
        }
    }
    
    private func update(markers: [ChatMarker]) {
        guard let conversation = self.delegate?.conversation else {
            return;
        }
                
        let grouped: [ChatMarkerKey: [ConversationEntrySender]] = markers.reduce(into: [:], { result, marker in
            result[ChatMarkerKey(type: marker.type, timestamp: marker.timestamp), default: []] += [marker.sender];
        })
        
        self.markers = grouped.map({ k, v in
            return ConversationEntry(id: Int.max, conversation: conversation, timestamp: k.timestamp, state: .none, sender: .none, payload: .marker(type: k.type, senders: v), options: .none)
        });

        self.updateStore();
    }
 
    private func add(item: ConversationEntry) {
        queue.async {
            self.add(items: [item], scrollTo: .none, completionHandler: nil);
        }
    }
    
    func getItem(at row: Int) -> ConversationEntry? {
        guard store.count > row && row >= 0 else {
            return nil;
        }
        let store = self.store;
        let item = store[row];
        // load more if remaining equals ChatMarkers!
        if row >= (entriesCount - 1) {
            if let oldestEntry = self.oldestEntry {
                self.loadItems(.before(entry: oldestEntry, limit: self.defaultPageSize))
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
            guard self.knownItems.contains(item.id) else {
                return;
            }
            self.knownItems.remove(item.id);
            self.entries = self.entries.filter({ $0.id == item.id });

            self.updateStore();
        }
    }

    func update(item: ConversationEntry) {
        queue.async {
            var entries = self.entries.filter({ $0.id != item.id });
            if !self.knownItems.contains(item.id) {
                self.knownItems.insert(item.id);
            }
            entries.append(item);
            self.entries = entries
            self.updateStore();
        }
    }

    func trimStore() {
        guard store.count > 100 else {
            return;
        }
        
        queue.async {
            guard self.entries.count > 100 else {
                return;
            }
            self.entries = Array(self.entries.sorted()[0..<100]);
            self.knownItems = Set(self.entries.map({ $0.id }));
            self.updateStore();
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
    private func add(items: [ConversationEntry], scrollTo: ScrollTo, initial: Bool = false, completionHandler: (()->Void)?) {
        let start = Date();
        let newItems = items.filter({ !self.knownItems.contains($0.id) });
        guard !newItems.isEmpty else {
            DispatchQueue.main.async {
                completionHandler?();
            }
            logger.debug("skipped adding rows as no rows were loadad!")
            return;
        }

        if case .oldestUnread = scrollTo {
            if entries.isEmpty,let firstUnread = newItems.last(where: { $0.state.isUnread }) {
                self.unreads = [.init(id: Int.min, conversation: firstUnread.conversation, timestamp: firstUnread.timestamp, state: .none, sender: .none, payload: .unreadMessages, options: .none)];
            }
        }

        self.entries = self.entries + newItems;
        self.knownItems = Set(self.entries.map({ $0.id }));

        // how to calculate where to scroll before main dispatch queue is fired?
        self.updateStore(scrollTo: scrollTo, completionHandler: {
            self.logger.debug("items added in: \(Date().timeIntervalSince(start))")
            completionHandler?();
        });
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
    
}

extension ConversationEntry {
    func isMessage() -> Bool {
        switch payload {
        case .message(_, _):
            return true;
        default:
            return false;
        }
    }
}

extension ConversationEntry {
    
    func isMarker() -> Bool {
        switch payload {
        case .marker(_, _):
            return true;
        default:
            return false;
        }
    }
 
}
