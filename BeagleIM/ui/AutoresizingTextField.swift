//
//  AutoresizingTextField.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 29.08.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class AutoresizingTextField: NSTextField {
    
    fileprivate var editing = false;
    fileprivate var lastIntrinsicSize = NSSize.zero;
    fileprivate var hasLastIntrinsicSize = false;
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        self.focusRingType = .none;
    }
    
    override var intrinsicContentSize: NSSize {
        var intrinsicSize = lastIntrinsicSize;
        
        if editing || !hasLastIntrinsicSize {
            intrinsicSize = super.intrinsicContentSize;
            if let editor = self.window?.fieldEditor(false, for: self) {
                if let textContainer = (editor as? NSTextView)?.textContainer {
                    if let usedRect = textContainer.layoutManager?.usedRect(for: textContainer) {
                        intrinsicSize.height = usedRect.size.height + 5.0;
                    }
                }
            }
            if intrinsicSize.height < 100 || !hasLastIntrinsicSize {
                lastIntrinsicSize = intrinsicSize;
            }
            hasLastIntrinsicSize = true;
        }
        return intrinsicSize;
    }
    
    override func textDidBeginEditing(_ notification: Notification) {
        super.textDidBeginEditing(notification);
        editing = true;
    }
    
    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification);
        editing = false;
    }
    
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification);
        self.invalidateIntrinsicContentSize();
    }
    
    func reset() {
        self.stringValue = "";
        self.hasLastIntrinsicSize = false;
        self.invalidateIntrinsicContentSize();
    }
}
