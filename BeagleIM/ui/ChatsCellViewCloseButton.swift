//
//  ChatsCellViewCloseButton.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 01.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class ChatsCellViewCloseButton: NSButton {
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        self.cell?.backgroundStyle = .dark;
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        
        self.cell?.backgroundStyle = .dark;
    }

    override func draw(_ dirtyRect: NSRect) {
        self.cell?.backgroundStyle = .dark;
        super.draw(dirtyRect);
    }
    
}
