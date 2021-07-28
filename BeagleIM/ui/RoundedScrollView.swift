//
// RoundedScrollView.swift
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

class RoundedScrollView: NSScrollView {
    
    var cornerRadius: CGFloat = 11 {
        didSet {
            self.contentView.layer?.cornerRadius = cornerRadius;
        }
    }
    var borderWidth: CGFloat = 1;
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        setup();
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        setup();
    }
    
    func setup() {
        self.contentView.wantsLayer = true;
        self.contentView.layer?.masksToBounds = true;
        self.contentView.layer?.borderWidth = borderWidth;
        self.contentView.layer?.borderColor = NSColor.lightGray.cgColor;
        self.contentView.layer?.cornerRadius = cornerRadius;
        self.contentView.layer?.maskedCorners = [.layerMaxXMaxYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMinXMinYCorner];
    }
    
}
