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

class AbstractConversationLogController: NSViewController, NSTableViewDataSource, ChatViewDataSourceDelegate {

    @IBOutlet var tableView: NSTableView!;

    weak var logTableViewDelegate: NSTableViewDelegate? {
        didSet {
            if let tableView = self.tableView {
                tableView.delegate = logTableViewDelegate;
            }
        }
    }
    
    let dataSource: ChatViewDataSource = ChatViewDataSource();
    var chat: DBChatProtocol!;
    var account: BareJID! {
        return chat.account;
    }
    
    var jid: BareJID! {
        return chat.jid.bareJid;
    }

    var scrollChatToMessageWithId: Int?;
    
    private var hasFocus: Bool {
        return view.window?.isKeyWindow ?? false;
    }

    let selectionManager = ConversationLogSelectionManager();
    
    var mouseMonitor: Any?;

    override func viewDidLoad() {
        super.viewDidLoad();
        self.dataSource.delegate = self;
        self.tableView.delegate = logTableViewDelegate;
        self.tableView.dataSource = self;
        self.tableView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        if let scrollToMessageWithId = self.scrollChatToMessageWithId {
            let position = DBChatHistoryStore.instance.itemPosition(for: account, with: jid, msgId: scrollToMessageWithId) ?? 0;
            self.dataSource.loadItems(before: nil, limit: max(position + 20, 100), awaitIfInProgress: true, unread: chat.unread) { (unread) in
                DispatchQueue.main.async {
                    if position > self.dataSource.count {
                        self.tableView.scrollRowToVisible(0);
                    } else {
                        self.tableView.scrollRowToVisible(position);
                    }
                }
            }
        } else {
            self.dataSource.refreshData(unread: chat.unread) { (firstUnread) in
                DispatchQueue.main.async {
                    let unread = firstUnread ?? 0;//self.chat.unread;
                    self.tableView.scrollRowToVisible(unread);
                }
            };
        }
        scrollChatToMessageWithId = nil;
        selectionManager.initilizeHandlers(controller: self);

        NotificationCenter.default.addObserver(self, selector: #selector(willStartLiveScroll(_:)), name: NSScrollView.willStartLiveScrollNotification, object: self.tableView.enclosingScrollView);
        NotificationCenter.default.addObserver(self, selector: #selector(didEndLiveScroll(_:)), name: NSScrollView.didEndLiveScrollNotification, object: self.tableView.enclosingScrollView);
        NotificationCenter.default.addObserver(self, selector: #selector(scrolledRowToVisible(_:)), name: ChatViewTableView.didScrollRowToVisible, object: self.tableView);
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKeyWindow), name: NSWindow.didBecomeKeyNotification, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(hourChanged), name: AppDelegate.HOUR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(boundsChange), name: NSView.boundsDidChangeNotification, object: self.tableView.enclosingScrollView?.contentView);
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear();
        if let mouseMonitor = self.mouseMonitor {
            self.mouseMonitor = nil;
            NSEvent.removeMonitor(mouseMonitor);
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: nil);
        NotificationCenter.default.removeObserver(self, name: AppDelegate.HOUR_CHANGED, object: nil);
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
        guard self.hasFocus && self.chat.unread > 0 else {
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
        print("marking as read:", account as Any, "jid:", jid as Any, "before:", since);
        DBChatHistoryStore.instance.markAsRead(for: self.account, with: self.jid, before: since);
    }
    
    func messageViewFor(event: NSEvent) -> ChatMessageCellView? {
        guard let contentView = event.window?.contentView else {
            return nil;
        }
        let point = contentView.convert(event.locationInWindow, to: nil);
        guard let textView = contentView.hitTest(point) as? NSTextField else {
            return nil;
        }
        guard let view = textView.superview as? ChatMessageCellView else {
            return nil;
        }
        return view;
    }
    
    func isInMesageView(event: NSEvent) -> Bool {
        guard let contentView = event.window?.contentView else {
            return false;
        }
        let point = contentView.convert(event.locationInWindow, to: nil);
        return contentView.hitTest(point) is ChatMessageCellView;
    }
    
    @objc func didBecomeKeyWindow(_ notification: Notification) {
        if chat.unread > 0 {
            markAsReadUpToNewestVisibleRow();
        }
    }
    
    private var prevVisibleRect: NSRect = .zero;
    private var prevVisibleRowId: Int = NSNotFound;
    private var prevBounds: NSRect = .zero;
    
    private var isLiveScroll: Bool = false;
    
    @objc func willStartLiveScroll(_ notification: Notification) {
        isLiveScroll = true;
    }
    
    @objc func didEndLiveScroll(_ notification: Notification) {
        isLiveScroll = false;
        prevVisibleRect = tableView.visibleRect;
        prevVisibleRowId = dataSource.getItem(at: tableView.row(at: prevVisibleRect.origin))?.id ?? NSNotFound;
        markAsReadUpToNewestVisibleRow();
    }
    
    @objc func boundsChange(_ notification: Notification) {
        if chat.unread > 0 {
            markAsReadUpToNewestVisibleRow();
        }
        if !isLiveScroll && !selectionManager.inProgress {
            // good for newest entry, but not if the entry has moved from the row 0
            if prevVisibleRect.contains(CGPoint.zero) || prevVisibleRowId == NSNotFound {
                print("scroll to prev rect:", prevVisibleRect)
                self.tableView.scrollToVisible(prevVisibleRect);
            } else {
                print("scroll to prev row id:", prevVisibleRowId);
                self.tableView.scrollRowToVisible(dataSource.position(withId: prevVisibleRowId));
            }
        }
        prevVisibleRect = self.tableView.visibleRect;
    }

    func itemAdded(at rows: IndexSet, shouldScroll scroll: Bool = true) {
        let shouldScroll = scroll && rows.contains(0) && tableView.rows(in: self.tableView.visibleRect).contains(0);
        if dataSource.count == rows.count && rows.count > 1 {
            tableView.insertRows(at: rows, withAnimation: []);
        } else {
            tableView.insertRows(at: rows, withAnimation: NSTableView.AnimationOptions.effectFade)
        }
        if (shouldScroll) {
            tableView.scrollRowToVisible(0);
        }
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

    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSource.count;
    }

    @objc func hourChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.tableView.reloadData(forRowIndexes: IndexSet(integersIn: 0..<self.dataSource.count), columnIndexes: [0]);
        }
    }

}

