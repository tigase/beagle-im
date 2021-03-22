//
// AbstractConversationLogController.swift
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

import AppKit
import TigaseSwift

class AbstractConversationLogController: NSViewController, NSTableViewDataSource, ConversationDataSourceDelegate {

    @IBOutlet var tableView: NSTableView!;
    
    let dataSource = ConversationDataSource();
    var conversation: Conversation!;
    
    private var hasFocus: Bool {
        return view.window?.isKeyWindow ?? false;
    }

    let selectionManager = ConversationLogSelectionManager();
    
    var mouseMonitor: Any?;

    override func viewDidLoad() {
        super.viewDidLoad();
        self.dataSource.delegate = self;
        self.tableView.dataSource = self;
        self.tableView.usesAutomaticRowHeights = true;
        self.tableView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        selectionManager.initilizeHandlers(controller: self);

        NotificationCenter.default.addObserver(self, selector: #selector(didEndLiveScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: self.tableView.enclosingScrollView);
        NotificationCenter.default.addObserver(self, selector: #selector(scrolledRowToVisible(_:)), name: ChatViewTableView.didScrollRowToVisible, object: self.tableView);
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKeyWindow), name: NSWindow.didBecomeKeyNotification, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChange), name: NSView.boundsDidChangeNotification, object: self.tableView.enclosingScrollView?.contentView);
    }
    
    override func viewDidAppear() {
        super.viewDidAppear();
        prevBounds = self.tableView.bounds;
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear();
        if let mouseMonitor = self.mouseMonitor {
            self.mouseMonitor = nil;
            NSEvent.removeMonitor(mouseMonitor);
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil);
    }
    
    func prepareContextMenu(_ menu: NSMenu, forRow row: Int) {
        
    }

    private func row(for event: NSEvent) -> Int? {
        let point = self.tableView.convert(event.locationInWindow, from: nil);
        let row = self.tableView.row(at: point);
        return row >= 0 ? row : nil;
    }
    
    private func messageId(for event: NSEvent) -> Int? {
        guard let row = self.row(for: event) else {
            return nil;
        }
        return dataSource.getItem(at: row)?.id;
    }
            
    @objc func scrolledRowToVisible(_ notification: Notification) {
        markAsReadUpToNewestVisibleRow();
    }

    func markAsReadUpToNewestVisibleRow() {
        let visibleRows = self.tableView.rows(in: self.tableView.visibleRect);
        if visibleRows.contains(0) {
            self.dataSource.trimStore();
        }
        guard self.hasFocus && self.conversation.unread > 0 else {
            return;
        }
        
        var ts: Date? = dataSource.getItem(at: visibleRows.lowerBound)?.timestamp;
        if let tmp = dataSource.getItem(at: visibleRows.upperBound-1)?.timestamp {
            if ts == nil {
                ts = tmp;
            } else if ts!.compare(tmp) == .orderedAscending {
                ts = tmp;
            }
        }
        guard let since = ts else {
            return;
        }
        DBChatHistoryStore.instance.markAsRead(for: self.conversation, before: since);
    }
    
    @objc func didBecomeKeyWindow(_ notification: Notification) {
        if conversation.unread > 0 {
            markAsReadUpToNewestVisibleRow();
        }
    }
    
    private var prevBounds: NSRect = .zero;
    
    @objc func didEndLiveScroll(_ notification: Notification) {
        markAsReadUpToNewestVisibleRow();
    }
    
    @objc func boundsChange(_ notification: Notification) {
        if conversation.unread > 0 {
            markAsReadUpToNewestVisibleRow();
        }
        if prevBounds.width != self.tableView.bounds.width {
            if tableView.rows(in: tableView.visibleRect).contains(0) {
                DispatchQueue.main.async { [weak self] in
                    self?.tableView.scrollRowToVisible(0);
                }
            }
        }
        prevBounds = self.tableView.bounds;
    }

    func beginUpdates() {
        tableView.beginUpdates();
    }
    
    func endUpdates() {
        tableView.endUpdates();
    }
    
    func itemsAdded(at rows: IndexSet, initial: Bool) {
        tableView.insertRows(at: rows, withAnimation: initial ? [] : .effectFade);
    }
    
    func itemUpdated(indexPath: IndexPath) {
        tableView.removeRows(at: IndexSet(integer: indexPath.item), withAnimation: .effectFade);
        tableView.insertRows(at: IndexSet(integer: indexPath.item), withAnimation: .effectFade);
        markAsReadUpToNewestVisibleRow();
    }
    
    func itemsUpdated(forRowIndexes: IndexSet) {
        tableView.reloadData(forRowIndexes: forRowIndexes, columnIndexes: [0])
        markAsReadUpToNewestVisibleRow();
    }
    
    func itemsRemoved(at: IndexSet) {
        tableView.removeRows(at: at, withAnimation: .effectFade);
    }
    
    func itemsReloaded() {
        tableView.reloadData();
    }
    
    func isVisible(row: Int) -> Bool {
        return tableView.rows(in:tableView.visibleRect).contains(row);
    }
    
    func scrollRowToVisible(_ row: Int) {
        tableView.scrollRowToVisible(row);
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSource.count;
    }

}

