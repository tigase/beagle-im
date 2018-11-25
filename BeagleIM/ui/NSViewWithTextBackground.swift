//
//  NSViewWithTextBackground.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 25/11/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
