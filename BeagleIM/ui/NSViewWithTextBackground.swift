//
// NSViewWithTextBackground.swift
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

class NSViewWithTextBackground: NSView {
    
    @IBInspectable
    public var backgroundColor: NSColor = NSColor(named: "chatBackgroundColor")!;
    
    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
    }
    
    public required init?(coder decoder: NSCoder) {
        super.init(coder: decoder);
    }
        
    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill();
        dirtyRect.fill();
        super.draw(dirtyRect);
    }
    
}
