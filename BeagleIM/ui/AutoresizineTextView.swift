//
// AutoresizineTextView.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit

class AutoresizingTextView: NSTextView, NSTextStorageDelegate {
  
    @objc var placeholderAttributedString: NSAttributedString?;
    
    weak var dragHandler: NSDraggingDestination? = nil;
    
    override func awakeFromNib() {
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular));
        self.textStorage?.delegate = self;
    }
    
    override var intrinsicContentSize: NSSize {
        self.layoutManager!.ensureLayout(for: self.textContainer!);
        return layoutManager!.usedRect(for: self.textContainer!).size;
    }
    
    override func didChangeText() {
        super.didChangeText();
        self.invalidateIntrinsicContentSize();
    }
    
    func reset() {
        self.string = "";
        self.invalidateIntrinsicContentSize();
    }
    
    func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        let fullRange = NSRange(0..<textStorage.length);
        textStorage.fixAttributes(in: fullRange);
        //textStorage.setAttributes([.font: self.font!], range: fullRange);
        textStorage.addAttributes([.foregroundColor: NSColor.textColor], range: fullRange);
        
        if Settings.enableMarkdownFormatting.bool() {
            Markdown.applyStyling(attributedString: textStorage, showEmoticons: false);
        }
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return (dragHandler?.performDragOperation?(sender) ?? false) || super.performDragOperation(sender);
    }
}
