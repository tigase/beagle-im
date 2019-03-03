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

    var name: String? = nil {
        didSet {
            if let parts = name?.uppercased().components(separatedBy: CharacterSet.letters.inverted) {
                let first = parts.first?.first;
                let last = parts.count > 1 ? parts.last?.first : nil;
                self.initials = last == nil ? (first == nil ? nil : "\(first!)") : "\(first!)\(last!)";
            } else {
                self.initials = nil;
            }
            self.needsDisplay =  true;
        }
    }
    fileprivate var initials: String?;
    
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
        } else if let text = self.initials {
            let isDark = (self.appearance ?? NSAppearance.current)!.bestMatch(from: [.aqua, .darkAqua]) != .aqua;
            (isDark ? NSColor.white : NSColor.darkGray).withAlphaComponent(0.3).setFill();
            path.fill();
            
            let font = NSFont.systemFont(ofSize: dirtyRect.width * 0.4, weight: .medium);
            let textAttr: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white.withAlphaComponent(0.9), .font: font];

            let textSize = text.size(withAttributes: textAttr)
            
            text.draw(in: CGRect(x: dirtyRect.midX - textSize.width/2, y: dirtyRect.midY - textSize.height/2, width: textSize.width, height: textSize.height), withAttributes: textAttr);
        } else {
            let image = NSImage(named: NSImage.userGuestName)!;
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
