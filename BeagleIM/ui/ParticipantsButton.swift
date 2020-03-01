//
// ParticipantsButton.swift
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

@IBDesignable
class ParticipantsButton: NSButton {
    
    @IBInspectable
    var marginRatio: CGFloat = 5.0;

    fileprivate(set) var mouseDown: Bool = false {
        didSet {
            self.highlight(mouseDown);
            self.state = mouseDown ? .on : .off;
            self.needsDisplay = true;
        }
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState();
        
        let radius = min(frame.width/2, frame.height/2);
        
        let path = NSBezierPath(roundedRect: dirtyRect, xRadius: radius, yRadius: radius);
        path.addClip();

        if mouseDown {
            NSColor.unemphasizedSelectedContentBackgroundColor.setFill();
        } else {
            NSColor.textBackgroundColor.setFill();
        }
        path.fill();

        path.lineWidth = 1;
        
        let tintColor =  NSApp.isDarkMode ? NSColor.lightGray : NSColor.darkGray;
        tintColor.setStroke();
        path.stroke();
        
        NSGraphicsContext.restoreGraphicsState();

        let marginHeight = dirtyRect.height / 5.0;
        let marginWidth = dirtyRect.height / 4.0;
        let imageWidth = dirtyRect.height - (2 * marginHeight);
        let imageFrame = NSRect(x: dirtyRect.width - (imageWidth + marginWidth), y: marginHeight, width: imageWidth, height: dirtyRect.height - (2 * marginHeight));
        if let image: NSImage = (self.cell as? NSButtonCell)?.image?.copy() as? NSImage {
            image.lockFocus();
            tintColor.set();
            NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop);
            image.unlockFocus();
            image.isTemplate = false;
            (self.cell as? NSButtonCell)?.drawImage(image, withFrame: imageFrame, in: self);
        }
    
        let textFrame = NSRect(x: marginWidth, y: marginHeight, width: dirtyRect.width - (imageWidth + marginWidth * 2), height: dirtyRect.height - (2 * marginHeight));
        let paragraph = NSMutableParagraphStyle();
        paragraph.alignment = .center;
        (self.cell as? NSButtonCell)?.drawTitle(NSAttributedString(string: self.title, attributes: [NSAttributedString.Key.paragraphStyle: paragraph]), withFrame: textFrame, in: self);

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
