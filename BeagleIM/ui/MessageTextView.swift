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
                return .zero
            }

            textContainer.size = NSSize(width: self.superview!.bounds.width - 68, height: CGFloat.greatestFiniteMagnitude);
            layoutManager.ensureLayout(for: textContainer);
            //layoutManager.glyphRange(for: textContainer);
            let size = layoutManager.usedRect(for: textContainer).size;
            //print("rendered size:", size, self.superview!.superview!.bounds.width, textContainer.size, "for:", self.string, "superview:", self.superview);
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
            self.textStorage?.beginEditing();
            self.textStorage?.setAttributedString(newValue);
            if alignment == .center {
                let style = NSMutableParagraphStyle();
                style.alignment = .center;
                self.textStorage?.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: textStorage!.length));
            }
            self.textStorage?.endEditing();
            self.invalidateIntrinsicContentSize();
        }
    }
    
    private var heightConstraint: NSLayoutConstraint?;

    override func awakeFromNib() {
        self.maxSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude);
        
        self.textContainer!.replaceLayoutManager(CustomLayoutManager());
        
        self.layoutManager?.delegate = self;
        self.layoutManager?.typesetterBehavior = .latestBehavior;
        //self.layoutManager?.backgroundLayoutEnabled = false;
        self.textContainer?.lineFragmentPadding = 1;
        self.textContainerInset = .zero;
        self.textContainer?.widthTracksTextView = false;
        self.textContainer?.heightTracksTextView = false;
        self.usesAdaptiveColorMappingForDarkAppearance = true;
    }
        
    class CustomLayoutManager: NSLayoutManager {
        
        override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
            super.drawBackground(forGlyphRange: glyphsToShow, at: origin);
//            let rect = self.boundingRect(forGlyphRange: glyphsToShow, in: self.textContainers.first!);
            
            let charRange = self.characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil);
            textStorage!.enumerateAttribute(.paragraphStyle, in: charRange, options: [], using: { (value, range, pth) in
                guard let paragraph = value as? Markdown.ParagraphStyle else {
                    return;
                }
                
                if let type = paragraph.type {
                    switch type {
                    case .quote:
                        let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil);
                        let rect = self.boundingRect(forGlyphRange: glyphRange, in: self.textContainers.first!)
                    
                        NSColor.textColor.withAlphaComponent(0.2).setFill();
                        let path = NSBezierPath(rect: NSRect(x: (rect.origin.x > paragraph.firstLineHeadIndent) ? 1 : rect.origin.x, y: rect.origin.y, width: 2, height: rect.height));
                        path.fill();
                    case .code:
                        let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil);
                        let rect = self.boundingRect(forGlyphRange: glyphRange, in: self.textContainers.first!)
                    
                        NSColor.textColor.withAlphaComponent(0.5).setFill();
                        let path = NSBezierPath(rect: NSRect(origin: rect.origin, size: NSSize(width: 2, height: rect.height)));
                        path.fill();
                    case .list:
                        break;
                    }
                }
            })
        }
        
    }
}
