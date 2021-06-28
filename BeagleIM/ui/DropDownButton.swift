//
// DropDownButton.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see https://www.gnu.org/licenses/.
//

import AppKit

class DropDownButton: NSButton {

    private var popUpCell: NSPopUpButtonCell?;
    
    override var menu: NSMenu? {
        didSet {
            if self.menu != nil {
                popUpCell = NSPopUpButtonCell();
                popUpCell?.pullsDown = true;
                popUpCell?.preferredEdge = .minY;
            } else {
                popUpCell = nil;
            }
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else {
            return;
        }
        if let popUpMenu = self.menu?.copy() as? NSMenu, let popUpCell = self.popUpCell {
            popUpMenu.insertItem(withTitle: "", action: nil, keyEquivalent: "", at: 0);
            popUpCell.menu = popUpMenu;
            popUpCell.target = self.target;
            popUpCell.performClick(withFrame: self.bounds, in: self);
            self.needsDisplay = true;
        } else {
            super.mouseDown(with: event);
        }
    }
 
    func item(at idx: Int) -> NSMenuItem? {
        return menu?.items[idx];
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect);
    }
    
}
