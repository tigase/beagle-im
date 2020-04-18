//
// MessageTextView.swift
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

class MessageTextView: NSTextView, NSLayoutManagerDelegate {
    
    override var intrinsicContentSize: NSSize {
        get {
            guard let layoutManager = layoutManager, let textContainer = textContainer else {
                print("textView no layoutManager or textContainer")
                return .zero
            }

            textContainer.containerSize = NSSize(width: self.frame.width, height: CGFloat.greatestFiniteMagnitude);
            layoutManager.ensureLayout(for: textContainer);
            layoutManager.glyphRange(for: textContainer);
            let size = layoutManager.usedRect(for: textContainer).size;
            if heightConstraint == nil {
                heightConstraint = self.heightAnchor.constraint(equalToConstant: size.height);
                heightConstraint?.isActive = true;
            } else {
                self.heightConstraint?.constant = size.height;
            }
            return size;
        }
    }
        
    var attributedString: NSAttributedString {
        get {
            guard let textStorage = self.textStorage else {
                return NSAttributedString(string: "");
            }
            return textStorage.attributedSubstring(from: NSRange(location: 0, length: textStorage.length));
        }
        set {
            let alignment = self.alignment;
            self.textStorage?.setAttributedString(newValue);
            if alignment == .center {
                let style = NSMutableParagraphStyle();
                style.alignment = .center;
                self.textStorage?.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: textStorage!.length));
            }
            self.invalidateIntrinsicContentSize();
        }
    }
    
    private var heightConstraint: NSLayoutConstraint?;

    override func awakeFromNib() {
        self.translatesAutoresizingMaskIntoConstraints = false;
        self.layoutManager?.delegate = self;
        self.textContainer?.widthTracksTextView = true;
        self.textContainer?.heightTracksTextView = true;
        self.textContainer?.lineFragmentPadding = 1;
        self.textContainerInset = .zero;
        self.usesAdaptiveColorMappingForDarkAppearance = true;
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager, didCompleteLayoutFor textContainer: NSTextContainer?, atEnd layoutFinishedFlag: Bool) {
        self.invalidateIntrinsicContentSize();
    }
    
}
