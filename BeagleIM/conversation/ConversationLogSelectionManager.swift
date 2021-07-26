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

class ConversationLogSelectionManager: ChatViewTableViewMouseDelegate {
    
    private var mouseMonitor: Any?;
    private weak var controller: AbstractConversationLogController?;
    private var selectionStart: SelectionPoint?;
    private var selectionEnd: SelectionPoint?;
    private var selectedItems: [SelectionItem] = [];
    
    private(set) var inProgress: Bool = false;
    
    var hasSelection: Bool {
        return selectionStart != nil && selectionEnd != nil;
    }
    
    var hasSingleSender: Bool {
        return Set(selectedItems.map({ $0.entry.sender.nickname })).count == 1;
    }
    
    deinit {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor);
        }
        mouseMonitor = nil;
    }
    
    func initilizeHandlers(controller: AbstractConversationLogController) {
        self.controller = controller;
        (self.controller?.tableView as? ChatViewTableView)?.mouseDelegate = self;
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] (event) -> NSEvent? in
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
        guard let testPoint = controller?.view.convert(event.locationInWindow, from: nil), controller?.view.visibleRect.contains(testPoint) ?? false else {
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
        
        guard let texts = self.selection?.selectedTexts else {
            return;
        }

        NSPasteboard.general.clearContents();
        NSPasteboard.general.writeObjects(texts);
    }
    
    @objc func copySelectedMessages(_ sender: Any) {
        let dateFormatter = DateFormatter();
        dateFormatter.locale = Locale(identifier: "en_US_POSIX");
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss";

        NSPasteboard.general.clearContents();
        guard let items = self.selection?.items else {
            return;
        }
        let texts: [NSAttributedString] = items.map {
            let item = NSMutableAttributedString(string: "[\(dateFormatter.string(from: $0.timestamp))] <\($0.entry.sender.nickname ?? "")>: ");
            item.applyFontTraits(.boldFontMask, range: NSRange(0..<item.length));
            item.append($0.attributedString);
            item.removeAttribute(.backgroundColor, range: NSRange(location:0, length: item.length));
            return item;
        };
        NSPasteboard.general.writeObjects(texts);
    }
    
//    func sortedSelectedTexts(row: Int) -> [NSMutableAttributedString] {
//        let texts = sortedSelectionItems(row: row).map { NSMutableAttributedString(attributedString: $0.attributedString) };
//
//        for text in texts {
//            text.removeAttribute(.backgroundColor, range: NSRange(location:0, length: text.length));
//        }
//
//        if let (begin,end) = selectionEnds() {
//            if let text = texts.last {
//                if end.location < text.length {
//                    text.deleteCharacters(in: NSRange(end.location..<text.length));
//                }
//            }
//            if let text = texts.first {
//                if begin.location > 0 {
//                    text.deleteCharacters(in: NSRange(0..<begin.location));
//                }
//            }
//        }
//        return texts;
//    }
//
//    func sortedSelectionItems(row: Int) -> [SelectionItem] {
//        guard let (begin,end) = selectionEnds() else {
//            guard row != NSNotFound, let view = self.controller?.tableView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ChatMessageCellView, let item = self.controller?.dataSource.getItem(at: row) as? ConversationEntryWithSender else {
//                return [];
//            }
//            return [SelectionItem(entry: item, attributedString: view.message.attributedString())];
//        }
//
//        let range = begin.timestamp...end.timestamp;
//        return selectedItems.filter({ range.contains($0.timestamp) }).sorted(by: { (e1, e2) -> Bool in
//            if e1.timestamp == e2.timestamp {
//                return e1.entryId < e2.entryId;
//            }
//            return e1.timestamp < e2.timestamp;
//        });
//    }
    
    var selection: Selection?;
        
    private func handleLeftMouseDown(event: NSEvent, table: NSTableView, superview: NSView) -> Bool {
        table.enumerateAvailableRowViews({ (rowView, id) in
            if let view = rowView.subviews.first as? ChatMessageCellView, let textStorage = view.message.textStorage {
                textStorage.beginEditing();
                textStorage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: textStorage.length));
                textStorage.endEditing();
            }
        });

        guard (table.enclosingScrollView?.verticalScroller?.testPart(event.locationInWindow) ?? .noPart) == .noPart else {
            return false;
        }
        
        selection = nil;
        
        guard event.clickCount == 1 else {
            switch event.clickCount {
            case 2:
                 if let (itemId, idx, ts, messageView, _) = estimateSelectionPoint(event: event, table: table, superview: superview) {
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
                        if let item = self.controller?.dataSource.getItem(withId: itemId) {
                            selectedItems.append(SelectionItem(entry: item, attributedString: messageView.attributedString()));
                            self.selection = Selection(items: selectedItems, ends: selectionEnds());
                        }
                    }
                 }
                break;
            case 3:
                if let (itemId, idx, ts, messageView, _) = estimateSelectionPoint(event: event, table: table, superview: superview) {
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
                        if let item = self.controller?.dataSource.getItem(withId: itemId) {
                            selectedItems.append(SelectionItem(entry: item, attributedString: messageView.attributedString()));
                            self.selection = Selection(items: selectedItems, ends: selectionEnds());
                        }
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
            selection = nil;
            return false;
        }
        print("selection hitTest():", view, view.hitTest(view.superview!.convert(event.locationInWindow, from: nil)) as Any, (table.enclosingScrollView?.verticalScroller?.testPart(event.locationInWindow) ?? .noPart) == .noPart );
        selectionStart = SelectionPoint(entryId: itemId, timestamp: ts, location: idx);
        inProgress = true;
        if !selectedItems.contains(where: { $0.entryId == itemId }) {
            if let item = self.controller?.dataSource.getItem(withId: itemId) {
                selectedItems.append(SelectionItem(entry: item, attributedString: messageView.attributedString()));
            }
        }
        return true;
    }
    
    private func handleLeftMouseUp(event: NSEvent, table: NSTableView, superview: NSView) -> Bool {
        inProgress = false;
        guard let selectionStart = self.selectionStart, event.clickCount <= 1 else {
            return false;
        }

        guard let (itemId, idx, ts, messageView, _) = estimateSelectionPoint(event: event, table: table, superview: superview) else {
            return false;
        }
        
        selectionEnd = SelectionPoint(entryId: itemId, timestamp: ts, location: idx);
        if !selectedItems.contains(where: { $0.entryId == itemId }) {
            if let item = self.controller?.dataSource.getItem(withId: itemId) {
                selectedItems.append(SelectionItem(entry: item, attributedString: messageView.attributedString()));
            }
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
            self.selection = nil;
            return true;
        }
        
        self.selection = Selection(items: selectedItems, ends: selectionEnds());
        
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
            if let view = rowView.subviews.first as? ChatMessageCellView, let item = self.controller?.dataSource.getItem(withId: view.id) {
                if let textStorage = view.message.textStorage {
                    textStorage.beginEditing();
                    textStorage.removeAttribute(.backgroundColor, range: NSRange(0..<textStorage.length))
                    if tsRange.contains(item.timestamp) {
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
                        selectedItems.append(SelectionItem(entry: item, attributedString: view.message.attributedString()));
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
        
        let row = table.row(at: superview.convert(event.locationInWindow, from: nil));
       
        if selection == nil {
            if row != NSNotFound, let view = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? ChatMessageCellView, let item = controller?.dataSource.getItem(at: row) {
                selection = Selection(items: [SelectionItem(entry: item, attributedString: view.message.attributedString())], ends: nil);
            }
        }

        let menu = Menu(title: "Actions", selectionManager: self);
        

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
        if row != NSNotFound {
            self.controller?.prepareContextMenu(menu, forRow: row);
        }
        if !menu.items.isEmpty {
            NSMenu.popUpContextMenu(menu, with: event, for: table);
        }
        return true;
    }
    
    class Menu: NSMenu {
        
        private weak var selectionManager: ConversationLogSelectionManager?;
        
        init(title: String, selectionManager: ConversationLogSelectionManager) {
            self.selectionManager = selectionManager;
            super.init(title: title);
        }
        
        required init(coder: NSCoder) {
            super.init(coder: coder);
        }
        
        deinit {
            if let selectionManager = self.selectionManager {
                DispatchQueue.main.async {
                    selectionManager.selection = nil;
                }
            }
        }
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
    
    struct Selection {
        let items: [SelectionItem];
        let begin: SelectionPoint?;
        let end: SelectionPoint?;
        
        init(items: [SelectionItem], ends: (SelectionPoint,SelectionPoint)?) {
            if let ends = ends {
                self.begin = ends.0;
                self.end = ends.1;
            } else {
                begin = nil;
                end = nil;
            }
            self.items = items;
        }
        
        var selectedTexts: [NSAttributedString] {
            let texts = items.map { NSMutableAttributedString(attributedString: $0.attributedString) };

            for text in texts {
                text.removeAttribute(.backgroundColor, range: NSRange(location:0, length: text.length));
            }
            
            if let begin = begin, let end = end {
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
            return texts;
        }
        
    }
    
    struct SelectionPoint {
        var entryId: Int;
        var timestamp: Date;
        var location: Int;
    }
 
    struct SelectionItem {
        var entryId: Int {
            return entry.id;
        }
        var timestamp: Date {
            return entry.timestamp;
        }
        var entry: ConversationEntry;
        var attributedString: NSAttributedString;
    }

}
