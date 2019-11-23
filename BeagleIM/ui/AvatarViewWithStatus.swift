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

class AvatarViewWithStatus: NSView {

    fileprivate(set) var avatarView: AvatarView!;
    fileprivate var statusView: StatusView!;
    
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
            return avatarView.image;
        }
        set {
//            let oldValue = avatarView.image;
//            if newValue == nil || oldValue == nil || ((oldValue!) != (newValue!)) {
//                NSAnimationContext.runAnimationGroup({ (_) in
//                    NSAnimationContext.current.duration = 0.2;
//                    self.avatarView.animator().alphaValue = 0;
//                }, completionHandler: {() in
//                    self.avatarView.image = newValue;
//                    NSAnimationContext.runAnimationGroup({ (_) in
//                        NSAnimationContext.current.duration = 0.2;
//                        self.avatarView.animator().alphaValue = 1.0;
//                    }, completionHandler: nil);
//                });
//                statusView.needsDisplay = true;
//            }
            self.avatarView.image = newValue;
            statusView.needsDisplay = true;
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
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
    
    func update(for jid: BareJID, on account: BareJID, orDefault: NSImage? = nil) {
        self.avatar = AvatarManager.instance.avatar(for: jid, on: account) ?? orDefault;
        if jid == account {
            if let status = XmppService.instance.getClient(for: account)?.state {
                switch status {
                case .connected:
                    self.status = .online;
                case .connecting:
                    self.status = .away;
                default:
                    self.status = .none;
                }
            } else {
                self.status = .none;
            }
        } else {
            let client = XmppService.instance.getClient(for: account);
            let presenceModule: PresenceModule? = client?.modulesManager.getModule(PresenceModule.ID);
            self.statusView.blocked = client != nil && BlockedEventHandler.isBlocked(JID(jid), on: client!);
            self.status = presenceModule?.presenceStore.getBestPresence(for: jid)?.show;
        }
    }
    
    fileprivate func initSubviews() {
        self.wantsLayer = true;
        self.avatarView = AvatarView(frame: self.frame);
        self.avatarView.translatesAutoresizingMaskIntoConstraints = false;
        self.avatarView.imageScaling = .scaleProportionallyUpOrDown;
        addSubview(avatarView);
        
        NSLayoutConstraint(item: self.avatarView!, attribute: .top, relatedBy: .equal, toItem: self, attribute: .top, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.avatarView!, attribute: .left, relatedBy: .equal, toItem: self, attribute: .left, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.avatarView!, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.avatarView!, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.avatarView!, attribute: .width, relatedBy: .equal, toItem: self, attribute: .width, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.avatarView!, attribute: .height, relatedBy: .equal, toItem: self, attribute: .height, multiplier: 1, constant: 0).isActive = true;

        self.statusView = StatusView(frame: self.frame);
        self.statusView.translatesAutoresizingMaskIntoConstraints = false;
        addSubview(statusView, positioned: NSWindow.OrderingMode.above, relativeTo: self.avatarView);
        NSLayoutConstraint(item: self.statusView!, attribute: .bottom, relatedBy: .equal, toItem: self, attribute: .bottom, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.statusView!, attribute: .right, relatedBy: .equal, toItem: self, attribute: .right, multiplier: 1, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.statusView!, attribute: .width, relatedBy: .equal, toItem: self, attribute: .width, multiplier: 0.30, constant: 0).isActive = true;
        NSLayoutConstraint(item: self.statusView!, attribute: .height, relatedBy: .equal, toItem: self, attribute: .height, multiplier: 0.30, constant: 0).isActive = true;
        
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
                let context = NSGraphicsContext.current!;
                context.saveGraphicsState();
            
                backgroundColor!.setFill();
                let ellipse = NSBezierPath.init(roundedRect: dirtyRect, xRadius: dirtyRect.width/2, yRadius: dirtyRect.height/2);
                ellipse.fill();
                ellipse.setClip();
                
                super.draw(dirtyRect);
                
                context.restoreGraphicsState();
            } else {
                super.draw(dirtyRect);
            }
        }
                
    }
}
