//
// AutoresizineTextView.swift
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

protocol PastingDelegate {
    
    func paste(in: AutoresizingTextView, pasteboard: NSPasteboard) -> Bool;
    
}

class AutoresizingTextView: NSTextView, NSTextStorageDelegate {
    
    @objc var placeholderAttributedString: NSAttributedString?;
    
    weak var dragHandler: (NSDraggingDestination & PastingDelegate)? = nil;
      
    override var rangeForUserCompletion: NSRange {
        let currRange = super.rangeForUserCompletion;
//        if currRange.length == 0 {
//            return currRange;
//        }
        let val = self.string as NSString
        var spaceRange = val.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: NSRange(location: 0, length: currRange.location));
        if spaceRange.location == NSNotFound {
            spaceRange = NSRange(location: 0, length: 0);
        } else if currRange.length == 0 && spaceRange.location + spaceRange.length + 1 >= currRange.location {
            return NSRange(location: 0, length: 0);
        }
        
        let rangeWithAt = NSRange(location: spaceRange.location + spaceRange.length, length: currRange.length + (currRange.location - (spaceRange.location + spaceRange.length)));
        
        return rangeWithAt;
    }
    
    override var string: String {
        didSet {
            self.invalidateIntrinsicContentSize();
        }
    }
    
    override func awakeFromNib() {
        setup();
    }
    
    func setup() {
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize);
        self.textStorage?.delegate = self;
        self.textContainer!.replaceLayoutManager(MessageTextView.CustomLayoutManager());
    }
    
    override var intrinsicContentSize: NSSize {
        self.layoutManager?.typesetterBehavior = .latestBehavior;
        self.layoutManager!.ensureLayout(for: self.textContainer!);
        self.layoutManager!.glyphRange(for: textContainer!);
        return layoutManager!.usedRect(for: self.textContainer!).size;
    }
    
    override func didChangeText() {
        super.didChangeText();
        self.invalidateIntrinsicContentSize();
    }
    
    override func paste(_ sender: Any?) {
        if dragHandler?.paste(in: self, pasteboard: NSPasteboard.general) ?? false {
            // nothing to do..
        } else {
            super.paste(sender);
        }
    }
    
    func pasteURLs(_ sender: Any?) {
        super.paste(sender);
    }
    
    func reset() {
        self.string = "";
    }
    
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: nil);
    }
    
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize);
        let fullRange = NSRange(0..<textStorage.length);
        textStorage.setAttributes([.font: font], range: fullRange);
        textStorage.fixAttributes(in: fullRange);
        textStorage.addAttributes([.foregroundColor: NSColor.textColor], range: fullRange);
        
        if Settings.enableMarkdownFormatting {
             Markdown.applyStyling(attributedString: textStorage, fontSize: NSFont.systemFontSize, showEmoticons: false);
        }
    }
    
    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard let handler = self.dragHandler?.draggingEnded else {
            super.draggingEnded(sender);
            return;
        }
        handler(sender);
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let handler = self.dragHandler?.draggingEntered else {
            return super.draggingEntered(sender);
        }
        let res = handler(sender);
        if res == [] {
            return super.draggingEntered(sender);
        } else {
            return res;
        }
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let handler = self.dragHandler?.draggingUpdated else {
            return super.draggingUpdated(sender);
        }
        let res = handler(sender);
        if res == [] {
            return super.draggingUpdated(sender);
        } else {
            return res;
        }
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard let handler = self.dragHandler?.draggingExited else {
            super.draggingExited(sender);
            return;
        }
        handler(sender);
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return (dragHandler?.performDragOperation?(sender) ?? false) || super.performDragOperation(sender);
    }
    
    override func pasteAsPlainText(_ sender: Any?) {
        super.pasteAsPlainText(sender);
    }
 
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        (self.undoManager ?? self.window?.undoManager)?.removeAllActions();
    }
}
