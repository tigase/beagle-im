//
// AutoresizingTextField.swift
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
            if intrinsicSize.height < 22 {
                intrinsicSize.height = 22;
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
    
    func reset(repeat val: Bool = true) {
        self.hasLastIntrinsicSize = false;
        self.invalidateIntrinsicContentSize();
        self.stringValue = "";
    }
}
