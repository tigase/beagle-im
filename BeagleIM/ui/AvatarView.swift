//
// AvatarView.swift
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
