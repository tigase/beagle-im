//
//  RoundedScrollView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 02/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
        
        NSColor.lightGray.setStroke();
        NSColor.textBackgroundColor.setFill();
        let rect = NSRect(x: dirtyRect.origin.x + 1, y: dirtyRect.origin.y + 1, width: dirtyRect.width - 2, height: dirtyRect.height - 2);
        let ellipse = NSBezierPath.init(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius);
        ellipse.lineWidth = 1;
        ellipse.stroke();
        ellipse.fill();
        ellipse.setClip();
        
        context.restoreGraphicsState();
    }
    
}
