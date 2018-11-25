//
//  OutlineGroupItemButton.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 30.08.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class OutlineGroupItemButton: NSButton {
    
    var group: ChatsListGroupProtocol?;
    
    override func draw(_ dirtyRect: NSRect) {
        if NSApp.isDarkMode {
            self.contentFilters.removeAll();
        } else if self.contentFilters.isEmpty {
            let filter = CIFilter(name: "CIColorInvert")!;
            filter.setDefaults();
            self.contentFilters.append(filter);
        }
        super.draw(dirtyRect);
    }
}
