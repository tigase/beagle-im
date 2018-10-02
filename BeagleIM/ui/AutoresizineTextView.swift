//
//  AutoresizineTextView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 01/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class AutoresizingTextView: NSTextView {
  
    override func awakeFromNib() {
        self.font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .regular));
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
}
