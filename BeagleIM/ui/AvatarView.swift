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
        
        if let image = self.image {
            let size = image.size;
            let widthDiff = max(size.width - size.height, 0) / 2;
            let heightDiff = max(size.height - size.width, 0) / 2;
            let width = size.width - (2 * widthDiff);
            let height = size.height - (2 * heightDiff);
            image.draw(in: dirtyRect, from: NSRect(x: widthDiff, y: heightDiff, width: width, height: height), operation: .sourceOver, fraction: 1.0);
        }
        
        NSGraphicsContext.restoreGraphicsState();
    }
    
}
