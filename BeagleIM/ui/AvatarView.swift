//
//  AvatarView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 26.08.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class AvatarView: NSImageView {
        
    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState();
        
        let path = NSBezierPath(roundedRect: dirtyRect, xRadius: frame.width/2, yRadius: frame.width/2);
        path.addClip();
        
        image?.draw(in: dirtyRect, from: .zero, operation: .sourceOver, fraction: 1.0);
        
        NSGraphicsContext.restoreGraphicsState();
    }
    
}
