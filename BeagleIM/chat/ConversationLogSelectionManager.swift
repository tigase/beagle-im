//
// ConversationLogSelectionManager.swift
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

class ConversationLogSelectionManager {
    
    private var mouseMonitor: Any?;
    private weak var controller: AbstractConversationLogController?;
    private var selectionStart: SelectionPoint?;
    private var selectionEnd: SelectionPoint?;
    private var selectedItems: [SelectionItem] = [];
    
    private(set) var inProgress: Bool = false;
    
    func initilizeHandlers(controller: AbstractConversationLogController) {
        self.controller = controller;
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .mouseMoved, .keyDown]) { [weak self] (event) -> NSEvent? in
            guard event.type != .keyDown else {
                if let that = self {
                    if !that.selectedItems.isEmpty && event.modifierFlags.contains(.command) && event.characters?.first == "c" {
                        that.copySelectedText(that);
                        return nil;
                    }
                }
                return event;
            }
            return (self?.handleMouse(event: event) ?? false) ? nil : event;
        }
    }
    
    func handleMouse(event: NSEvent) -> Bool {
        guard controller?.view.window?.isKeyWindow ?? false else {
            return false;
        }
        guard let table = controller?.tableView, let superview = table.superview else {
            return false;
        }
        
        switch event.type {
        case .leftMouseDown:
            return handleLeftMouseDown(event: event, table: table, superview: superview);
        case .leftMouseUp:
            return handleLeftMouseUp(event: event, table: table, superview: superview);
        case .leftMouseDragged:
            return handleLeftMouseDragged(event: event, table: table, superview: superview);
        case .rightMouseDown:
            return handleRightMouseDown(event: event, table: table, superview: superview);
        default:
            break;
        }
        return false;
    }
    
    func selectionEnds() -> (SelectionPoint,SelectionPoint)? {
        guard let selectionStart = self.selectionStart, let selectionEnd = self.selectionEnd else {
            return nil;
        }
        let sortedEnds = [selectionStart, selectionEnd].sorted(by: { (e1, e2) -> Bool in
            if e1.timestamp == e2.timestamp {
                if e1.entryId == e2.entryId {
                    return e1.location < e2.location;
                }
                return e1.entryId < e2.entryId;
            }
            return e1.timestamp < e2.timestamp;
        });
        return (sortedEnds[0], sortedEnds[1]);
    }
    
    @objc func copySelectedText(_ sender: Any) {
        if let url = (sender as? NSMenuItem)?.representedObject as? URL {
            NSPasteboard.general.clearContents();
            NSPasteboard.general.setString(url.absoluteString, forType: .string);
            return;
        }
        
        let texts = sortedSelectionItems(row: (sender as? NSMenuItem)?.tag ?? NSNotFound).map { NSMutableAttributedString(attributedString: $0.attributedString) };
        
        for text in texts {
            text.removeAttribute(.backgroundColor, range: NSRange(location:0, length: text.length));
        }
        
        if let (begin,end) = selectionEnds() {
            if let text = texts.last {
                if end.location < text.length {
                    text.deleteCharacters(in: NSRange(end.location..<text.length));
                }
            }
            if let text = texts.first {
                if begin.location > 0 {
                    text.deleteCharacters(in: NSRange(0..<begin.location));
                }
            }
        }

        NSPasteboard.general.clearContents();
        NSPasteboard.general.writeObjects(texts);
    }
    
    @objc func copySelectedMessages(_ sender: Any) {
        let dateFormatter = DateFormatter();
        dateFormatter.locale = Locale(identifier: "en_US_POSIX");
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss";

        NSPasteboard.general.clearContents();
        let items = sortedSelectionItems(row: (sender as? NSMenuItem)?.tag ?? NSNotFound);
        let texts: [NSAttributedString] = items.map {
            let item = NSMutableAttributedString(string: "[\(dateFormatter.string(from: $0.timestamp))] <\($0.sender)>: ");
            item.applyFontTraits(.boldFontMask, range: NSRange(0..<item.length));
            item.append($0.attributedString);
            item.removeAttribute(.backgroundColor, range: NSRange(location:0, length: item.length));
            return item;
        };
        NSPasteboard.general.writeObjects(texts);
    }

    
    private func sortedSelectionItems(row: Int) -> [SelectionItem] {
        guard let (begin,end) = selectionEnds() else {
            guard row != NSNotFound, let view = self.controller?.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ChatMessageCellView else {
                return [];
            }
            return [SelectionItem(entryId: view.id, timestamp: view.ts!, sender: view.sender ?? "", attributedString: view.message.attributedString())];
        }
        
        let range = begin.timestamp...end.timestamp;
        return selectedItems.filter({ range.contains($0.timestamp) }).sorted(by: { (e1, e2) -> Bool in
            if e1.timestamp == e2.timestamp {
                return e1.entryId < e2.entryId;
            }
            return e1.timestamp < e2.timestamp;
        });
    }
        
    private func handleLeftMouseDown(event: NSEvent, table: NSTableView, superview: NSView) -> Bool {
        table.enumerateAvailableRowViews({ (rowView, id) in
            if let view = rowView.subviews.first as? ChatMessageCellView, let textStorage = view.message.textStorage {
                textStorage.beginEditing();
                textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length));
                textStorage.endEditing();
            }
        });

        // TODO: handle double and tripple clicks!
        
        guard event.clickCount == 1 else {
            switch event.clickCount {
            case 2:
                 if let (itemId, idx, ts, messageView, view) = estimateSelectionPoint(event: event, table: table, superview: superview) {
                    if let textStorage = messageView.textStorage {
                        let range = textStorage.doubleClick(at: idx);
                        textStorage.beginEditing();
                        textStorage.removeAttribute(.backgroundColor, range: NSRange(location:0, length: textStorage.length));
                        if range.location != NSNotFound {
                            textStorage.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: range);
                        }
                        textStorage.endEditing();
                        selectionStart = SelectionPoint(entryId: itemId, timestamp: ts, location: range.location);
                        selectionEnd = SelectionPoint(entryId: itemId, timestamp: ts, location: range.location + range.length);
                        selectedItems.removeAll();
                        selectedItems.append(SelectionItem(entryId: itemId, timestamp: ts, sender: view.sender ?? "", attributedString: messageView.attributedString()));
                    }
                 }
                break;
            case 3:
                if let (itemId, idx, ts, messageView, view) = estimateSelectionPoint(event: event, table: table, superview: superview) {
                    if let textStorage = messageView.textStorage {
                        var before = textStorage.attributedSubstring(from: NSRange(0..<idx)).string;
                        var after = idx < textStorage.length ? textStorage.attributedSubstring(from: NSRange(idx..<textStorage.length)).string : "";
                        
                        var beginOffset = before.lastIndex(where: { CharacterSet.newlines.contains($0.unicodeScalars.first!) }) ?? before.startIndex;
                        let afterOffset = after.firstIndex(where: { CharacterSet.newlines.contains($0.unicodeScalars.first!) }) ?? after.endIndex;
                        
                        if beginOffset != before.endIndex {
                            beginOffset = before.index(after: beginOffset);
                            if beginOffset != before.endIndex {
                                before.removeSubrange(beginOffset..<before.endIndex);
                            }
                        }
                        if afterOffset != after.endIndex {
                            after.removeSubrange(afterOffset..<after.endIndex);
                        }
                        
                        selectionStart = SelectionPoint(entryId: itemId, timestamp: ts, location: (before as NSString).length);
                        selectionEnd = SelectionPoint(entryId: itemId, timestamp: ts, location: idx + (after as NSString).length);
                                                
                        textStorage.beginEditing();
                        textStorage.removeAttribute(.backgroundColor, range: NSRange(location:0, length: textStorage.length));
                        textStorage.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(selectionStart!.location..<selectionEnd!.location));
                        textStorage.endEditing();
                        
                        selectedItems.removeAll();
                        selectedItems.append(SelectionItem(entryId: itemId, timestamp: ts, sender: view.sender ?? "", attributedString: messageView.attributedString()));
                    }
                }
                break;
            default:
                break;
            }
            return true;
        }
        
        guard let (itemId, idx, ts, messageView, view) = estimateSelectionPoint(event: event, table: table, superview: superview) else {
            selectionEnd = nil;
            selectionStart = nil;
            selectedItems.removeAll();
            return false;
        }
        selectionStart = SelectionPoint(entryId: itemId, timestamp: ts, location: idx);
        inProgress = true;
        if !selectedItems.contains(where: { $0.entryId == itemId }) {
            selectedItems.append(SelectionItem(entryId: itemId, timestamp: ts, sender: view.sender ??  "", attributedString: messageView.attributedString()));
        }
        return true;
    }
    
    private func handleLeftMouseUp(event: NSEvent, table: NSTableView, superview: NSView) -> Bool {
        inProgress = false;
        guard let selectionStart = self.selectionStart, event.clickCount == 1 else {
            return false;
        }

        guard let (itemId, idx, ts, messageView, view) = estimateSelectionPoint(event: event, table: table, superview: superview) else {
            return false;
        }
        
        selectionEnd = SelectionPoint(entryId: itemId, timestamp: ts, location: idx);
        if !selectedItems.contains(where: { $0.entryId == itemId }) {
            selectedItems.append(SelectionItem(entryId: itemId, timestamp: ts, sender: view.sender ??  "", attributedString: messageView.attributedString()));
        }
        print("selection end:", selectionEnd as Any, itemId, ts, idx);
        
        guard selectionStart.entryId != selectionEnd!.entryId || selectionStart.location != selectionEnd!.location else {
            // find if we clicked on a link!
            if (messageView.textStorage?.length ?? 0) > idx, let link = messageView.textStorage?.attribute(.link, at: idx, effectiveRange: nil) as? URL {
                NSWorkspace.shared.open(link);
            }
            self.selectionStart = nil;
            self.selectionEnd = nil;
            self.selectedItems.removeAll();
            print("not selected anything!")
            return true;
        }
        
        return false;
    }
    
    private func handleLeftMouseDragged(event: NSEvent, table: NSTableView, superview: NSView) -> Bool {
        guard self.selectionStart != nil else {
            return false;
        }
        
        table.enclosingScrollView?.contentView.autoscroll(with: event);
        guard let (itemId, idx, ts, _, _) = estimateSelectionPoint(event: event, table: table, superview: superview) else {
            return false;
        }
        selectionEnd = SelectionPoint(entryId: itemId, timestamp: ts, location: idx);
        print("selection end:", selectionEnd as Any, itemId, ts, idx);
        
        guard let (begin, end) = selectionEnds() else {
            return false;
        }

        let tsRange = begin.timestamp...end.timestamp;
        
        table.enumerateAvailableRowViews({ (rowView, id) in
            if let view = rowView.subviews.first as? ChatMessageCellView {
                if let textStorage = view.message.textStorage {
                    textStorage.beginEditing();
                    textStorage.removeAttribute(.backgroundColor, range: NSRange(0..<textStorage.length))
                    if let ts = view.ts, tsRange.contains(ts) {
                        if begin.entryId == end.entryId {
                            if begin.location < end.location {
                                textStorage.addAttributes([.backgroundColor: NSColor.selectedTextBackgroundColor], range: NSRange(begin.location..<end.location));
                            }
                        } else {
                            textStorage.removeAttribute(.backgroundColor, range: NSRange(0..<textStorage.length));
                            if view.id == begin.entryId {
                                textStorage.addAttributes([.backgroundColor: NSColor.selectedTextBackgroundColor], range: NSRange(begin.location..<textStorage.length));
                            } else if view.id == end.entryId {
                                textStorage.addAttributes([.backgroundColor: NSColor.selectedTextBackgroundColor], range: NSRange(0..<end.location));
                            } else {
                                textStorage.addAttributes([.backgroundColor: NSColor.selectedTextBackgroundColor], range: NSRange(0..<textStorage.length));
                            }
                        }
                    }
                    textStorage.endEditing();
                    view.message.setNeedsDisplay(view.message.bounds);
                    if !selectedItems.contains(where: { $0.entryId == view.id }) {
                        selectedItems.append(SelectionItem(entryId: view.id, timestamp: view.ts!, sender: view.sender ??  "", attributedString: view.message.attributedString()));
                    }
                }
            }
        });
        selectedItems.removeAll(where: {
            !tsRange.contains($0.timestamp)
        });
        
        return true;
    }
    
    private func handleRightMouseDown(event: NSEvent, table: NSTableView, superview: NSView) -> Bool {
        guard let point = self.controller?.view.convert(event.locationInWindow, from: nil) else {
            return false;
        }

        guard table.enclosingScrollView?.frame.contains(point) ?? false else {
            return false;
        }

        let menu = NSMenu(title: "Actions");
        let row = table.row(at: superview.convert(event.locationInWindow, from: nil));
        if row != NSNotFound {
            self.controller?.prepareContextMenu(menu, forRow: row);
        }

        if row != NSNotFound || (selectionStart != nil && selectionEnd != nil) {
            var copy = menu.addItem(withTitle: "Copy text", action: #selector(copySelectedText), keyEquivalent: "");
            copy.target = self;
            copy.tag = row;
            copy = menu.addItem(withTitle: "Copy messages", action: #selector(copySelectedMessages), keyEquivalent: "");
            copy.target = self;
            copy.tag = row;
        }
        if let (_,idx,_,messageView,_) = self.estimateSelectionPoint(event: event, table: table, superview: superview) {
            if messageView.textStorage?.length ?? 0 > idx, let link = messageView.textStorage?.attribute(.link, at: idx, effectiveRange: nil) as? URL {
                let copy = menu.addItem(withTitle: "Copy link", action: #selector(copySelectedText), keyEquivalent: "");
                copy.target = self;
                copy.representedObject = link;
            }
        }
        if !menu.items.isEmpty {
            NSMenu.popUpContextMenu(menu, with: event, for: table);
        }
        return true;
    }
    
    private func estimateSelectionPoint(event: NSEvent, table: NSTableView, superview: NSView) -> (Int, Int, Date, MessageTextView, ChatMessageCellView)? {
        let point = superview.convert(event.locationInWindow, from: nil);
        let row = table.row(at: point);

        guard row != NSNotFound else {
            return nil;
        }
        let documentPoint = table.enclosingScrollView!.documentView!.convert(event.locationInWindow, from: nil);
        print("clicked at:", point, " hit in:", row, "document point:", documentPoint, documentPoint.y);
        guard let item = controller?.dataSource.getItem(at: row) else {
            return nil;
        }
        
        var rowView: NSTableRowView?;
        table.enumerateAvailableRowViews { (view, id) in
            if id == row {
                rowView = view;
            }
        }
        
        print("found row view:", rowView as Any, "view:", rowView?.subviews as Any, rowView?.subviews.first as Any);
        guard let view = rowView?.subviews.first as? ChatMessageCellView else {
            return nil;
        }

        let textPoint = view.message.convert(point, from: superview);
        var distance: CGFloat = 0;

        guard let glyphIdx = view.message.layoutManager?.glyphIndex(for: textPoint, in: view.message.textContainer!, fractionOfDistanceThroughGlyph: &distance) else {
            return nil;
        }
        
        let rect = view.message.layoutManager!.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 1), in: view.message.textContainer!);
        print("got item at:", textPoint, "char rect is:", rect);
        
        var inFirstHalf = true;
        if textPoint.y < rect.origin.y {
            inFirstHalf = true;
        } else if textPoint.y > (rect.origin.y + rect.height) {
            inFirstHalf = false;
        } else {
            inFirstHalf = textPoint.x < (rect.origin.x + ( rect.width / 2));
        }
        
        if inFirstHalf {
            let charIdx = view.message.layoutManager!.characterIndexForGlyph(at: glyphIdx);
            print("got item charIdx:", charIdx, "for glyph:", glyphIdx, ", firstHalf = true");
            return (item.id, charIdx, item.timestamp, view.message, view);
        } else {
            var nextIdx = glyphIdx;
            while nextIdx < view.message.layoutManager!.numberOfGlyphs - 1 {
                nextIdx = nextIdx + 1;
                let nextRect = view.message.layoutManager!.boundingRect(forGlyphRange: NSRange(location: nextIdx, length: 1), in: view.message.textContainer!);
                if !nextRect.equalTo(rect) {
                    let nextCharIdx = view.message.layoutManager!.characterIndexForGlyph(at: nextIdx);
                    print("got item next charIdx:", nextCharIdx, "for glyph:", glyphIdx, ", firstHalf = false");
                    return (item.id, nextCharIdx, item.timestamp, view.message, view);
                }
            }
            print("got item next2 charIdx:", view.message.textStorage!.length, "for glyph:", glyphIdx, ", firstHalf = false");
            return (item.id, view.message.textStorage!.length, item.timestamp, view.message, view);
        }
    }
    
    struct SelectionPoint {
        var entryId: Int;
        var timestamp: Date;
        var location: Int;
    }
    
    struct SelectionItem {
        var entryId: Int;
        var timestamp: Date;
        var sender: String;
        var attributedString: NSAttributedString;
    }
//        switch event.type {
//        case .leftMouseDown:
//
//        default:
//
//        }
        //        switch event.type {
        //        case .mouseMoved:
        //            if currentSession == nil {
        //                guard let messageView = messageViewFor(event: event) else {
        //                    NSCursor.pointingHand.pop();
        //                    return isInMesageView(event: event);
        //                }
        //                if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
        //                    if (messageView.message.attributedStringValue.attribute(.link, at: idx, effectiveRange: nil) as? URL) != nil {
        //                        if NSCursor.current != NSCursor.pointingHand {
        //                            NSCursor.pointingHand.push();
        //                        }
        //                    } else {
        //                        NSCursor.pointingHand.pop();
        //                    }
        //                } else {
        //                    NSCursor.pointingHand.pop();
        //                }
        //            }
        //            return false;
        //        case .leftMouseDown:
        //            if currentSession != nil {
        //                let visibleRows = self.tableView.rows(in: self.tableView.visibleRect);
        //                for row in visibleRows.lowerBound..<visibleRows.upperBound {
        //                    if let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView {
        //                        let str = NSMutableAttributedString(attributedString: view.message.attributedStringValue);
        //                        str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length));
        //                        view.message.attributedStringValue = str;
        //                    }
        //                }
        //            }
        //            currentSession = nil;
        //
        //            guard event.clickCount == 1 else {
        //                if event.clickCount == 2 {
        //                    guard let messageView = messageViewFor(event: event) else {
        //                        return isInMesageView(event: event);
        //                    }
        //                    if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
        //                        let str = messageView.message.stringValue;
        //                        let clickIdx = str.index(str.startIndex, offsetBy: idx);
        //                        let before = str[str.startIndex...clickIdx]
        //                        let after = str[str.index(after: clickIdx)..<str.endIndex];
        //                        let beforeIdx = before.lastIndex { (c) -> Bool in
        //                            return !CharacterSet.alphanumerics.contains(c.unicodeScalars.first!);
        //                        }
        //                        let prefix = beforeIdx != nil ? before[before.index(after: beforeIdx!)..<before.endIndex] : before;
        //                        let afterIdx = after.firstIndex { (c) -> Bool in
        //                            return !CharacterSet.alphanumerics.contains(c.unicodeScalars.first!);
        //                        }
        //                        let suffix = (afterIdx != nil) ? ((afterIdx! != after.startIndex) ? after[after.startIndex...after.index(before: afterIdx!)] : nil) : after;
        //                        print("got:", prefix, suffix as Any, "\(String(prefix))\(String(suffix ?? ""))");
        //                        let attrStr = NSMutableAttributedString(attributedString: messageView.message.attributedStringValue);
        //                        let len = (prefix.count + (suffix?.count ?? 0));
        //                        attrStr.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: before.count - prefix.count,  length: len));
        //                        messageView.message.attributedStringValue = attrStr;
        //                        self.currentSession = TextSelectionSession(messageView: messageView, selected: "\(String(prefix))\(String(suffix ?? ""))");
        //                            return true;
        //                        }
        //                    }
        //                    if event.clickCount == 3 {
        //                        guard let messageView = messageViewFor(event: event) else {
        //                            return isInMesageView(event: event);
        //                        }
        //                    if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
        //                        let str = messageView.message.stringValue;
        //                        let clickIdx = str.index(str.startIndex, offsetBy: idx);
        //                        let before = str[str.startIndex...clickIdx]
        //                        let after = str[str.index(after: clickIdx)..<str.endIndex];
        //                        let beforeIdx = before.lastIndex { (c) -> Bool in
        //                            return CharacterSet.newlines.contains(c.unicodeScalars.first!);
        //                        }
        //                        let prefix = beforeIdx != nil ? before[before.index(after: beforeIdx!)..<before.endIndex] : before;
        //                        let afterIdx = after.firstIndex { (c) -> Bool in
        //                            return CharacterSet.newlines.contains(c.unicodeScalars.first!);
        //                        }
        //                        let suffix = (afterIdx != nil && (afterIdx! != after.startIndex)) ? after[after.startIndex...after.index(before: afterIdx!)] : after;
        //                        print("got:", prefix, suffix, "\(String(prefix))\(String(suffix))");
        //                        let attrStr = NSMutableAttributedString(attributedString: messageView.message.attributedStringValue);
        //                        let len = (prefix.count + suffix.count);
        //                        attrStr.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: before.count - prefix.count,  length: len));
        //                        messageView.message.attributedStringValue = attrStr;
        //                        self.currentSession = TextSelectionSession(messageView: messageView, selected: "\(String(prefix))\(String(suffix))");
        //                        return true;
        //                    }
        //                }
        //                //return false;
        //                return false;
        //            }
        //
        //            guard let messageView = messageViewFor(event: event) else {
        //                return isInMesageView(event: event);
        //            }
        //
        //            self.currentSession = SelectionSession(messageView: messageView, event: event);
        //
        //            return true;//currentSession != nil;
        //        case .leftMouseUp:
        //            NSCursor.pointingHand.pop();
        //
        //            guard let session = currentSession as? SelectionSession else {
        //                return false;
        //            }
        //            if session.selected?.isEmpty ?? true {
        //                currentSession = nil;
        //            }
        //
        //            guard let messageView = messageViewFor(event: event) else {
        //                return isInMesageView(event: event);
        //            }
        //
        //            if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
        //                if let link = messageView.message.attributedStringValue.attribute(.link, at: idx, effectiveRange: nil) as? URL {
        //                    if session.position.location == idx && session.messageId == messageView.id {
        //                        NSWorkspace.shared.open(link);
        //                    }
        //                    NSCursor.pointingHand.push();
        //                }
        //            }
        //
        //            return true;
        //        case .leftMouseDragged:
        //            guard let session = self.currentSession as? SelectionSession else {
        //                return false;
        //            }
        //            NSCursor.pointingHand.pop();
        //
        //            let point = self.tableView.convert(event.locationInWindow, from: nil);
        //            let currRow = self.tableView.row(at: point);
        //            let startRow = self.tableView.row(at: self.tableView.convert(session.point, from: nil));
        //            guard currRow >= 0 && startRow >= 0 else {
        //                return false;
        //            }
        //            guard let messageView = messageViewFor(event: event) else {
        //                return false;
        //            }
        //            guard let idx = messageView.message.characterIndexFor(event: event) else {
        //                return false;
        //            }
        //
        //            let visibleRows = self.tableView.rows(in: self.tableView.visibleRect);
        //            for row in visibleRows.lowerBound..<visibleRows.upperBound {
        //                if let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView {
        //                    let str = NSMutableAttributedString(attributedString: view.message.attributedStringValue);
        //                    str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length));
        //                    view.message.attributedStringValue = str;
        //                }
        //            }
        //
        //            let begin = max(startRow, currRow);
        //            let end = min(startRow, currRow);
        //            for row in end...begin {
        //                if let view = self.tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView {
        //                    let str = NSMutableAttributedString(attributedString: view.message.attributedStringValue);
        //                    str.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: str.length));
        //                    if row == begin {
        //                        if row == end {
        //                            let s1 = min(session.position, idx);
        //                            let s2 = max(session.position, idx);
        //                            //print("s1:", s1, "s2:", s2, "length:", (s2-s1) + 1);
        //                            str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: s1.location, length: (s2.upperBound - s1.location)));
        //                            print("str:", str, s1, s2, idx.length, str.length, str.string.last as Any);
        //                        } else {
        //                            let start = begin == startRow ? session.position : idx;
        //                            str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: start.location, length: (str.length - start.location)));
        //                        }
        //                    } else if row == end {
        //                        let start = end == startRow ? session.position : idx;
        //                        str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range: NSRange(location: 0, length: start.upperBound));
        //                    } else {
        //                        str.addAttribute(.backgroundColor, value: NSColor.selectedTextBackgroundColor, range:   NSRange(location: 0, length: str.length));
        //                    }
        //                    view.message.attributedStringValue = str;
        //                }
        //            }
        //
        //            let range = tableView.rows(in: tableView.visibleRect);
        //            let selected = dataSource.getItems(fromId: session.messageId, toId: messageView.id, inRange: range).filter { (item) -> Bool in
        //                return item is ChatMessage;
        //                }.map { (item) -> ChatMessage in
        //                    return item as! ChatMessage;
        //            }
        //            if selected.count == 1 {
        //                let s1 = min(session.position, idx);
        //                let s2 = max(session.position, idx);
        //                session.selection(selected, startOffset: s1.lowerBound, endOffset: s2.upperBound);
        //            } else {
        //                let inverted = (selected.first?.id ?? 0) != session.messageId;
        //
        //                session.selection(selected, startOffset: (inverted ? idx : session.position).lowerBound, endOffset: (inverted ? session.position : idx).upperBound);
        //            }
        //            return true;
        //        case .rightMouseDown:
        //            let point = self.view.convert(event.locationInWindow, from: nil);
        //    //            print("point:", point, "frame:", self.tableView.enclosingScrollView?.frame);
        //            guard self.tableView.enclosingScrollView?.frame.contains(point) ?? false else {
        //                return false;
        //            }
        //            let menu = NSMenu(title: "Actions");
        //            let tag = currentSession != nil ? -1 : (self.messageId(for: event) ?? -1);
        //            if tag != -1 {
        //                if let row = row(for: event) {
        //                    self.prepareContextMenu(menu, forRow: row);
        //                }
        //            }
        //            if tag != -1 || currentSession != nil {
        //                var copy = menu.addItem(withTitle: "Copy text", action: #selector(copySelectedText), keyEquivalent: "");
        //                copy.target = self;
        //                copy.tag = tag;
        //                copy = menu.addItem(withTitle: "Copy messages", action: #selector(copySelectedMessages), keyEquivalent: "");
        //                copy.target = self;
        //                copy.tag = tag;
        //            }
        //            if let messageView = messageViewFor(event: event) {
        //                if let idx = messageView.message.characterIndexFor(event: event)?.location, idx != 0 {
        //                    if let link = messageView.message.attributedStringValue.attribute(.link, at: idx, effectiveRange: nil) as? URL {
        //                        let copy = menu.addItem(withTitle: "Copy link", action: #selector(copySelectedText), keyEquivalent: "");
        //                        copy.target = self;
        //                        copy.representedObject = link;
        //                    }
        //                }
        //            }
        //
        //            if !menu.items.isEmpty {
        //                NSMenu.popUpContextMenu(menu, with: event, for: self.tableView);
        //            }
        //            return true;
        //        default:
        //            break;
        //        }
        //        return false;
        //    }

    
}
