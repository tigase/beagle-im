//
// RoundButton.swift
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

@IBDesignable
public class RoundButton: NSButton {
    
    @IBInspectable
    var backgroundColor: NSColor = NSColor.textBackgroundColor;
    
    public override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState();
        
        let path = NSBezierPath(roundedRect: dirtyRect, xRadius: frame.width/2, yRadius: frame.width/2);
        path.addClip();

        backgroundColor.setFill();
        path.fill();

        NSGraphicsContext.restoreGraphicsState();

        let margin = max(dirtyRect.width, dirtyRect.height) / 5;
        let imageFrame = NSRect(x: margin, y: margin, width: dirtyRect.width - (2 * margin), height: dirtyRect.height - (2 * margin));
        (self.cell as? NSButtonCell)?.drawImage(self.cell!.image!, withFrame: imageFrame, in: self);
        
    }
    
}
