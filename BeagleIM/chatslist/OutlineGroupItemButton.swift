//
// OutlineGroupItemButton.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
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
