//
//  ChatsListTableRowView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 08.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class ChatsListTableRowView: NSTableRowView {
    
    fileprivate var highlightColor: NSColor = NSColor.selectedKnobColor;
    
    override var isSelected: Bool {
        didSet {
            self.highlightColor = isSelected ? NSColor.selectedKnobColor.blended(withFraction: 0.15, of: NSColor(calibratedWhite: 0.82, alpha: 1.0))! : NSColor.selectedKnobColor;
            if let subview = self.subviews.last as? ChatCellView {
               subview.avatar.backgroundColor = highlightColor;
            }
        }
    }
    
    override func drawSelection(in dirtyRect: NSRect) {
        if self.selectionHighlightStyle != .none {
            let selectionRect = dirtyRect;//NSInsetRect(self.bounds, 2.5, 2.5)
            NSColor(calibratedWhite: 0.65, alpha: 0.15).setStroke();
            highlightColor.setFill();
            let selectionPath = NSBezierPath(roundedRect: selectionRect, xRadius: 6, yRadius: 6);
            selectionPath.fill();
            selectionPath.stroke();
        }
    }
    
    override func layout() {
        if let subview = self.subviews.last as? ChatCellView {
            //                self.setFrameSize(NSSize(width: self.frame.width, height: 40));
            super.layout();
            let height = subview.lastMessage.intrinsicContentSize.height + subview.label.frame.height + 4 + 2 + 2;
            self.setFrameSize(NSSize(width: self.frame.width, height: height < 44 ? 44 : height));
        } else {
            super.layout();
        }
    }
 
}
