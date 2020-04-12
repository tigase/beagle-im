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
        
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .mouseMoved, .keyDown]) { (event) -> NSEvent? in
            guard event.type != .keyDown else {
                if self.currentSession != nil && event.modifierFlags.contains(.command) && event.characters?.first == "c" {
                    self.copySelectedText(self);
                    return nil;
                }
                return event;
            }
            return self.handleMouse(event: event) ? nil : event;
        }

        NotificationCenter.default.addObserver(self, selector: #selector(didEndScrolling), name: NSScrollView.didEndLiveScrollNotification, object: self.tableView.enclosingScrollView);
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
    
    var currentSession: BaseSelectionSession? {
        willSet {
            if newValue == nil && currentSession != nil {
                print("changing selection!");
            }
        }
    }
        
    func handleMouse(event: NSEvent) -> Bool {
        guard self.view.window?.isKeyWindow ?? false else {
            return false;
        }
        switch event.type {
        case .mouseMoved:
            if currentSession == nil {
                guard let messageView = messageViewFor(event: event) else {
                    NSCursor.pointingHand.pop();
                    return isInMesageView(event: event);
                }
                if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
                    if (messageView.message.attributedStringValue.attribute(.link, at: idx, effectiveRange: nil) as? URL) != nil {
                        if NSCursor.current != NSCursor.pointingHand {
                            NSCursor.pointingHand.push();
                        }
                    } else {
                        NSCursor.pointingHand.pop();
                    }
                } else {
                    NSCursor.pointingHand.pop();
                }
            }
            return false;
        case .leftMouseDown:
            if currentSession != nil {
                let visibleRows = self.tableView.rows(in: self.tableView.visibleRect);
                for row in visibleRows.lowerBound..<visibleRows.upperBound {
                    if let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView {
                        let str = NSMutableAttributedString(attributedString: view.message.attributedStringValue);
                        str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length));
                        view.message.attributedStringValue = str;
                    }
                }
            }
            currentSession = nil;
        
            guard event.clickCount == 1 else {
                if event.clickCount == 2 {
                    guard let messageView = messageViewFor(event: event) else {
                        return isInMesageView(event: event);
                    }
                    if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
                        let str = messageView.message.stringValue;
                        let clickIdx = str.index(str.startIndex, offsetBy: idx);
                        let before = str[str.startIndex...clickIdx]
                        let after = str[str.index(after: clickIdx)..<str.endIndex];
                        let beforeIdx = before.lastIndex { (c) -> Bool in
                            return !CharacterSet.alphanumerics.contains(c.unicodeScalars.first!);
                        }
                        let prefix = beforeIdx != nil ? before[before.index(after: beforeIdx!)..<before.endIndex] : before;
                        let afterIdx = after.firstIndex { (c) -> Bool in
                            return !CharacterSet.alphanumerics.contains(c.unicodeScalars.first!);
                        }
                        let suffix = (afterIdx != nil) ? ((afterIdx! != after.startIndex) ? after[after.startIndex...after.index(before: afterIdx!)] : nil) : after;
                        print("got:", prefix, suffix as Any, "\(String(prefix))\(String(suffix ?? ""))");
                        let attrStr = NSMutableAttributedString(attributedString: messageView.message.attributedStringValue);
                        let len = (prefix.count + (suffix?.count ?? 0));
                        attrStr.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: before.count - prefix.count,  length: len));
                        messageView.message.attributedStringValue = attrStr;
                        self.currentSession = TextSelectionSession(messageView: messageView, selected: "\(String(prefix))\(String(suffix ?? ""))");
                            return true;
                        }
                    }
                    if event.clickCount == 3 {
                        guard let messageView = messageViewFor(event: event) else {
                            return isInMesageView(event: event);
                        }
                    if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
                        let str = messageView.message.stringValue;
                        let clickIdx = str.index(str.startIndex, offsetBy: idx);
                        let before = str[str.startIndex...clickIdx]
                        let after = str[str.index(after: clickIdx)..<str.endIndex];
                        let beforeIdx = before.lastIndex { (c) -> Bool in
                            return CharacterSet.newlines.contains(c.unicodeScalars.first!);
                        }
                        let prefix = beforeIdx != nil ? before[before.index(after: beforeIdx!)..<before.endIndex] : before;
                        let afterIdx = after.firstIndex { (c) -> Bool in
                            return CharacterSet.newlines.contains(c.unicodeScalars.first!);
                        }
                        let suffix = (afterIdx != nil && (afterIdx! != after.startIndex)) ? after[after.startIndex...after.index(before: afterIdx!)] : after;
                        print("got:", prefix, suffix, "\(String(prefix))\(String(suffix))");
                        let attrStr = NSMutableAttributedString(attributedString: messageView.message.attributedStringValue);
                        let len = (prefix.count + suffix.count);
                        attrStr.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: before.count - prefix.count,  length: len));
                        messageView.message.attributedStringValue = attrStr;
                        self.currentSession = TextSelectionSession(messageView: messageView, selected: "\(String(prefix))\(String(suffix))");
                        return true;
                    }
                }
                //return false;
                return false;
            }
            
            guard let messageView = messageViewFor(event: event) else {
                return isInMesageView(event: event);
            }
                
            self.currentSession = SelectionSession(messageView: messageView, event: event);
            
            return true;//currentSession != nil;
        case .leftMouseUp:
            NSCursor.pointingHand.pop();
            
            guard let session = currentSession as? SelectionSession else {
                return false;
            }
            if session.selected?.isEmpty ?? true {
                currentSession = nil;
            }

            guard let messageView = messageViewFor(event: event) else {
                return isInMesageView(event: event);
            }
                
            if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
                if let link = messageView.message.attributedStringValue.attribute(.link, at: idx, effectiveRange: nil) as? URL {
                    if session.position.location == idx && session.messageId == messageView.id {
                        NSWorkspace.shared.open(link);
                    }
                    NSCursor.pointingHand.push();
                }
            }

            return true;
        case .leftMouseDragged:
            guard let session = self.currentSession as? SelectionSession else {
                return false;
            }
            NSCursor.pointingHand.pop();
                
            let point = self.tableView.convert(event.locationInWindow, from: nil);
            let currRow = self.tableView.row(at: point);
            let startRow = self.tableView.row(at: self.tableView.convert(session.point, from: nil));
            guard currRow >= 0 && startRow >= 0 else {
                return false;
            }
            guard let messageView = messageViewFor(event: event) else {
                return false;
            }
            guard let idx = messageView.message.characterIndexFor(event: event) else {
                return false;
            }
                
            let visibleRows = self.tableView.rows(in: self.tableView.visibleRect);
            for row in visibleRows.lowerBound..<visibleRows.upperBound {
                if let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView {
                    let str = NSMutableAttributedString(attributedString: view.message.attributedStringValue);
                    str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length));
                    view.message.attributedStringValue = str;
                }
            }
                
            let begin = max(startRow, currRow);
            let end = min(startRow, currRow);
            for row in end...begin {
                if let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView {
                    let str = NSMutableAttributedString(attributedString: view.message.attributedStringValue);
                    str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length));
                    if row == begin {
                        if row == end {
                            let s1 = min(session.position, idx);
                            let s2 = max(session.position, idx);
                            //print("s1:", s1, "s2:", s2, "length:", (s2-s1) + 1);
                            str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: s1.location, length: (s2.upperBound - s1.location)));
                            print("str:", str, s1, s2, idx.length, str.length, str.string.last as Any);
                        } else {
                            let start = begin == startRow ? session.position : idx;
                            str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: start.location, length: (str.length - start.location)));
                        }
                    } else if row == end {
                        let start = end == startRow ? session.position : idx;
                        str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: 0, length: start.upperBound));
                    } else {
                        str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range:   NSRange(location: 0, length: str.length));
                    }
                    view.message.attributedStringValue = str;
                }
            }
                
            let range = tableView.rows(in: tableView.visibleRect);
            let selected = dataSource.getItems(fromId: session.messageId, toId: messageView.id, inRange: range).filter { (item) -> Bool in
                return item is ChatMessage;
                }.map { (item) -> ChatMessage in
                    return item as! ChatMessage;
            }
            if selected.count == 1 {
                let s1 = min(session.position, idx);
                let s2 = max(session.position, idx);
                session.selection(selected, startOffset: s1.lowerBound, endOffset: s2.upperBound);
            } else {
                let inverted = (selected.first?.id ?? 0) != session.messageId;
                
                session.selection(selected, startOffset: (inverted ? idx : session.position).lowerBound, endOffset: (inverted ? session.position : idx).upperBound);
            }
            return true;
        case .rightMouseDown:
            let point = self.view.convert(event.locationInWindow, from: nil);
    //            print("point:", point, "frame:", self.tableView.enclosingScrollView?.frame);
            guard self.tableView.enclosingScrollView?.frame.contains(point) ?? false else {
                return false;
            }
            let menu = NSMenu(title: "Actions");
            let tag = currentSession != nil ? -1 : (self.messageId(for: event) ?? -1);
            if tag != -1 {
                if let row = row(for: event) {
                    self.prepareContextMenu(menu, forRow: row);
                }
            }
            if tag != -1 || currentSession != nil {
                var copy = menu.addItem(withTitle: "Copy text", action: #selector(copySelectedText), keyEquivalent: "");
                copy.target = self;
                copy.tag = tag;
                copy = menu.addItem(withTitle: "Copy messages", action: #selector(copySelectedMessages), keyEquivalent: "");
                copy.target = self;
                copy.tag = tag;
            }
            if let messageView = messageViewFor(event: event) {
                if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
                    if let link = messageView.message.attributedStringValue.attribute(.link, at: idx, effectiveRange: nil) as? URL {
                        let copy = menu.addItem(withTitle: "Copy link", action: #selector(copySelectedText), keyEquivalent: "");
                        copy.target = self;
                        copy.representedObject = link;
                    }
                }
            }

            if !menu.items.isEmpty {
                NSMenu.popUpContextMenu(menu, with: event, for: self.tableView);
            }
            return true;
        default:
            break;
        }
        return false;
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
    
    @objc func copySelectedText(_ sender: Any) {
        NSPasteboard.general.clearContents();
        if let link = (sender as? NSMenuItem)?.representedObject as? URL {
            NSPasteboard.general.setString(link.absoluteString, forType: .string);
            return;
        }
        guard let session = self.currentSession as? SelectionSession else {
            guard let selectedText = (self.currentSession as? TextSelectionSession)?.selected else {
                guard let tag = (sender as? NSMenuItem)?.tag, tag >= 0 else {
                    return;
                }
                let range = tableView.rows(in: tableView.visibleRect);
                guard let item = dataSource.getItems(fromId: tag, toId: tag, inRange: range).first as? ChatMessage else {
                    return;
                }
                NSPasteboard.general.setString(item.message, forType: .string);
                return;
            }
            NSPasteboard.general.setString(selectedText, forType: .string);
            return;
        }
        
        guard let selected = session.selected, let startOffset = session.startOffset, let endOffset = session.endOffset, !selected.isEmpty else {
            return;
        }
        
        var text: [String] = [];
        if selected.count == 1 {
            let item = selected[0];
            let message = NSMutableAttributedString(string: item.message.emojify());
            if let errorMessage = item.error {
                message.append(NSAttributedString(string: "\n------\n\(errorMessage)"));
            }
            text.append(message.attributedSubstring(from: NSRange(location: startOffset, length: endOffset-startOffset)).string);
        } else {
            for (pos, item) in selected.enumerated() {
                let message = NSMutableAttributedString(string: item.message.emojify());
                if let errorMessage = item.error {
                    message.append(NSAttributedString(string: "\n------\n\(errorMessage)"));
                }
                if pos == 0 {
                    text.append(message.attributedSubstring(from: NSRange(location: startOffset, length: message.length-startOffset)).string);
                } else if pos == (selected.count - 1) {
                    text.append(message.attributedSubstring(from: NSRange(location: 0, length: endOffset)).string);
                } else {
                    text.append(message.string);
                }
            }
        }

        NSPasteboard.general.setString(text.joined(separator: "\n"), forType: .string);
    }
    
    @objc func copySelectedMessages(_ sender: Any) {
        NSPasteboard.general.clearContents();
        var selected: [ChatMessage] = (self.currentSession as? SelectionSession)?.selected ?? [];
        if selected.isEmpty {
            let range = tableView.rows(in: tableView.visibleRect);
            if let messageId = (self.currentSession as? TextSelectionSession)?.messageId ?? ((sender as? NSMenuItem)?.tag) {
                if messageId >= 0 {
                    selected = dataSource.getItems(fromId: messageId, toId: messageId, inRange: range).filter { (item) -> Bool in
                        return item as? ChatMessage != nil;
                        }.map { (item) -> ChatMessage in
                            return item as! ChatMessage;
                    };
                }
            }
        }

        guard !selected.isEmpty else {
            return;
        }
        
        let dateFormatter = DateFormatter();
        dateFormatter.locale = Locale(identifier: "en_US_POSIX");
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss";
        
        let rosterStore = XmppService.instance.getClient(for: account)?.rosterStore;
        
        let text = selected.map { (item) -> String in
            let name: String = item.state.direction == .incoming ? (rosterStore?.get(for: chat.jid.withoutResource)?.name ?? chat.jid.localPart ?? chat.jid.domain) : "Me";
            return "[\(dateFormatter.string(from: item.timestamp))] <\(item.authorNickname ?? name)> \(item.message.emojify())";
        };
        
        NSPasteboard.general.setString(text.joined(separator: "\n"), forType: .string);
    }
    
    @objc func didEndScrolling(_ notification: Notification) {
        markAsReadUpToNewestVisibleRow();
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
    
    @objc func boundsChange(_ notification: Notification) {
        if chat.unread > 0 {
            markAsReadUpToNewestVisibleRow();
        }
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

    class BaseSelectionSession {

        let messageId: Int;

        init(messageId: Int) {
            self.messageId = messageId;
        }
    }
    
    class SelectionSession: BaseSelectionSession {
        
        let position: NSTextField.CharacterRange;
        let point: NSPoint;
        
        fileprivate(set) var selected: [ChatMessage]?;
        fileprivate(set) var startOffset: Int?;
        fileprivate(set) var endOffset: Int?;
        
        init?(messageView: ChatMessageCellView, event: NSEvent) {
            guard let position = messageView.message!.characterIndexFor(event: event) else {
                return nil;
            }
            self.position = position;
            self.point = event.locationInWindow;
            super.init(messageId: messageView.id);
        }
        
        func selection(_ selected: [ChatMessage], startOffset: Int, endOffset: Int) {
            self.selected = selected;
            self.startOffset = startOffset;
            self.endOffset = endOffset;
        }
    }
    
    class TextSelectionSession: BaseSelectionSession {

        let selected: String;

        init(messageId: Int, selected: String) {
            self.selected = selected;
            super.init(messageId: messageId);
        }
        
        init(messageView: ChatMessageCellView, selected: String) {
            self.selected = selected;
            super.init(messageId: messageView.id);
        }
    }

}
