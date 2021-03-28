//
// AvatarViewWithStatus.swift
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
import Combine

class AvatarViewWithStatus: NSView {

    fileprivate(set) var avatarView: AvatarView!;
    private(set) var statusView: StatusView!;
    
    var name: String? {
        get {
            return avatarView.name;
        }
        set {
            avatarView.name = newValue;
        }
    }
    var avatar: NSImage? {
        get {
            return avatarView.avatar;
        }
        set {
            self.avatarView.avatar = newValue;
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    var displayableId: DisplayableIdProtocol? {
        didSet {
            cancellables.removeAll();
            if let namePublisher = displayableId?.displayNamePublisher, let avatarPublisher = displayableId?.avatarPublisher {
                namePublisher.combineLatest(avatarPublisher).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] name, image in
                    self?.avatarView.set(name: name, avatar: image);
                }).store(in: &cancellables);
            }
            displayableId?.statusPublisher.assign(to: \.status, on: statusView).store(in: &cancellables);
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
            guard backgroundColor != statusView.backgroundColor else {
                return;
            }
            statusView.backgroundColor = backgroundColor;
            statusView.needsDisplay = true;
        }
    }
    
    var status: Presence.Show? {
        get {
            return statusView.status;
        }
        
        set {
            statusView.status = newValue;
        }
    }
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        initSubviews();
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        initSubviews();
    }
    
    fileprivate func initSubviews() {
        //self.wantsLayer = true;
        self.avatarView = AvatarView(frame: self.frame);
        self.avatarView.translatesAutoresizingMaskIntoConstraints = false;
        self.avatarView.imageScaling = .scaleProportionallyUpOrDown;
        addSubview(avatarView);

        self.statusView = StatusView(frame: self.frame);
        self.statusView.translatesAutoresizingMaskIntoConstraints = false;
        addSubview(statusView, positioned: NSWindow.OrderingMode.above, relativeTo: self.avatarView);

        NSLayoutConstraint.activate([
        NSLayoutConstraint(item: self.avatarView!, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.avatarView!, attribute: .left, relatedBy: .equal, toItem: self, attribute: .left, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.avatarView!, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.avatarView!, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.avatarView!, attribute: .width, relatedBy: .equal, toItem: self, attribute: .width, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.avatarView!, attribute: .height, relatedBy: .equal, toItem: self, attribute: .height, multiplier: 1, constant: 0),
            NSLayoutConstraint(item: self.statusView!, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.statusView!, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1, constant: 0),
        NSLayoutConstraint(item: self.statusView!, attribute: .width, relatedBy: .equal, toItem: self, attribute: .width, multiplier: 0.30, constant: 0),
        NSLayoutConstraint(item: self.statusView!, attribute: .height, relatedBy: .equal, toItem: self, attribute: .height, multiplier: 0.30, constant: 0)]);
        
        statusView.image = NSImage(named: NSImage.statusAvailableName);
        statusView.imageScaling = .scaleProportionallyUpOrDown;
    }
    
    class StatusView: NSImageView {
        
        var backgroundColor: NSColor?;
        var blocked: Bool = false {
            didSet {
                updateImage();
            }
        }
        var status: Presence.Show? = nil {
            didSet {
                updateImage();
            }
        }
        
        func updateImage() {
            if blocked {
                self.image = StatusHelper.blockedImage;
            } else {
                self.image = StatusHelper.imageFor(status: status);
            }
        }
        
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect);
            updateImage();
        }
        
        required init?(coder: NSCoder) {
            super.init(coder: coder);
            updateImage();
        }
        
        override func draw(_ dirtyRect: NSRect) {
            if backgroundColor != nil {
                backgroundColor!.setFill();
                let ellipse = NSBezierPath.init(roundedRect: dirtyRect, xRadius: dirtyRect.width/2, yRadius: dirtyRect.height/2);
                ellipse.fill();
                ellipse.setClip();
                
                super.draw(dirtyRect);
                
            } else {
                super.draw(dirtyRect);
            }
        }
                
    }
}
