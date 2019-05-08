//
// ChatsListTableRowView.swift
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

class ChatsListTableRowView: NSTableRowView {
    
    fileprivate var highlightColor: NSColor = NSColor(named: "sidebarBackgroundColor")!;
    
    override var isSelected: Bool {
        didSet {
            self.highlightColor = isSelected ? NSColor(named: "sidebarBackgroundColor")!.blended(withFraction: 0.15, of: NSColor(calibratedWhite: 0.82, alpha: 1.0))! : NSColor(named: "sidebarBackgroundColor")!;
            if let subview = self.subviews.last as? ChatCellView {
               subview.avatar.backgroundColor = highlightColor;
            }
        }
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        highlightColor = (isSelected ? NSColor(named: "sidebarBackgroundColor")!.blended(withFraction: 0.15, of: NSColor(calibratedWhite: 0.82, alpha: 1.0))! : NSColor(named: "sidebarBackgroundColor")!);
        if self.selectionHighlightStyle != .none {
            //let selectionRect = dirtyRect;//NSInsetRect(self.bounds, 2.5, 2.5)
            NSColor(calibratedWhite: 0.65, alpha: 0.15).setStroke();
            highlightColor.setFill();
            dirtyRect.fill();
//            dirtyRect.stroke();
//            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6);
//            selectionPath.fill();
//            selectionPath.stroke();
        }
        if let subview = self.subviews.last as? ChatCellView {
            subview.avatar.backgroundColor = highlightColor;
        }
    }
    
    override func layout() {
//        let color = highlightColor.usingColorSpaceName(.deviceRGB)!;
//        print("color:", String(format: "#%02X%02X%02X", Int(color.redComponent * 0xFF), Int(color.greenComponent * 0xFF), Int(color.blueComponent * 0xFF)));
        self.isGroupRowStyle = false;
        super.layout();
        self.invalidateIntrinsicContentSize();
        super.layout();
    }
 
}
