//
//  ChatCellViewMessage.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 01.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class ChatCellViewMessage: NSTextField {
    
    var blured: Bool = false {
        didSet {
            needsDisplay = true;
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect);
        
        let isHighlighted = (self.superview?.superview as? NSTableRowView)?.isSelected ?? false;
        
        if blured && !isHighlighted {
            
            let startingColor = isHighlighted ? NSColor(calibratedWhite: 0.82, alpha: 0.15) : NSColor.selectedKnobColor.withAlphaComponent(0.0);
            let endingColor = isHighlighted ? NSColor(calibratedWhite: 0.82, alpha: 0.15) : NSColor.selectedKnobColor.withAlphaComponent(1.0);
            let gradient = NSGradient(starting: startingColor, ending: endingColor);
        
            let rect = NSRect(x: dirtyRect.origin.x + dirtyRect.width/2, y: dirtyRect.origin.y, width: dirtyRect.width/2, height: dirtyRect.height);
            gradient!.draw(in: rect, angle: 0.0);
        }
    }
    
}
