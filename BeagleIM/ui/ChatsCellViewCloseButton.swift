//
// ChatsCellViewCloseButton.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
