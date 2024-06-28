//
// AvatarView.swift
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
import Combine

class AvatarView: NSImageView {

    static let defaultImage: NSImage = NSImage(named: NSImage.userGuestName)!;
    
    override var frame: NSRect {
        didSet {
            updateImage();
        }
    }
    
    var name: String? = nil {
        didSet {
            if let parts = name?.uppercased().components(separatedBy: CharacterSet.letters.inverted) {
                let first = parts.first?.first;
                let last = parts.count > 1 ? parts.last?.first : nil;
                self.initials = (last == nil || first == nil) ? (first == nil ? nil : "\(first!)") : "\(first!)\(last!)";
            } else {
                self.initials = nil;
            }
            updateImage();
        }
    }
    
    var avatar: NSImage? {
        didSet {
            updateImage();
        }
    }
    
    private var initials: String? {
        didSet {
            if initials != oldValue {
                self.needsDisplay = true;
            }
        }
    }
    
    private func updateImage() {
        if avatar != nil {
            // workaround to properly handle appearance
            if self.avatar! == AvatarManager.instance.defaultGroupchatAvatar {
                self.image = self.avatar;
            } else {
                self.image = self.frame.size.width == 0 ? avatar : avatar?.square(max(self.frame.size.width, self.frame.size.height));
            }
        } else if initials != nil {
            self.image = nil;
        } else {
            self.image = AvatarView.defaultImage;
        }
    }
    
    override func awakeFromNib() {
        self.imageScaling = .scaleProportionallyUpOrDown;
        self.updateImage();
    }
    
    func set(name: String?, avatar: NSImage?) {
        self.name = name;
        self.avatar = avatar;
        self.needsDisplay = true;
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: self.bounds, xRadius: frame.width/2, yRadius: frame.width/2);
        path.addClip();

        if self.image != nil {
            super.draw(dirtyRect);
        } else if let text = self.initials {
            let isDark = (self.appearance ?? NSAppearance.current)!.bestMatch(from: [.aqua, .darkAqua]) != .aqua;
            (isDark ? NSColor.white : NSColor.darkGray).withAlphaComponent(0.3).setFill();
            path.fill();

            let font = NSFont.systemFont(ofSize: frame.width * 0.4, weight: .medium);
            let textAttr: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white.withAlphaComponent(0.9), .font: font];

            let textSize = text.size(withAttributes: textAttr)

            text.draw(in: CGRect(x: bounds.midX - textSize.width/2, y: bounds.midY - textSize.height/2, width: textSize.width, height: textSize.height), withAttributes: textAttr);
        }
    }
    
}
