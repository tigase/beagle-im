//
//  ChatCellViewMessage.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 01.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class ChatCellViewMessage: NSTextField {
    
    fileprivate var dotLayers = [CAShapeLayer]();
    fileprivate var dotsRadius: CGFloat = 4;
    
    var blured: Bool = false {
        didSet {
            needsDisplay = true;
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        self.wantsLayer = true;
//        setupLayers();
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        self.wantsLayer = true;
//        setupLayers();
    }
    
    fileprivate func setupLayers() {
        for _ in 0..<3 {
            let layer = CAShapeLayer();
            layer.bounds = CGRect(origin: .zero, size: CGSize(width: 2 * dotsRadius, height: 2 * dotsRadius));
            layer.path = CGPath(roundedRect: layer.bounds, cornerWidth: dotsRadius, cornerHeight: dotsRadius, transform: nil);
            layer.fillColor = NSColor.lightGray.cgColor;
            dotLayers.append(layer);
            self.layer?.addSublayer(layer);
        }
        for (idx, layer) in dotLayers.enumerated() {
            let x = 2*dotsRadius + 1 + (CGFloat(idx) * (2 * dotsRadius + 1));
            layer.position = CGPoint(x: x, y: frame.size.height / 2.0);
        }
    }
    
    fileprivate func teardownLayers() {
        dotLayers.forEach { (layer) in
            layer.removeFromSuperlayer();
        }
        dotLayers.removeAll();
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect);
        
        let isHighlighted = (self.superview?.superview as? NSTableRowView)?.isSelected ?? false;
        
        if blured && !isHighlighted {
            
            let startingColor = isHighlighted ? NSColor(calibratedWhite: 0.82, alpha: 0.15) : NSColor.selectedKnobColor.withAlphaComponent(0.0);
            let endingColor = isHighlighted ? NSColor(calibratedWhite: 0.82, alpha: 0.15) : NSColor.selectedKnobColor.withAlphaComponent(1.0);
            let gradient = NSGradient(starting: startingColor, ending: endingColor);
        
            let rect = NSRect(x: dirtyRect.origin.x + dirtyRect.width/2, y: dirtyRect.origin.y, width: dirtyRect.width/2, height: dirtyRect.height);
            gradient!.draw(in: rect, angle: 0.0);
        }
    }
    
    override func layout() {
        super.layout();
        for (idx, layer) in dotLayers.enumerated() {
            let x = 2*dotsRadius + 1 + (CGFloat(idx) * (2 * dotsRadius + 1));
            layer.position = CGPoint(x: x, y: frame.size.height / 2.0);
        }
    }

    func startAnimating() {
        var offset: TimeInterval = 0.0;
        setupLayers();
        dotLayers.forEach { (layer) in
            layer.removeAllAnimations();
            layer.add(scaleAnimation(offset), forKey: "aj.dotLoading.scaleAnima");
            offset = offset + 0.25;
        }
    }
    
    func stopAnimating() {
        dotLayers.forEach { (layer) in
            layer.removeAllAnimations();
        }
        teardownLayers();
    }
    
    private func scaleAnimation(_ after: TimeInterval = 0) -> CAAnimationGroup {
        let scaleUp = CABasicAnimation(keyPath: "transform.scale")
        scaleUp.beginTime = after
        scaleUp.fromValue = 1
        scaleUp.toValue = 1.3;
        scaleUp.duration = 0.3
        scaleUp.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        
        let scaleDown = CABasicAnimation(keyPath: "transform.scale")
        scaleDown.beginTime = after+scaleUp.duration
        scaleDown.fromValue = 1.3;
        scaleDown.toValue = 1.0
        scaleDown.duration = 0.2
        scaleDown.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeOut)
        
        let group = CAAnimationGroup()
        group.animations = [scaleUp, scaleDown]
        group.repeatCount = Float.infinity
        
        let sum = CGFloat(3)*0.2 + CGFloat(0.4)
        group.duration = CFTimeInterval(sum)
        
        return group
    }
}
