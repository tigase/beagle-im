//
// NSImage.swift
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

extension NSImage {
    
    func rounded() -> NSImage {
        return rounded(radius: min(size.width, size.height)/2);
    }
    
    func rounded(radius: CGFloat) -> NSImage {
        guard let cgImage = self.cgImage, let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 4 * Int(size.width), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue) else {
            return self;
        }
        
        let rect = NSRect(origin: .zero, size: size);
        
        context.beginPath();
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil));
        context.closePath();
        context.clip();
        context.draw(cgImage, in: rect);
        
        guard let composedImage = context.makeImage() else {
            return self;
        }
        
        return NSImage(cgImage: composedImage, size: size);
    }

    func scaled(to size: NSSize, format: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey:Any] = [:]) -> Data? {
//        guard let cgImage = self.cgImage else {
//            return nil;
//        }
//        let newRep = NSBitmapImageRep(cgImage: cgImage);
//        newRep.size = size;
//        return newRep.representation(using: format, properties: properties);
        let small = NSImage(size: size);
        small.lockFocus();
        NSGraphicsContext.current?.imageInterpolation = .high;
        
        let transform = NSAffineTransform();
        transform.scaleX(by: size.width/self.size.width, yBy: size.height/self.size.height);
        transform.concat();
        draw(at: .zero, from: NSRect(origin: .zero, size: self.size), operation: .sourceOver, fraction: 1.0);
        small.unlockFocus();
        guard let cgImage = small.cgImage else {
            return nil;
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: format, properties: properties);
    }
    
    func scaled(maxWidthOrHeight: CGFloat, format: NSBitmapImageRep.FileType, properties: [NSBitmapImageRep.PropertyKey: Any] = [:]) -> Data? {
        let maxDimmension = max(self.size.height, self.size.width);
        let scale = maxDimmension / maxWidthOrHeight;
        let expSize = NSSize(width: self.size.width / scale, height: self.size.height / scale);
        return scaled(to: expSize, format: format);
    }
    
    func scaledToPng(to size: NSSize) -> Data? {
        return scaled(to: size, format: .png);
    }

    func scaledToPng(to maxWidthOrHeight: CGFloat) -> Data? {
        return scaled(maxWidthOrHeight: maxWidthOrHeight, format: .png);
    }
    
    func scaledAndFlipped(maxWidth: CGFloat, maxHeight: CGFloat, flipX: Bool, flipY: Bool, roundedRadius radius: CGFloat = 0.0) -> NSImage {
        var scale: CGFloat = 1.0;
        if self.size.width > self.size.height {
            scale = max(self.size.width / maxWidth, 1.0);
        } else {
            scale = max(self.size.height / maxHeight, 1.0);
        }
//        let maxDimmension = max(self.size.height, self.size.width);
//        let scale = max(maxDimmension / maxWidthOrHeight, 1.0);
        //let expSize = NSSize(width: size.width, height: size.height);//NSSize(width: self.size.width / scale, height: self.size.height / scale);
        
        let expSize = self.size.height > self.size.width ? NSSize(width: self.size.width / scale, height: self.size.height / scale) : NSSize(width: self.size.width / scale, height: self.size.height / scale);
        
//        print("expected size:", expSize);
        let flipped = NSImage(size: expSize);
        flipped.lockFocus();
        NSGraphicsContext.current?.imageInterpolation = .high;

        let transform = NSAffineTransform();
        transform.translateX(by: 0.0, yBy: flipY ? expSize.height : 0);
//        transform.translateX(by: expSize.width, yBy: expSize.height);
        //transform.scaleX(by: (flipX ? -1.0 : 1.0)/scale, yBy: (flipY ? -1.0 : 1.0)/scale);
        //transform.scaleX(by: flipX ? -1.0 : 1.0, yBy: flipY ? -1.0 : 1.0);
        transform.scaleX(by: (flipX ? -1.0 : 1.0) / scale, yBy: (flipY ? -1.0 : 1.0) / scale);
        transform.concat();
        
        let rect = NSRect(origin: .zero, size: size);
        if radius > 0.0, let context = NSGraphicsContext.current?.cgContext {
            context.beginPath();
            context.addPath(CGPath(roundedRect: rect, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil));
            context.closePath();
            context.clip();
        }
        draw(at: .zero, from: rect, operation: .sourceOver, fraction: 1.0);
        flipped.unlockFocus();
        return flipped;
    }
    
    func tinted(with tintColor: NSColor) -> NSImage {
        guard let cgImage = self.cgImage else {
            return self;
        }
        
        return NSImage(size: size, flipped: false, drawingHandler: { bounds in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            tintColor.set()
            context.clip(to: bounds, mask: cgImage)
            context.fill(bounds)
            return true;
        })
    }
    
}

fileprivate extension NSImage {

    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size);
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil);
    }
    
}
