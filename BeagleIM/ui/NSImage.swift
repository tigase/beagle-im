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
import Intents

extension NSImage {
    
    func decoded() -> NSImage {
        guard let cgImage = self.cgImage else {
            return self;
        }
        
        let size = CGSize(width: cgImage.width, height: cgImage.height);
        let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: cgImage.bytesPerRow, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue);
        
        context?.draw(cgImage, in: .init(origin: .zero, size: size));
        
        guard let image = context?.makeImage() else {
            return self;
        }
        
        return NSImage(cgImage: image, size: size);
    }
    
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

    func scaled(to size: NSSize) -> NSImage {
        let small = NSImage(size: size);
        small.lockFocus();
        NSGraphicsContext.current?.imageInterpolation = .high;
        
        let transform = NSAffineTransform();
        transform.scaleX(by: size.width/self.size.width, yBy: size.height/self.size.height);
        transform.concat();
        draw(at: .zero, from: NSRect(origin: .zero, size: self.size), operation: .sourceOver, fraction: 1.0);
        small.unlockFocus();
        return small;
    }
    
    func scaled(maxWidthOrHeight: CGFloat) -> NSImage {
        guard maxWidthOrHeight < size.height || maxWidthOrHeight < size.width else {
            return self;
        }
        let maxDimmension = max(self.size.height, self.size.width);
        let scale = maxDimmension / maxWidthOrHeight;
        let expSize = NSSize(width: self.size.width / scale, height: self.size.height / scale);
        return scaled(to: expSize);
    }
    
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let cgImage = self.cgImage else {
            return nil;
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]);
    }
    
    func pngData() -> Data? {
        guard let cgImage = self.cgImage else {
            return nil;
        }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:]);
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
    
    func square(_ size: CGFloat) -> NSImage {
        let width = self.size.width;
        let height = self.size.height;
        
        let dest = NSImage(size: NSSize(width: size, height: size));
        dest.lockFocus();
    
//        let sourceRect = width > height ? NSRect(x: (width - height) / 2, y: 0, width: height, height: height) : NSRect(x: 0, y: (height - width) / 2, width: width, height: height);
   
        NSGraphicsContext.current?.imageInterpolation = .high;
        
//        let transform = NSAffineTransform();
//        transform.translateX(by: 0.0, yBy: 0);
//        transform.scaleX(by: size / sourceRect.width, yBy: size / sourceRect.height);
//        transform.concat();
//
//        draw(at: .zero, from: sourceRect, operation: .sourceOver, fraction: 1.0);
        let widthDiff = max(width - height, 0) / 2;
        let heightDiff = max(height - width, 0) / 2;
        draw(in: NSRect(origin: .zero, size: dest.size), from: NSRect(x: widthDiff, y: heightDiff, width: width - (widthDiff * 2), height: height - (heightDiff * 2)), operation: .sourceOver, fraction: 1.0);
        
        dest.unlockFocus();
        return dest;
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
    
    @available(macOS 11.0, *)
    public func inImage() -> INImage? {
        guard let data = self.jpegData(compressionQuality: 0.7) else {
            return nil;
        }
        return INImage(imageData: data);
    }
}

fileprivate extension NSImage {

    var cgImage: CGImage? {
        var rect = CGRect(origin: .zero, size: self.size);
        return self.cgImage(forProposedRect: &rect, context: nil, hints: nil);
    }
    
}
