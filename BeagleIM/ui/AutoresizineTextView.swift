//
//  AutoresizineTextView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 01/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class AutoresizingTextView: NSTextView, NSTextStorageDelegate {
  
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
            Markdown.applyStyling(attributedString: textStorage);
        }
    }
}
