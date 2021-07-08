//
// MeetController.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift
import TigaseLogging
import WebRTC
import MetalKit

class MeetController: NSViewController, NSCollectionViewDataSource, CallDelegate, RTCVideoViewDelegate {
    func callDidStart(_ sender: Call) {
        // nothing to do..
    }
    
    func callDidEnd(_ sender: Call) {
        DispatchQueue.main.async {
            guard let window = self.view.window else {
                return;
            }

            let alert = NSAlert();
            alert.messageText = "Meeting ended";
            alert.informativeText = "Meeting has ended";
            alert.alertStyle = .informational;
            alert.beginSheetModal(for: window, completionHandler: { _ in
                self.endCall(self);
            })
        }
    }
    
    func callStateChanged(_ sender: Call) {
        // nothing to do..
    }
    
    func call(_ sender: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            localTrack.add(self.localVideoRenderer);
        }
    }
    
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream: String, fromReceiver receiverId: String) {
        DispatchQueue.main.async {
            self.items.append(Item(contact: nil, videoTrack: remoteTrack, receiverId: receiverId));
            self.collectionView.animator().performBatchUpdates({
                self.collectionView.insertItems(at: Set([IndexPath(item: self.items.count - 1, section: 0)]));
            }, completionHandler: nil);
        }
    }
    
    func call(_ sender: Call, goneRemoteVideoTrack remoteTrack: RTCVideoTrack, fromReceiver receiverId: String) {
        DispatchQueue.main.async {
            if let idx = self.items.firstIndex(where: { $0.receiverId == receiverId }) {
                self.items.remove(at: idx);
                self.collectionView.animator().performBatchUpdates({
                    self.collectionView.deleteItems(at: Set([IndexPath(item: idx, section: 0)]));
                }, completionHandler: nil);
            }
        }
    }
    
    func call(_ sender: Call, goneLocalVideoTrack localTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            localTrack.remove(self.localVideoRenderer);
        }
    }
    
    
    public static func open(meet: Meet) {
        let meetController = MeetController();
        meetController.meet = meet;
        let windowController = NSWindowController(window: NSWindow(contentViewController: meetController));
        windowController.window?.titleVisibility = .hidden;
        windowController.window?.titlebarAppearsTransparent = true;
        windowController.window?.appearance = NSAppearance(named: .darkAqua)
        windowController.showWindow(nil);
    }
    
    private var remove: Bool = true;
    private var items: [Item] = [];
    
    func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1;
    }
    
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count;
    }
    
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let cell = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("VideoStreamCell"), for: indexPath);
        if let view = cell as? VideoStreamCell {
            view.contact = items[indexPath.item].contact;
            view.videoTrack = items[indexPath.item].videoTrack;
//            items[indexPath.item].videoTrack?.add(view.videoRenderer);
        }
        return cell;
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "meet")
    private let collectionView: NSCollectionView = NSCollectionView();
    
    private let collectonViewDelegate = CollectionViewDelegate();
    
    private let buttonsStack: NSStackView = NSStackView(frame: .zero);
    
    private var endCallButton: RoundButton?;
    private var muteButton: RoundButton?;
    private var inviteButton: RoundButton?;

    private let localVideoRenderer: RTCVideoView = RTCVideoView();
    private var localVideoRendererWidth: NSLayoutConstraint?;
    
    private var cancellables: Set<AnyCancellable> = [];
    private var muted: Bool = false {
        didSet {
            muteButton?.backgroundColor = muted ? NSColor.systemRed : NSColor.white.withAlphaComponent(0.1);
//            muteButton?.contentTintColor = muted ? NSColor.white : NSColor.white;
        }
    }
    
    private var meet: Meet? {
        didSet {
            meet?.$outgoingCall.sink(receiveValue: { [weak self] call in
                guard let that = self else {
                    return;
                }
                call?.delegate = that;
            }).store(in: &cancellables);
            meet?.$incomingCall.sink(receiveValue: { [weak self] call in
                guard let that = self else {
                    return;
                }
                call?.delegate = that;
            }).store(in: &cancellables);
        }
    }
        
    override func loadView() {
        let view = NSView();
        view.wantsLayer = true;
//        super.viewDidLoad();
        let flowLayout = FlowLayout();
        flowLayout.scrollDirection = .vertical;
        flowLayout.itemSize = NSSize(width: 100, height: 100)
        collectionView.collectionViewLayout = flowLayout;
        collectionView.delegate = collectonViewDelegate;
        collectionView.translatesAutoresizingMaskIntoConstraints = false;
        collectionView.isSelectable = false;
        collectionView.autoresizesSubviews = true;
        view.addSubview(collectionView);
        
        buttonsStack.orientation = .horizontal;
        buttonsStack.spacing = 40;
        buttonsStack.distribution = .equalSpacing;
        buttonsStack.translatesAutoresizingMaskIntoConstraints = false;
        buttonsStack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20);
        buttonsStack.setHuggingPriority(.defaultHigh, for: .horizontal);
        buttonsStack.setHuggingPriority(.defaultHigh, for: .vertical);
        
        localVideoRenderer.translatesAutoresizingMaskIntoConstraints = false;
        localVideoRenderer.wantsLayer = true;
        localVideoRenderer.layer?.cornerRadius = 5;
        localVideoRenderer.layer?.backgroundColor = NSColor.black.cgColor;
        view.addSubview(localVideoRenderer);
        
        endCallButton = RoundButton(image: NSImage(named: "endCall")!, target: self, action: #selector(endCall(_:)))
        endCallButton?.hasBorder = false;
        endCallButton?.backgroundColor = NSColor.systemRed;
        endCallButton?.contentTintColor = NSColor.white;
        buttonsStack.addArrangedSubview(endCallButton!)
        
        muteButton = RoundButton(image: NSImage(named: "muteMicrophone")!, target: self, action: #selector(muteClicked(_:)));
        muteButton?.hasBorder = false;
        muteButton?.backgroundColor = NSColor.white.withAlphaComponent(0.1);
        muteButton?.contentTintColor = NSColor.white;
        buttonsStack.addArrangedSubview(muteButton!);
        
        inviteButton = RoundButton(image: NSImage(named: "person.fill.badge.plus")!, target: self, action: #selector(inviteToCallClicked(_:)));
        inviteButton?.hasBorder = false;
        inviteButton?.backgroundColor = NSColor.white.withAlphaComponent(0.1);
        inviteButton?.contentTintColor = NSColor.white;
        buttonsStack.addArrangedSubview(inviteButton!);
        
        view.addSubview(buttonsStack);
        
        localVideoRendererWidth = localVideoRenderer.widthAnchor.constraint(equalToConstant: 100);
        
        NSLayoutConstraint.activate([
            localVideoRendererWidth!,
            localVideoRenderer.heightAnchor.constraint(equalToConstant: 100),
            
            endCallButton!.widthAnchor.constraint(equalTo: endCallButton!.heightAnchor),
            endCallButton!.widthAnchor.constraint(equalToConstant: 40),

            muteButton!.widthAnchor.constraint(equalTo: muteButton!.heightAnchor),
            muteButton!.widthAnchor.constraint(equalToConstant: 40),
            
            inviteButton!.widthAnchor.constraint(equalTo: inviteButton!.heightAnchor),
            inviteButton!.widthAnchor.constraint(equalToConstant: 40),
            
            view.leadingAnchor.constraint(equalTo: collectionView.leadingAnchor,  constant: -10),
            view.trailingAnchor.constraint(equalTo: collectionView.trailingAnchor, constant: 10),
            view.topAnchor.constraint(equalTo: collectionView.topAnchor, constant: -10),
            
            buttonsStack.topAnchor.constraint(greaterThanOrEqualTo: collectionView.bottomAnchor, constant: 10),
            //buttonsStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            //buttonsStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor),
            buttonsStack.leadingAnchor.constraint(greaterThanOrEqualTo: localVideoRenderer.trailingAnchor, constant: 20),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            view.bottomAnchor.constraint(greaterThanOrEqualTo: buttonsStack.bottomAnchor, constant: 10),

            buttonsStack.centerYAnchor.constraint(equalTo: localVideoRenderer.centerYAnchor),
            localVideoRenderer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            localVideoRenderer.topAnchor.constraint(equalTo: collectionView.bottomAnchor, constant: 10),
            view.bottomAnchor.constraint(equalTo: localVideoRenderer.bottomAnchor, constant: 10)
        ])
        
        localVideoRenderer.delegate = self;
        
        self.view = view;
    }
     
    override func viewDidLoad() {
        super.viewDidLoad();
        self.view.frame = CGRect(origin: .zero, size: CGSize(width: 560, height: 560));
        

        
        collectionView.register(VideoStreamCell.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("VideoStreamCell"))
        
        collectionView.dataSource = self;
    }
    
    @objc func endCall(_ sender: Any) {
        self.meet?.leave();
        self.view.window?.orderOut(self);
    }
   
    @objc func muteClicked(_ sender: Any) {
        muted = !muted;
        meet?.muted(value: muted);
    }
    
    @objc func inviteToCallClicked(_ sender: Any) {
        let alert = NSAlert();
        alert.alertStyle = .informational;
        alert.messageText = "Temporary placeholder";
        alert.informativeText = "This functionality is not available yet.";
        alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
    }
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DispatchQueue.main.async {
            self.localVideoRendererWidth?.animator().constant = (size.width * self.localVideoRenderer.frame.height) / size.height;
        }
    }
    
    private class FlowLayout: NSCollectionViewFlowLayout {
        
        override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
            return true;
        }
        
        override func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
            let context = super.invalidationContext(forBoundsChange: newBounds) as! NSCollectionViewFlowLayoutInvalidationContext;
            context.invalidateFlowLayoutDelegateMetrics = true;
            return context;
        }
        
    }
    
    private class CollectionViewDelegate: NSObject, NSCollectionViewDelegateFlowLayout {
        
        // TODO: This semi-works but it would be better to have some better layout!
//        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
//            let itemsCount = collectionView.numberOfItems(inSection: indexPath.section);
//            guard itemsCount > 0 else {
//                return collectionView.frame.size;
//            }
//
//            let ratio = collectionView.frame.size.width / collectionView.frame.size.height;
//            let columns = ceil(sqrt(CGFloat(itemsCount) * ratio));
//
//            let itemAreaSize = (collectionView.frame.size.width / columns) - (collectionViewLayout as! NSCollectionViewFlowLayout).minimumLineSpacing;
//            return NSSize(width: itemAreaSize, height: itemAreaSize);
//        }
        
        func collectionView(_ collectionView: NSCollectionView, layout collectionViewLayout: NSCollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> NSSize {
            let itemsCount = collectionView.numberOfItems(inSection: indexPath.section);
 
            let spacing = (collectionViewLayout as! NSCollectionViewFlowLayout).minimumLineSpacing;
            guard itemsCount > 1 else {
                return collectionView.frame.size;
            }
            
            //if collectionView.frame.size.width > collectionView.frame.size.height {
                let ratio = collectionView.frame.size.width / collectionView.frame.size.height;
//            if itemsCount == 2 {
//                return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height);
//            } else {
//                let rows = floor(sqrt(itemsCount))
//                let cols = itemsCount / rows < indexPath.item ? itemsCount / 2 : itemsCount
//            }
                switch itemsCount {
                case 2:
                    return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height);
                case 3:
//                    if ratio >= 2 {
//                        return NSSize(width: collectionView.frame.size.width / 3 - spacing, height: collectionView.frame.size.height);
//                    } else {
                        return NSSize(width: indexPath.item == 2 ? collectionView.frame.size.width : collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 2 - spacing)
//                    }
                case 4:
//                    if ratio >= 3 {
//                        return NSSize(width: collectionView.frame.size.width / 4 - spacing, height: collectionView.frame.size.height);
//                    } else {
                        return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 2 - spacing)
//                    }
                case 5:
                    if indexPath.item >= 3 {
                        return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 2 - spacing);
                    } else {
                        return NSSize(width: collectionView.frame.size.width / 3 - spacing, height: collectionView.frame.size.height / 2 - spacing);
                    }
                case 6:
                    return NSSize(width: collectionView.frame.size.width / 3 - spacing, height: collectionView.frame.size.height / 2 - spacing);
                default:
                    break;
                }
//            } else {
//                let ratio = collectionView.frame.size.height / collectionView.frame.size.width;
//                switch itemsCount {
//                case 2:
//                    return NSSize(width: collectionView.frame.size.width, height: collectionView.frame.size.height / 2 - spacing);
//                case 3:
//                    if ratio >= 2 {
//                        return NSSize(width: collectionView.frame.size.width, height: collectionView.frame.size.height / 3 - spacing);
//                    } else {
//                        return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: indexPath.item == 1 ? collectionView.frame.size.height : (collectionView.frame.size.height / 2 - spacing))
//                    }
//                case 4:
//                    if ratio >= 3 {
//                        return NSSize(width: collectionView.frame.size.width, height: collectionView.frame.size.height / 4 - spacing);
//                    } else {
//                        return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 2 - spacing)
//                    }
//                case 5:
//                    if indexPath.item >= 4 {
//                        return NSSize(width: collectionView.frame.size.width, height: collectionView.frame.size.height / 3 - spacing);
//                    } else {
//                        return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 3 - spacing);
//                    }
//                case 6:
//                    return NSSize(width: collectionView.frame.size.width / 2 - spacing, height: collectionView.frame.size.height / 3 - spacing);
//                default:
//                    break;
//                }
//            }

            guard itemsCount > 0 else {
                return collectionView.frame.size;
            }
            
            let columns = ceil(sqrt(CGFloat(itemsCount) * ratio));
            
            let itemAreaSize = (collectionView.frame.size.width / columns) - (collectionViewLayout as! NSCollectionViewFlowLayout).minimumLineSpacing;
            return NSSize(width: itemAreaSize, height: itemAreaSize);
        }

    }
    
    private struct Item {
        let contact: Contact?;
        let videoTrack: RTCVideoTrack?;
        let receiverId: String;
    }
    
    private class VideoStreamCell: NSCollectionViewItem {
        
        private let avatarView: AvatarView = AvatarView();
        private let nameLabel: NSTextField = NSTextField(labelWithString: "");
        let videoRenderer: RTCMTLNSVideoView = RTCMTLNSVideoView(frame: .zero);
        
        private var cancellables: Set<AnyCancellable> = [];
        
        private var avatarSize: NSLayoutConstraint?;
        
        var videoTrack: RTCVideoTrack? {
            willSet {
                videoTrack?.remove(videoRenderer);
            }
            didSet {
                videoTrack?.add(videoRenderer);
            }
        }
        
        var contact: Contact? {
            didSet {
                cancellables.removeAll();
                contact?.$displayName.map({ $0 as String? }).receive(on: DispatchQueue.main).assign(to: \.name, on: avatarView).store(in: &cancellables);
                contact?.$displayName.receive(on: DispatchQueue.main).assign(to: \.stringValue, on: nameLabel).store(in: &cancellables);
                contact?.avatarPublisher.receive(on: DispatchQueue.main).assign(to: \.avatar, on: avatarView).store(in: &cancellables);
            }
        }
        
        override func loadView() {
            self.view = NSView();
            view.wantsLayer = true;
            view.layer?.backgroundColor = NSColor.systemGray.cgColor;
            view.layer?.cornerRadius = 10;
            
            avatarView.translatesAutoresizingMaskIntoConstraints = false;
            nameLabel.translatesAutoresizingMaskIntoConstraints = false;
            videoRenderer.translatesAutoresizingMaskIntoConstraints = false;
            videoRenderer.wantsLayer = true;
            for subview in videoRenderer.subviews {
                (subview as? MTKView)?.layerContentsPlacement = .scaleProportionallyToFill;
                if let mtkView = subview as? MTKView {
                    print("found MTKView:", mtkView);
                }
            }

            avatarView.imageScaling = .scaleProportionallyUpOrDown;
            
            nameLabel.alignment = .center;
            nameLabel.backgroundColor = NSColor.darkGray.withAlphaComponent(0.8);
            nameLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            nameLabel.drawsBackground = true;
            
            view.addSubview(avatarView);
            view.addSubview(videoRenderer);
            view.addSubview(nameLabel);
            
            avatarSize = avatarView.widthAnchor.constraint(equalToConstant: 0);
            
            NSLayoutConstraint.activate([
                avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
                view.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
                view.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),

                avatarSize!,
                            
                view.leadingAnchor.constraint(equalTo: videoRenderer.leadingAnchor),
                view.topAnchor.constraint(equalTo: videoRenderer.topAnchor),
                view.trailingAnchor.constraint(equalTo: videoRenderer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: videoRenderer.bottomAnchor),
                
                view.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: nameLabel.bottomAnchor)
            ])
        }
        
        override func viewWillLayout() {
            avatarSize?.constant = min(self.view.frame.height, self.view.frame.width) * 0.8;
//            self.updateVideoRendererSize();
            super.viewWillLayout();
        }
        
        override func viewDidDisappear() {
            self.videoTrack?.remove(videoRenderer);
            super.viewDidDisappear();
        }
        
    }
}

extension NSLayoutConstraint {
    
    func priority(_ value: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = value;
        return self;
    }
    
}


