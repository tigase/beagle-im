//
// VideoCallController.swift
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
import WebRTC
import Martin
import Metal
import UserNotifications
import os
import MetalKit

class RTCVideoView: RTCMTLNSVideoView {
    
    var scaling: RTCVideoViewScaling {
        get {
            guard let view = subviews.compactMap({ $0 as? MTKView }).first else {
                return .fit;
            }
            switch view.layerContentsPlacement {
            case .scaleProportionallyToFill:
                return .fill;
            default:
                return .fit;
            }
        }
        set {
            guard let view = subviews.compactMap({ $0 as? MTKView }).first else {
                return;
            }
            switch newValue {
            case .fit:
                view.layerContentsPlacement = .scaleProportionallyToFit;
            case .fill:
                view.layerContentsPlacement = .scaleProportionallyToFill;
            }
        }
    }
    
    override func renderFrame(_ frame: RTCVideoFrame?) {
        super.renderFrame(frame);
    }

}

enum RTCVideoViewScaling {
    case fit
    case fill
}

class VideoCallController: NSViewController, RTCVideoViewDelegate, CallDelegate {
    
    public static let peerConnectionFactory: RTCPeerConnectionFactory = {
        return RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory());
    }();
    
    public static func open(completionHandler: @escaping (VideoCallController)->Void) {
        DispatchQueue.main.async {
            let windowController = NSStoryboard(name: "VoIP", bundle: nil).instantiateController(withIdentifier: "VideoCallWindowController") as! NSWindowController;
            completionHandler(windowController.contentViewController as! VideoCallController);
            windowController.showWindow(nil);
            DispatchQueue.main.async {
                windowController.window?.makeKey();
                NSApp.activate(ignoringOtherApps: true);
            }
        }
    }
    
    private var call: Call?;
    
    func callDidStart(_ call: Call) {
        self.call = call;
        self.updateAvatarView();
        self.updateStateLabel();
    }
    
    func callDidEnd(_ sender: Call) {
        self.call = nil;
        if sender.direction == .incoming {
            self.closeWindow();
        } else {
            self.hideAlert();
            var title = NSLocalizedString("Call ended", comment: "video call conroller");
            switch sender.state {
            case .ringing:
                title = NSLocalizedString("Call declined", comment: "video call conroller");
            case .connecting:
                title = NSLocalizedString("Call failed", comment: "video call conroller");
            default:
                break;
            }
            DispatchQueue.main.async {
                self.avplayer = nil;
                NSSound(named: "Blow")?.play();
            }
            self.showAlert(title: title, buttons: [NSLocalizedString("OK", comment: "Button")], completionHandler: { response in
                DispatchQueue.main.async {
                    self.closeWindow();
                }
            });
        }
    }
    
    func callStateChanged(_ sender: Call) {
        updateStateLabel();
    }
    
    func call(_ call: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack) {
        DispatchQueue.main.async {
            self.localVideoTrack = localTrack;
        }
    }
    
    func call(_ call: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream: String, fromReceiver: String) {
        self.remoteVideoTrack = remoteTrack;
    }
    
    func call(_ sender: Call, goneLocalVideoTrack localTrack: RTCVideoTrack) {
        
    }
    
    func call(_ sender: Call, goneRemoteVideoTrack remoteTrack: RTCVideoTrack, fromReceiver: String) {
        
    }
    
    @IBOutlet var remoteVideoView: RTCVideoView!
    @IBOutlet var localVideoView: RTCVideoView!;
    
    @IBOutlet var remoteAvatarView: AvatarView!;
    
//    var remoteVideoViewAspect: NSLayoutConstraint?
    var localVideoViewAspect: NSLayoutConstraint?
                
    fileprivate var localVideoTrack: RTCVideoTrack? {
        willSet {
            if localVideoTrack != nil && localVideoView != nil {
                localVideoTrack!.remove(localVideoView!);
            }
        }
        didSet {
            if localVideoTrack != nil && localVideoView != nil {
                localVideoTrack!.add(localVideoView!);
            }
        }
    }
    fileprivate var remoteVideoTrack: RTCVideoTrack? {
        willSet {
            if remoteVideoTrack != nil && remoteVideoView != nil {
                remoteVideoTrack!.remove(remoteVideoView);
            }
        }
        didSet {
            if remoteVideoTrack != nil && remoteVideoView != nil {
                remoteVideoTrack!.add(remoteVideoView);
            }
        }
    }
    
    @IBOutlet var stateLabel: NSTextField!;
    @IBOutlet var moreButton: RoundButton!;
    
    override func viewDidLoad() {
        super.viewDidLoad();

        remoteVideoView.wantsLayer = true;
        remoteVideoView.scaling = .fill;
        localVideoViewAspect = localVideoView.widthAnchor.constraint(equalTo: localVideoView.heightAnchor, multiplier: 1.0);
        localVideoViewAspect?.isActive = true;
        
//        remoteVideoViewAspect = remoteVideoView.widthAnchor.constraint(equalTo: remoteVideoView.heightAnchor, multiplier: 1.0);
//        remoteVideoViewAspect?.isActive = true;
        
        localVideoView.wantsLayer = true;
        localVideoView.layer?.cornerRadius = 5;
        localVideoView.layer?.backgroundColor = NSColor.black.cgColor;
        localVideoView.delegate = self;
        remoteVideoView.delegate = self;
    }
    
//    private var timer: Foundation.Timer?;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        if let call = self.call, call.state == .ringing {
            switch call.direction {
            case .incoming:
                self.askForAcceptance(for: call);
            case .outgoing:
                break;
            }
        }
        self.updateAvatarView();
        self.updateStateLabel();
        
//        timer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { timer in
//            guard let tracks = self.call?.currentConnection?.receivers.map({ $0.track }) else {
//                return;
//            }
//            for track in tracks {
//                self.call?.currentConnection?.stats(for: track, statsOutputLevel: .debug, completionHandler: { report in
//                    print("stats: \(report)");
//                })
//            }
//        });
    }
    
    override func viewWillDisappear() {
//        timer?.invalidate();
        super.viewWillDisappear();
    }
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DispatchQueue.main.async {
            if videoView === self.localVideoView! {
                self.localVideoViewAspect?.isActive = false;
                self.localVideoView.removeConstraint(self.localVideoViewAspect!);
                self.localVideoViewAspect = self.localVideoView.widthAnchor.constraint(equalTo: self.localVideoView.heightAnchor, multiplier: size.width / size.height);
                self.localVideoViewAspect?.isActive = true;
            } else if videoView === self.remoteVideoView! {
//                let currSize = self.remoteVideoView.frame.size;
//
//                let newHeight = sqrt((currSize.width * currSize.height)/(size.width/size.height));
//                let newWidth = newHeight * (size.width/size.height);
//
//                self.remoteVideoViewAspect?.isActive = false;
//                self.remoteVideoView.removeConstraint(self.remoteVideoViewAspect!);
//                //self.view.window?.setContentSize(NSSize(width: newWidth, height: newHeight));
//                self.remoteVideoViewAspect = self.remoteVideoView.widthAnchor.constraint(equalTo: self.remoteVideoView.heightAnchor, multiplier: size.width / size.height);
//                self.remoteVideoViewAspect?.isActive = true;
            }
        }
    }
    
    private func updateAvatarView() {
        if let call = self.call {
            self.remoteAvatarView?.avatar = AvatarManager.instance.avatar(for: call.jid, on: call.account);
            self.remoteAvatarView?.name = DBRosterStore.instance.item(for: call.account, jid: JID(call.jid))?.name ?? call.jid.description;
        } else {
            self.remoteAvatarView?.avatar = nil;
            self.remoteAvatarView?.name = nil;
        }
        self.localVideoView.isHidden = !(call?.media.contains(.video) ?? false);
        self.moreButton.isHidden = !(call?.media.contains(.video) ?? false);
    }
    
    private func updateStateLabel() {
        DispatchQueue.main.async {
            switch self.call?.state ?? .new {
            case .new:
                self.stateLabel.stringValue = NSLocalizedString("New call", comment: "video call conroller");
            case .ringing:
                self.stateLabel.stringValue = NSLocalizedString("Ringing...", comment: "video call conroller");
                if self.call?.direction == .outgoing {
                    self.avplayer = AVPlayer(url: Bundle.main.url(forResource: "outgoingCall", withExtension: "mp3")!);
                }
            case .connecting:
                self.stateLabel.stringValue = NSLocalizedString("Connecting...", comment: "video call conroller");
            case .connected:
                self.stateLabel.stringValue = "";
                self.remoteAvatarView?.isHidden = self.remoteVideoTrack != nil;
                self.avplayer = nil;
                NSSound(named: "Glass")?.play();
            case .ended:
                self.stateLabel.stringValue = NSLocalizedString("Call ended", comment: "video call conroller");
                self.avplayer = nil;
            }
        }
    }
    
    private var avplayer: AVPlayer? = nil {
        didSet {
            if let value = oldValue {
                os_log(OSLogType.debug, log: .jingle, "deregistering av player item: %s", value.currentItem?.description ?? "nil");
                value.pause();
                NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: value.currentItem);
            }
            if let value = avplayer {
                value.actionAtItemEnd = .none;
                os_log(OSLogType.debug, log: .jingle, "registering av player item: %s", value.currentItem?.description ?? "nil");
                NotificationCenter.default.addObserver(self, selector: #selector(playerItemDidReachEnd), name: .AVPlayerItemDidPlayToEndTime, object: value.currentItem);
                value.play();
            }
        }
    }
    
    @objc func playerItemDidReachEnd(notification: Notification) {
        if let playerItem = notification.object as? AVPlayerItem {
            playerItem.seek(to: CMTime.zero, completionHandler: nil)
        }
    }
    
    var logger: RTCFileLogger?;
    var loggerFile: URL?;
        
    func askForAcceptance(for call: Call) {
        DispatchQueue.main.async {
            self.avplayer = AVPlayer(url: Bundle.main.url(forResource: "incomingCall", withExtension: "mp3")!);
            let buttons = [ NSLocalizedString("Accept", comment: "Button"), NSLocalizedString("Reject", comment: "Button") ];
            
            let name = DBRosterStore.instance.item(for: call.account, jid: JID(call.jid))?.name ?? call.jid.description;
            
            self.showAlert(title: (call.media.contains(.video) ? String.localizedStringWithFormat(NSLocalizedString("Incoming video call from %@", comment: "video call controller"), name) : String.localizedStringWithFormat(NSLocalizedString("Incoming audio call from %@", comment: "video call controller"), name)) + NSLocalizedString("Do you want to accept this call?", comment: "video call controller"), buttons: buttons, completionHandler: { (response) in
                self.avplayer = nil;
                switch response {
                case .alertFirstButtonReturn:
                    DispatchQueue.global().async {
                        call.accept(offerMedia: call.media)
                    }
                default:
                    call.reject();
                }
            });
        }
    }
    
    var muted: Bool = false;
    
    @IBAction func muteClicked(_ sender: RoundButton) {
        muted = !muted;
        sender.backgroundColor = muted ? NSColor.red : NSColor.white;
        sender.contentTintColor = muted ? NSColor.white : NSColor.black;
        
        self.call?.mute(value: muted);
    }
    
    @IBAction func moreClicked(_ sender: RoundButton) {
        guard self.call?.media.contains(.video) ?? false else {
            return;
        }
        
        if let event = NSApp.currentEvent {
            let menu = NSMenu(title: "");
            menu.addItem(withTitle: NSLocalizedString("Fill frame", comment: "video call menu action"), action: #selector(fillFrame), keyEquivalent: "").state = remoteVideoView.scaling == .fill ? .on : .off;
            menu.addItem(withTitle: NSLocalizedString("Fit to frame", comment: "video call menu action"), action: #selector(fitFrame), keyEquivalent: "").state = remoteVideoView.scaling == .fit ? .on : .off;
            menu.addItem(.separator());
            let selectCamera = menu.addItem(withTitle: NSLocalizedString("Video source", comment: "video call menu action"), action: nil, keyEquivalent: "");
            let camerasMenu = NSMenu(title: NSLocalizedString("Video source", comment: "video call menu action"));
            let currentDevice = call?.currentCapturerDevice;
            for device in VideoCaptureDevice.allDevices {
                let item = camerasMenu.addItem(withTitle: device.label, action: #selector(changeVideoSource(_:)), keyEquivalent: "");
                item.representedObject = device;
                item.state = device == currentDevice ? .on : .off;
            }
            selectCamera.submenu = camerasMenu;
            for item in (menu.items + camerasMenu.items) {
                item.target = self;
            }
            NSMenu.popUpContextMenu(menu, with: event, for: sender);
        }
    }
    
    @objc func fillFrame() {
        self.remoteVideoView.scaling = .fill;
    }
        
    @objc func fitFrame() {
        self.remoteVideoView.scaling = .fit;
    }
    
    @objc func changeVideoSource(_ item: NSMenuItem) {
        guard let device = item.representedObject as? VideoCaptureDevice else {
            return;
        }
     
        if #available(macOS 11.0, *), case .display(_) = device {
            var hasAccess = CGPreflightScreenCaptureAccess();
            if !hasAccess {
                hasAccess = CGRequestScreenCaptureAccess();
            }
            
            guard hasAccess else {
                let alert = NSAlert();
                alert.messageText = NSLocalizedString("Access denied", comment: "error window title");
                alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("You didn't grant permission to record screen from %@.", comment: "error window message - no access to the screen"), device.label);
                alert.addButton(withTitle: NSLocalizedString("OK", comment: "button label"));
                guard let window = self.view.window else {
                    return;
                }
                alert.beginSheetModal(for: window, completionHandler: nil);
                return;
            }
        }
        self.call?.startVideoCapturer(device: device, completionHandler: { result in
            os_log(OSLogType.debug, log: .jingle, "switched video source");
        })
    }
    
    static let defaultCallConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]);
    
    static let publicStunServers: [RTCIceServer] = [ RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302","stun:stun1.l.google.com:19302","stun:stun2.l.google.com:19302","stun:stun3.l.google.com:19302","stun:stun4.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stunserver.org:3478" ]) ];
    
    static func initiatePeerConnection(iceServers foundIceServers: [RTCIceServer], withDelegate delegate: RTCPeerConnectionDelegate) -> RTCPeerConnection? {
        let configuration = RTCConfiguration();
        configuration.sdpSemantics = .unifiedPlan;
        
        let iceServers: [RTCIceServer] = (foundIceServers.isEmpty && Settings.usePublicStunServers) ? publicStunServers : foundIceServers;
        
        os_log(OSLogType.debug, log: .jingle, "using ICE servers: %s", iceServers.map({ $0.urlStrings.description }).description);
        
        configuration.iceServers = iceServers;
        configuration.bundlePolicy = .maxCompat;
        configuration.rtcpMuxPolicy = .require;
        configuration.iceCandidatePoolSize = 3;
        
        return peerConnectionFactory.peerConnection(with: configuration, constraints: defaultCallConstraints, delegate: delegate);
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        call?.reset();
//        self.localVideoCapturer?.stopCapture();
//        self.localVideoCapturer = nil;
//        if let session = self.session {
//            session.delegate = nil;
//            _ = session.terminate();
//        }
//        self.sessionsInProgress.forEach { sess in
//            sess.delegate = nil;
//            _ = sess.terminate();
//        }
        self.closeWindow();
    }

    fileprivate var alertWindow: NSWindow?;
    
    fileprivate func hideAlert() {
        DispatchQueue.main.async {
            if let window = self.alertWindow {
                self.alertWindow = nil;
                self.view.window?.endSheet(window);
            }
        }
    }
    
    fileprivate func showAlert(title: String, message: String = "", icon: NSImage? = nil, buttons: [String], completionHandler: @escaping (NSApplication.ModalResponse)->Void) {
        hideAlert();
        DispatchQueue.main.async {
            guard let window = self.view.window else {
                self.closeWindow();
                return;
            }
            let alert = NSAlert();
            alert.messageText = title;
            alert.informativeText = message;
            if icon != nil {
                alert.icon = icon!;
            }
            buttons.forEach { (button) in
                alert.addButton(withTitle: button);
            }
            // window for some reason is nil already!!
            alert.beginSheetModal(for: window, completionHandler: { (result) in
                self.alertWindow = nil;
                completionHandler(result);
            });
            self.alertWindow = alert.window;
        }
    }
    
    func closeWindow() {
        logger?.stop();
        
        DispatchQueue.main.async {
            self.avplayer = nil;
            self.localVideoTrack = nil;
            self.remoteVideoTrack = nil;
            self.view.window?.orderOut(self);
        }
    }
}
