//
// RoundButton.swift
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

@IBDesignable
public class RoundButton: NSButton {
    
    @IBInspectable
    var backgroundColor: NSColor = NSColor.textBackgroundColor;
    @IBInspectable
    var marginRatio: CGFloat = 4.0;

    var hasBorder: Bool = true;
    
    fileprivate(set) var mouseDown: Bool = false {
        didSet {
            self.highlight(mouseDown);
            self.state = mouseDown ? .on : .off;
            self.needsDisplay = true;
        }
    }
    
    public override func draw(_ dirtyRectX: NSRect) {
        let dirtyRect = self.bounds;
        NSGraphicsContext.saveGraphicsState();
        
        let path = NSBezierPath(roundedRect: dirtyRect, xRadius: frame.width/2, yRadius: frame.width/2);
        path.addClip();

        if mouseDown {
            NSColor.unemphasizedSelectedContentBackgroundColor.setFill();
        } else {
            backgroundColor.setFill();
        }
        path.fill();

        if hasBorder {
            path.lineWidth = 1;
            if NSApp.isDarkMode {
                NSColor.darkGray.setStroke();
            } else {
                NSColor.lightGray.setStroke();
            }
            path.stroke();
        }
        
        NSGraphicsContext.restoreGraphicsState();

        let margin = max(dirtyRect.width, dirtyRect.height) / marginRatio;
        let imageFrame = NSRect(x: margin, y: margin, width: dirtyRect.width - (2 * margin), height: dirtyRect.height - (2 * margin));
        let tint = contentTintColor ?? NSColor.textColor;
        if let image: NSImage = (self.cell as? NSButtonCell)?.image?.copy() as? NSImage {
            image.lockFocus();
            tint.set();
            NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop);
            image.unlockFocus();
            image.isTemplate = false;
            (self.cell as? NSButtonCell)?.drawImage(image, withFrame: imageFrame, in: self);
        }
        //(self.cell as? NSButtonCell)?.drawImage(self.cell!.image!, withFrame: imageFrame, in: self);
    }
    
    public override func mouseDown(with event: NSEvent) {
        if isEnabled {
            mouseDown = true;
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        if mouseDown {
            mouseDown = false;
            _ = target?.perform(action, with: self);
        }
    }
    
    public override func mouseExited(with event: NSEvent) {
        if mouseDown {
            mouseDown = false;
        }
    }
    
}
