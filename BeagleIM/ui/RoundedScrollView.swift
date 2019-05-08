//
// RoundedScrollView.swift
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

class RoundedScrollView: NSScrollView {
    
    var cornerRadius: CGFloat = 11;
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect);
        
        let context = NSGraphicsContext.current!;
        context.saveGraphicsState();
        
        if NSApp.isDarkMode {
            NSColor.darkGray.setStroke();
        } else {
            NSColor.lightGray.setStroke();
        }
        NSColor(named: "chatBackgroundColor")!.setFill();
        let rect = NSRect(x: dirtyRect.origin.x + 1, y: dirtyRect.origin.y + 1, width: dirtyRect.width - 2, height: dirtyRect.height - 2);
        let ellipse = NSBezierPath.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius);
        ellipse.lineWidth = 1;
        ellipse.stroke();
        ellipse.fill();
        ellipse.setClip();
        
        context.restoreGraphicsState();
    }
    
}
