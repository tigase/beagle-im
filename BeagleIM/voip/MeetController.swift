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
import Martin
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
            alert.messageText = NSLocalizedString("Meeting ended", comment: "meet controller");
            alert.informativeText = NSLocalizedString("Meeting has ended", comment: "meet controller");
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
    
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream mid: String, fromReceiver receiverId: String) {
        DispatchQueue.main.async {
            self.items.append(Item(mid: mid, videoTrack: remoteTrack, receiverId: receiverId));
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
        if let view = cell as? VideoStreamCell, let account = meet?.client.userBareJid {
            view.delegate = self;
            view.set(item: items[indexPath.item], account: account, publishersPublisher: $publisherByMid);
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
    
    @Published
    private var publisherByMid: [String: MeetModule.Publisher] = [:];
    
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
            meet?.$publishers.sink(receiveValue: { [weak self] publishers in
                var dict: [String: MeetModule.Publisher] = [:];
                for publisher in publishers {
                    for stream in publisher.streams {
                        dict[stream] = publisher;
                    }
                }
                self?.publisherByMid = dict;
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
        let windowController = NSStoryboard(name: "VoIP", bundle: nil).instantiateController(withIdentifier: "InviteToMeetingWindowController") as! NSWindowController;
        let controller = windowController.contentViewController as! InviteToMeetingController;
        controller.meet = meet;
        if let window = windowController.window {
            window.styleMask = NSWindow.StyleMask(rawValue: window.styleMask.rawValue | NSWindow.StyleMask.nonactivatingPanel.rawValue | NSWindow.StyleMask.utilityWindow.rawValue);
            window.backgroundColor = NSColor.textBackgroundColor;
            window.hasShadow = true;
        }
        windowController.showWindow(self);
    }
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DispatchQueue.main.async {
            self.localVideoRendererWidth?.animator().constant = (size.width * self.localVideoRenderer.frame.height) / size.height;
        }
    }
    
    func deny(jid: BareJID) {
        Task {
            do {
                try await self.meet?.deny(jids: [jid]);
            } catch {
                await MainActor.run(body: {
                    guard let window = self.view.window else {
                        return;
                    }
                    let alert = NSAlert();
                    alert.alertStyle = .informational;
                    alert.messageText = NSLocalizedString("Failed to kick out", comment: "meet controlller");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to kick out %@. Server returned an error: %@", comment: "meet controller"), jid.description, error.localizedDescription);
                    alert.beginSheetModal(for: window, completionHandler: nil);
                })
            }
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
        let mid: String;
        let videoTrack: RTCVideoTrack?;
        let receiverId: String;
    }
    
    private class VideoStreamCell: NSCollectionViewItem {
        
        private class HoverView: NSView {

            weak var cell: VideoStreamCell?;

            private var trackingArea : NSTrackingArea?;

            override func updateTrackingAreas() {
                super.updateTrackingAreas()

                ensureTrackingArea()

                if let trackingArea = trackingArea, !trackingAreas.contains(trackingArea) {
                    addTrackingArea(trackingArea)
                }
            }

            func ensureTrackingArea() {
                if trackingArea == nil {
                    trackingArea = NSTrackingArea(rect: .zero,
                                                  options: [
                                                    .inVisibleRect,
                                                    .activeAlways,
                                                    .mouseEnteredAndExited],
                                                  owner: self,
                                                  userInfo: nil)
                }
            }

            override func mouseEntered(with event: NSEvent) {
                self.cell?.mouseEntered(with: event);
            }
            
            override func mouseExited(with event: NSEvent) {
                self.cell?.mouseExited(with: event);
            }
        }
        
        weak var delegate: MeetController?;
        
        private let avatarView: AvatarView = AvatarView();
        private let closeButton: NSButton = NSButton(image: NSImage(named: "xmark.circle.fill")!, target: nil, action: nil);
        private let nameLabel: NSTextField = NSTextField(labelWithString: "");
        private let nameBox = NSView();
        let videoRenderer: RTCMTLNSVideoView = RTCMTLNSVideoView(frame: .zero);
        
        private var cancellables: Set<AnyCancellable> = [];
        
        private var avatarSize: NSLayoutConstraint?;
        
        private var videoTrack: RTCVideoTrack? {
            willSet {
                videoTrack?.remove(videoRenderer);
            }
            didSet {
                videoTrack?.add(videoRenderer);
            }
        }
        
        private var contact: Contact? {
            didSet {
                cancellables.removeAll();
                contact?.$displayName.map({ $0 as String? }).receive(on: DispatchQueue.main).assign(to: \.name, on: avatarView).store(in: &cancellables);
                contact?.$displayName.receive(on: DispatchQueue.main).assign(to: \.stringValue, on: nameLabel).store(in: &cancellables);
                contact?.avatarPublisher.receive(on: DispatchQueue.main).assign(to: \.avatar, on: avatarView).store(in: &cancellables);
            }
        }
        
        private var item: Item?;
        
        private var publisherCancellable: AnyCancellable? {
            willSet {
                publisherCancellable?.cancel();
            }
        }
        
        func set(item: Item, account: BareJID, publishersPublisher: Published<[String:MeetModule.Publisher]>.Publisher) {
            self.videoTrack = item.videoTrack;
            self.item = item;
            publisherCancellable = publishersPublisher.map({ $0[item.mid]?.jid }).removeDuplicates().map({ j -> Contact? in
                if let jid = j {
                    return ContactManager.instance.contact(for: .init(account: account, jid: jid, type: .buddy));
                }
                return nil;
            }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] contact in
                self?.contact = contact;
            });
        }
        
        override func loadView() {
            self.view = HoverView();
            (self.view as? HoverView)?.cell = self;
            view.wantsLayer = true;
            view.layer?.backgroundColor = NSColor.systemGray.cgColor;
            view.layer?.cornerRadius = 10;
            
            nameBox.translatesAutoresizingMaskIntoConstraints = false;
            nameBox.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
            nameBox.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            avatarView.translatesAutoresizingMaskIntoConstraints = false;
            nameLabel.translatesAutoresizingMaskIntoConstraints = false;
            videoRenderer.translatesAutoresizingMaskIntoConstraints = false;
            videoRenderer.wantsLayer = true;
            for subview in videoRenderer.subviews {
                (subview as? MTKView)?.layerContentsPlacement = .scaleProportionallyToFill;
            }

            avatarView.imageScaling = .scaleProportionallyUpOrDown;
            
            nameLabel.alignment = .center;
            nameBox.wantsLayer = true;
            nameBox.layer?.backgroundColor = NSColor.darkGray.withAlphaComponent(0.9).cgColor;
            nameLabel.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)
            //nameLabel.drawsBackground = true;
            
            view.addSubview(avatarView);
            view.addSubview(videoRenderer);
            nameBox.addSubview(nameLabel);
            view.addSubview(nameBox);
            
            avatarSize = avatarView.widthAnchor.constraint(equalToConstant: 0);
            
            closeButton.isHidden = true;
            closeButton.isBordered = false;
            closeButton.translatesAutoresizingMaskIntoConstraints = false;
            closeButton.target = self;
            closeButton.action = #selector(closeClicked(_:));
            view.addSubview(closeButton);
            
            NSLayoutConstraint.activate([
                view.trailingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 6),
                view.topAnchor.constraint(equalTo: closeButton.topAnchor, constant: -6),
                closeButton.widthAnchor.constraint(equalTo: closeButton.heightAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 28),
                
                avatarView.heightAnchor.constraint(equalTo: avatarView.widthAnchor),
                view.centerYAnchor.constraint(equalTo: avatarView.centerYAnchor),
                view.centerXAnchor.constraint(equalTo: avatarView.centerXAnchor),

                avatarSize!,
                            
                view.leadingAnchor.constraint(equalTo: videoRenderer.leadingAnchor),
                view.topAnchor.constraint(equalTo: videoRenderer.topAnchor),
                view.trailingAnchor.constraint(equalTo: videoRenderer.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: videoRenderer.bottomAnchor),
                
                nameBox.centerXAnchor.constraint(equalTo: nameLabel.centerXAnchor),
                nameBox.leadingAnchor.constraint(lessThanOrEqualTo: nameLabel.leadingAnchor),
                nameBox.topAnchor.constraint(equalTo: nameLabel.topAnchor, constant: -6),
                nameBox.bottomAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 6),
                
                view.leadingAnchor.constraint(equalTo: nameBox.leadingAnchor),
                view.trailingAnchor.constraint(equalTo: nameBox.trailingAnchor),
                view.bottomAnchor.constraint(equalTo: nameBox.bottomAnchor)
            ])
        }
        
        override func viewWillLayout() {
            avatarSize?.constant = min(self.view.frame.height, self.view.frame.width) * 0.8;
            super.viewWillLayout();
        }
        
        override func viewDidDisappear() {
            self.videoTrack?.remove(videoRenderer);
            super.viewDidDisappear();
        }
        
        override func mouseEntered(with event: NSEvent) {
            closeButton.isHidden = false;
        }
        
        override func mouseExited(with event: NSEvent) {
            closeButton.isHidden = true;
        }
     
        @objc func closeClicked(_ sender: Any) {
            guard let jid = contact?.jid else {
                return;
            }
            delegate?.deny(jid: jid);
        }
    }
}

extension NSLayoutConstraint {
    
    func priority(_ value: NSLayoutConstraint.Priority) -> NSLayoutConstraint {
        self.priority = value;
        return self;
    }
    
}


