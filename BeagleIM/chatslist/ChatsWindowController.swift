//
//  ChatsWindowController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 26.08.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class ChatsWindowController: NSWindowController, NSWindowDelegate {
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
    }
    
    override func windowDidLoad() {
        super.windowDidLoad();
        self.window?.titleVisibility = .hidden;
    }
    
//    func windowShouldClose(_ sender: NSWindow) -> Bool {
////        sender.orderOut(nil);
//        sender.setIsMiniaturized(true);
//        return false;
//    }
    
}
