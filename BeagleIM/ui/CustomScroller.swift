//
// CustomScroller.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class CustomScroller: NSScroller {
    
    @IBInspectable
    var backgroudColor: NSColor = NSColor.controlBackgroundColor;

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        commonInit();
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder);
        commonInit();
    }

    override func awakeFromNib() {
        super.awakeFromNib();
        commonInit();
    }

    private func commonInit() {
    }
    
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {
        NSGraphicsContext.saveGraphicsState();
        self.backgroudColor.setFill();
        self.bounds.fill();
        let color = backgroudColor.blended(withFraction: 0.1, of: NSColor.white)!
        color.setFill();
        let rect = NSRect(x: self.bounds.origin.x + 1, y: self.bounds.origin.y, width: self.bounds.width - 1, height: self.bounds.height);
        rect.fill();
        NSGraphicsContext.restoreGraphicsState();
    }
    
    override class var isCompatibleWithOverlayScrollers: Bool {
        return true;
    }

}
