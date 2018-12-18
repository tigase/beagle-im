//
//  RoundButton.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 18/12/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
