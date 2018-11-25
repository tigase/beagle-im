//
//  ChatsListTableRowView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 08.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
            let selectionRect = dirtyRect;//NSInsetRect(self.bounds, 2.5, 2.5)
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
