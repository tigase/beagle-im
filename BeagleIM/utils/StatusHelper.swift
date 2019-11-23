//
// StatusHelper.swift
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
import TigaseSwift

class StatusHelper {
    
    public static let blockedImage: NSImage = {
        let bgImage = NSImage(named: NSImage.statusUnavailableName)!;
        var rect = CGRect(origin: .zero, size: bgImage.size);
        let bgCgImage = bgImage.cgImage(forProposedRect: &rect, context: nil, hints: nil)!;

        return NSImage(size: bgImage.size, flipped: false, drawingHandler: { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            
            context.draw(bgCgImage, in: bounds);
            
            let w = bounds.width/2;
            let h = bounds.height/2;
            let eclipse2 = NSBezierPath.init(roundedRect: NSRect(x: w/2, y: h/2, width: w, height: h), xRadius: w/2, yRadius: h/2);
            eclipse2.setClip();
            
            NSImage(named: NSImage.stopProgressTemplateName)!.tinted(with: NSColor.white).draw(in: bounds);
            
            return true;
        })
    }();
    
    public static func imageFor(status: Presence.Show?) -> NSImage {
        return NSImage(named: StatusHelper.imageNameFor(status: status))!;
    }
    
    fileprivate static func imageNameFor(status: Presence.Show?) -> NSImage.Name {
        if status == nil {
            return NSImage.statusNoneName;
        } else {
            switch status! {
            case .online, .chat:
                return NSImage.statusAvailableName;
            case .away, .xa:
                return NSImage.statusPartiallyAvailableName;
            case .dnd:
                return NSImage.statusUnavailableName;
            }
        }
    }
    
}
