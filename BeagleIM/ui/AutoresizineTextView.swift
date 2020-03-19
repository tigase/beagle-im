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

class AutoresizingTextView: NSTextView, NSTextStorageDelegate {
  
    @objc var placeholderAttributedString: NSAttributedString?;
    
    weak var dragHandler: NSDraggingDestination? = nil;
    
    override var rangeForUserCompletion: NSRange {
        let currRange = super.rangeForUserCompletion;
        if currRange.length == 0 {
            return currRange;
        }
        let val = self.string as NSString
        var spaceRange = val.rangeOfCharacter(from: .whitespacesAndNewlines, options: .backwards, range: NSRange(location: 0, length: currRange.location));
        if spaceRange.location == NSNotFound {
            spaceRange = NSRange(location: 0, length: 0);
        }
        let rangeWithAt = NSRange(location: spaceRange.location + spaceRange.length, length: currRange.length + (currRange.location - (spaceRange.location + spaceRange.length)));
        
        let atRange = val.rangeOfCharacter(from: CharacterSet(charactersIn: "@"), options: [], range: NSRange(location: rangeWithAt.location, length: 1));
        if atRange.location != NSNotFound {
            return NSRange(location: atRange.location + atRange.length, length: rangeWithAt.length - atRange.length);
        } else {
            return NSRange(location: NSNotFound, length: 0);
        }
    }
    
    override var string: String {
        didSet {
            self.invalidateIntrinsicContentSize();
        }
    }
    
    override func awakeFromNib() {
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1.0, weight: .light);
        self.textStorage?.delegate = self;
    }
    
    override var intrinsicContentSize: NSSize {
        print("font:", self.font as Any, "size:", self.font?.pointSize as Any, "system:", NSFont.systemFont(ofSize: NSFont.systemFontSize - 1.0, weight: .light), "inset:", self.textContainerInset, "origin:", self.textContainerOrigin);
        self.layoutManager?.typesetterBehavior = .latestBehavior;
        self.layoutManager!.ensureLayout(for: self.textContainer!);
        self.layoutManager!.glyphRange(for: textContainer!);
        return layoutManager!.usedRect(for: self.textContainer!).size;
    }
    
    override func didChangeText() {
        super.didChangeText();
        self.invalidateIntrinsicContentSize();
    }
    
    func reset() {
        self.string = "";
    }
    
    override func cancelOperation(_ sender: Any?) {
        NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: nil);
    }
    
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1.0, weight: .light);
        let fullRange = NSRange(0..<textStorage.length);
        textStorage.fixAttributes(in: fullRange);
        //textStorage.setAttributes([.font: self.font!], range: fullRange);
        textStorage.addAttributes([.foregroundColor: NSColor.textColor], range: fullRange);
        
        if Settings.enableMarkdownFormatting.bool() {
            Markdown.applyStyling(attributedString: textStorage, showEmoticons: false);
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
        if res == .generic {
            return super.draggingUpdated(sender);
        } else {
            return res;
        }
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let handler = self.dragHandler?.draggingUpdated else {
            return super.draggingUpdated(sender);
        }
        let res = handler(sender);
        if res == .generic {
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
}
