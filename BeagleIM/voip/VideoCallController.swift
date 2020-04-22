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
import TigaseSwift
import Metal
import UserNotifications
import os

class RTCVideoView: RTCMTLNSVideoView {
    
    override func renderFrame(_ frame: RTCVideoFrame?) {
        super.renderFrame(frame);
    }

}

class VideoCallController: NSViewController, RTCVideoViewDelegate {
    
    public static var hasAudioSupport: Bool {
        return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized;
    }
    
    public static var hasVideoSupport: Bool {
        return AVCaptureDevice.authorizationStatus(for: .video) == .authorized;
    }
    
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
    
    public static func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool) {
        open { (videoCallController) in
            videoCallController.call(jid: jid, from: account, withAudio: withAudio, withVideo: withVideo);
        }
    }
    
    fileprivate func initialize(connectionFactory: RTCPeerConnectionFactory, withAudio: Bool, withVideo: Bool) {
        self.localAudioTrack = connectionFactory.audioTrack(withTrackId: "audio0");
        if VideoCallController.hasVideoSupport && withVideo {
            self.localVideoSource = connectionFactory.videoSource();
            if let localVideoCapturer = self.localVideoCapturer {
                localVideoCapturer.stopCapture();
            }
            self.localVideoCapturer = RTCCameraVideoCapturer(delegate: self.localVideoSource!);
            self.localVideoTrack = connectionFactory.videoTrack(with: self.localVideoSource!, trackId: "video-" + UUID().uuidString);
            
            self.startVideoCapture(videoCapturer: self.localVideoCapturer!) {
                os_log(OSLogType.debug, log: .jingle, "started local video track: %d", (self.localVideoTrack?.isEnabled ?? false) ? 1 : 0);
            }
        }
    }
    
    @IBOutlet var remoteVideoView: RTCMTLNSVideoView!
    @IBOutlet var localVideoView: RTCMTLNSVideoView!;
    
    @IBOutlet var remoteAvatarView: NSImageView!;
    
    var remoteVideoViewAspect: NSLayoutConstraint?
    var localVideoViewAspect: NSLayoutConstraint?
        
//    var audio: Bool = true;
//    var video: Bool = true;
    
    var session: JingleManager.Session? {
        didSet {
            os_log(OSLogType.debug, log: .jingle, "setting session: %s, peerConnection: %s",  session?.description ?? "mil", session?.peerConnection?.description ?? "nil");
            if let conn = session?.peerConnection {
                print("with sdp:", conn.configuration.sdpSemantics.rawValue);
                if conn.configuration.sdpSemantics == .unifiedPlan {
                    if remoteVideoView != nil {
                        os_log(OSLogType.debug, log: .jingle, "setting remote view");
                        conn.transceivers.forEach { (trans) in
                            if trans.mediaType == .video && (trans.direction == .sendRecv || trans.direction == .recvOnly) {
                                guard let track = trans.receiver.track as? RTCVideoTrack else {
                                    return;
                                }
                                self.didAdd(remoteVideoTrack: track);
                            }
                        }
                    } else {
                        os_log(OSLogType.debug, log: .jingle, "no remote view");
                    }
                    if localVideoView != nil {
                        conn.transceivers.forEach { (trans) in
                            if trans.mediaType == .video && (trans.direction == .sendRecv || trans.direction == .sendOnly) {
                                guard let track = trans.sender.track as? RTCVideoTrack else {
                                    return;
                                }
                                self.didAdd(localVideoTrack: track);
                            }
                        }
                    }
                    self.state = self.session?.state ?? .disconnected;
                }
            }
        }
    }
    
    fileprivate var localAudioTrack: RTCAudioTrack?;
    fileprivate var localVideoCapturer: RTCCameraVideoCapturer?;
    fileprivate var localVideoSource: RTCVideoSource?;
    
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
    
    var state: JingleManager.Session.State = .created {
        didSet {
            if state == .connected {
                DispatchQueue.main.async {
                    self.remoteAvatarView.isHidden = (self.remoteVideoTrack?.isEnabled ?? false) && ((self.remoteVideoTrack?.source.state ?? .ended) != .ended);
                }
            }
            DispatchQueue.main.async {
                switch self.state {
                case .created:
                    self.stateLabel.stringValue = "";
                case .disconnected:
                    self.stateLabel.stringValue = "Disconnected";
                case .negotiating:
                    self.stateLabel.stringValue = "Connecting...";
                case .connecting:
                    self.stateLabel.stringValue = "Connecting...";
                case .connected:
                    self.stateLabel.stringValue = "Connected";
                }
                self.stateLabel.isHidden = self.state == .connected;
                os_log(OSLogType.debug, log: .jingle, "controller state: %d %s", self.state.rawValue, self.stateLabel.stringValue);
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();

        localVideoViewAspect = localVideoView.widthAnchor.constraint(equalTo: localVideoView.heightAnchor, multiplier: 1.0);
        localVideoViewAspect?.isActive = true;
        
        remoteVideoViewAspect = remoteVideoView.widthAnchor.constraint(equalTo: remoteVideoView.heightAnchor, multiplier: 1.0);
        remoteVideoViewAspect?.isActive = true;
        
        localVideoView.delegate = self;
        remoteVideoView.delegate = self;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();

    }
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DispatchQueue.main.async {
            if videoView === self.localVideoView! {
                self.localVideoViewAspect?.isActive = false;
                self.localVideoView.removeConstraint(self.localVideoViewAspect!);
                self.localVideoViewAspect = self.localVideoView.widthAnchor.constraint(equalTo: self.localVideoView.heightAnchor, multiplier: size.width / size.height);
                self.localVideoViewAspect?.isActive = true;
            } else if videoView === self.remoteVideoView! {
                let currSize = self.remoteVideoView.frame.size;
                
                let newHeight = sqrt((currSize.width * currSize.height)/(size.width/size.height));
                let newWidth = newHeight * (size.width/size.height);
                
                self.remoteVideoViewAspect?.isActive = false;
                self.remoteVideoView.removeConstraint(self.remoteVideoViewAspect!);
                self.view.window?.setContentSize(NSSize(width: newWidth, height: newHeight));
                self.remoteVideoViewAspect = self.remoteVideoView.widthAnchor.constraint(equalTo: self.remoteVideoView.heightAnchor, multiplier: size.width / size.height);
                self.remoteVideoViewAspect?.isActive = true;
            }
        }
    }
    
    fileprivate var sessionsInProgress: [JingleManager.Session] = [];
    
    var avplayer: AVPlayer? = nil {
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
    
    private var media: [Media] = [];
    
    enum Media: String {
        case audio
        case video
        
        static func from(string: String?) -> Media? {
            guard let v = string else {
                return nil;
            }
            return Media(rawValue: v);
        }
    }
    
    func accept(session: JingleManager.Session, media: [Media], completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        loggerFile = FileManager.default.temporaryDirectory;
        logger = RTCFileLogger(dirPath: loggerFile!.path, maxFileSize: 20 * 1024 * 1024);
        logger?.start();
        DispatchQueue.main.async {
            self.avplayer = AVPlayer(url: Bundle.main.url(forResource: "incomingCall", withExtension: "aiff")!);

            self.session = session;
            session.delegate = self;
            
            let name = session.client?.rosterStore?.get(for: session.jid.withoutResource)?.name ?? session.jid.bareJid.stringValue;
            
            self.remoteAvatarView.image = AvatarManager.instance.avatar(for: session.jid.bareJid, on: session.account) ?? AvatarManager.instance.defaultAvatar;
            
            self.view.window?.title = "Call with \(name)"
            
            let isVideo = media.contains(.video);
            
            self.initialize(connectionFactory: session.peerConnectionFactory, withAudio: true, withVideo: isVideo);
            
            var buttons = [ "Accept audio", "Deny" ];
            if isVideo {
                buttons.insert("Accept video", at: 0);
            }
            
            self.showAlert(title: "Incoming call from \(name)", message: "Do you want to accept this call?", buttons: buttons, completionHandler: { (response) in
                self.avplayer = nil;
                if isVideo {
                    switch response {
                    case .alertFirstButtonReturn:
                        self.media = media;
                        completionHandler(.success(Void()));
                    case .alertSecondButtonReturn:
                        self.media = [.audio];
                        completionHandler(.success(Void()));
                    default:
                        completionHandler(.failure(.recipient_unavailable));
                        _ = session.decline();
                        self.closeWindow();
                    }
                } else {
                    switch response {
                    case .alertFirstButtonReturn:
                        self.media = [.audio];
                        completionHandler(.success(Void()));
                    default:
                        _ = session.decline();
                        self.closeWindow();
                    }
                }
            });
        }
    }
    
    func accepted(session: JingleManager.Session, sdpOffer: SDP) -> Bool {
        guard self.initiatePeerConnection(for: session) else {
            handle(error: .peerConnectionNotCreated, for: session);
            return true;
        }
        
        self.session = session;
                
        let sessDesc = RTCSessionDescription(type: .offer, sdp: sdpOffer.toString());

        guard !self.media.isEmpty else {
            return false;
        }
        
        if !media.contains(.video) {
            self.localVideoCapturer?.stopCapture();
            self.localVideoCapturer = nil;
        }
        
        self.initializeMedia(for: session, audio: media.contains(.audio), video: media.contains(.video)) { result in
            guard result else {
                self.handle(error: .mediaInitializationFailed, for: session);
                return;
            }
            session.peerConnection?.delegate = session;
            os_log(OSLogType.debug, log: .jingle, "setting remote description:  %s", sdpOffer.toString());
            self.setRemoteSessionDescription(sessDesc, for: session) { (result) in
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        if (session.peerConnection?.configuration.sdpSemantics ?? RTCSdpSemantics.planB) == RTCSdpSemantics.unifiedPlan {
                            session.peerConnection?.transceivers.forEach({ transceiver in
                                if !self.media.contains(.audio) && transceiver.mediaType == .audio {
                                    transceiver.stop();
                                }
                                if !self.media.contains(.video) && transceiver.mediaType == .video {
                                    transceiver.stop();
                                }
                            });
                        }
                        
                        session.peerConnection?.answer(for: self.defaultCallConstraints, completionHandler: { (sdpAnswer, error) in
                            guard error == nil else {
                                self.handle(error: .sdpAnswerNotGenerated(error: error!), for: session);
                                return;
                            }
                            os_log(OSLogType.debug, log: .jingle, "generated local description: %s", sdpAnswer!.sdp, sdpAnswer!.type.rawValue);
                            self.setLocalSessionDescription(sdpAnswer!, for: session, completionHandler: { result in
                                switch result {
                                case .success(_):
                                    os_log(OSLogType.debug, log: .jingle, "set local description: %s", session.peerConnection?.localDescription?.sdp ?? "nil");
                                    
                                    let sdp = SDP(from: sdpAnswer!.sdp, creator: session.role);
                                    _  = session.accept(contents: sdp!.contents, bundle: sdp!.bundle);
                                case .failure(let error):
                                    self.handle(error: error, for: session);
                                }
                            })
                        })
                    }
                case .failure(let error):
                    self.handle(error: error, for: session);
                }

            }
        }
        return true;
    }
    
    func handle(error: PeerConnectionError, for session: JingleManager.Session) {
        switch error {
        case .settingLocalDescriptionFailed(_), .settingRemoteDescriptionFailed(_):
            _ = session.decline();
        case .mediaInitializationFailed:
            _ = session.decline();
        case .sdpAnswerNotGenerated(_):
            _ = session.decline();
        case .sdpOfferNotGenerated(_):
            _ = session.decline();
        case .peerConnectionNotCreated:
            break;
        }
        self.showAlert(title: "Call failed!", message: error.description, icon: NSImage(named: NSImage.infoName), buttons: ["OK"], completionHandler: { (reponse) in
            self.closeWindow();
        });
    }

    func setAudioEnabled(value: Bool) {
        guard let audioTracks = self.session?.peerConnection?.senders.compactMap({ (sender) -> RTCAudioTrack? in
            return sender.track as? RTCAudioTrack;
        }) else {
            return;
        }
        audioTracks.forEach { (track) in
            os_log(OSLogType.debug, log: .jingle, "audio is enbled:", track, track.isEnabled);
            track.isEnabled = value;
        }
    }

    func setVideoEnabled(value: Bool) {
        guard let videoTracks = self.session?.peerConnection?.senders.compactMap({ (sender) -> RTCVideoTrack? in
            return sender.track as? RTCVideoTrack;
        }) else {
            return;
        }
        videoTracks.forEach { (track) in
            os_log(OSLogType.debug, log: .jingle, "video is enbled: %@ %d", track, track.isEnabled ? 1 : 0);
            track.isEnabled = value;
        }
    }
    
    var muted: Bool = false;
    
    @IBAction func muteClicked(_ sender: RoundButton) {
        muted = !muted;
        sender.backgroundColor = muted ? NSColor.red : NSColor.white;
        sender.contentTintColor = muted ? NSColor.white : NSColor.black;
        
        setAudioEnabled(value: !muted);
        setVideoEnabled(value: !muted);
    }
    
    func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool) {
        loggerFile = FileManager.default.temporaryDirectory;
        os_log(OSLogType.info, log: .jingle, "starting logging at: %s", loggerFile?.absoluteString ?? "nil");
        logger = RTCFileLogger(dirPath: loggerFile!.path, maxFileSize: 20 * 1024 * 1024);
        logger?.start();
        let name = XmppService.instance.getClient(for: account)?.rosterStore?.get(for: JID(jid))?.name ?? jid.stringValue;
        self.view.window?.title = "Call with \(name)";
        self.remoteAvatarView.image = AvatarManager.instance.avatar(for: jid, on: account) ?? AvatarManager.instance.defaultAvatar;
        
        guard let presences = XmppService.instance.getClient(for: account)?.presenceStore?.getPresences(for: jid)?.keys, !presences.isEmpty
            else {
                self.showAlert(title: "Call failed", message: "It was not possible to establish the connection. Recipient is unavailable.", icon: NSImage(named: NSImage.cautionName), buttons: ["OK"]) { (response) in
                    self.closeWindow();
                };
                return;
        }
        
        let connectionFactory = RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory());

        self.initialize(connectionFactory: connectionFactory, withAudio: withAudio, withVideo: withVideo);
        
        var errors: [PeerConnectionError] = [];
        
        let group = DispatchGroup();
        
        group.enter();
        presences.forEach { resource in
            group.enter();
            let session = JingleManager.instance.open(for: account, with: JID(jid, resource: resource), sid: nil, role: .initiator, peerConnectionFactory: connectionFactory);
            
            session.delegate = self;
            guard self.initiatePeerConnection(for: session) else {
                DispatchQueue.main.async {
                    errors.append(.peerConnectionNotCreated);
                }
                _ = session.terminate();
                group.leave();
                return;
            }
            
            os_log(OSLogType.debug, log: .jingle, "creating peer connection for: %@", session.jid.stringValue);
            self.initializeMedia(for: session, audio: withAudio, video: withVideo) { result in
                guard result else {
                    print("intialization of media failed!");
                    DispatchQueue.main.async {
                        errors.append(.mediaInitializationFailed);
                    }
                    _ = session.terminate();
                    group.leave();
                    return;
                }

                os_log(OSLogType.debug, log: .jingle, "preparing sdp offer for: %@", session.peerConnection?.description ?? "nil");
                session.peerConnection?.offer(for: self.defaultCallConstraints, completionHandler: { (sdp, error) in
                    if sdp != nil && error == nil {
                        os_log(OSLogType.debug, log: .jingle, "setting local description: %@", sdp!.sdp);
                        let tmp = RTCSessionDescription(type: sdp!.type, sdp: sdp!.sdp.replacingOccurrences(of: "a=mid:0", with: "a=mid:m0").replacingOccurrences(of: "a=group:BUNDLE 0", with: "a=group:BUNDLE m0"));
                        self.setLocalSessionDescription(tmp, for: session, completionHandler: { result in
                            switch result {
                            case .success(_):
                                let sdpOffer = SDP(from: tmp.sdp, creator: .initiator)!;
                                
                                if session.initiate(sid: sdpOffer.sid, contents: sdpOffer.contents, bundle: sdpOffer.bundle) {
                                    DispatchQueue.main.async {
                                        self.sessionsInProgress.append(session);
                                        session.delegate = self;
                                        group.leave();
                                    }
                                } else {
                                    _ = session.terminate();
                                    group.leave();
                                }
                            case .failure(let error):
                                DispatchQueue.main.async {
                                    errors.append(.sdpOfferNotGenerated(error: error));
                                }
                                _ = session.terminate();
                                group.leave();
                            }
                        })
                    } else {
                        DispatchQueue.main.async {
                            errors.append(.sdpOfferNotGenerated(error: error!));
                        }
                        _ = session.terminate();
                        group.leave();
                    }
                });
            }
        }
        group.leave();
        
        group.notify(queue: DispatchQueue.main, execute: { [weak self] in
            guard let that = self else {
                return;
            }
            if that.sessionsInProgress.isEmpty {
                that.showAlert(title: "Call failed", message: "It was not possible to establish the connection.\nErrors:\n \(errors.map({ $0.description }).joined(separator: "\n"))", icon: NSImage(named: NSImage.cautionName), buttons: ["OK"]) { (response) in
                    that.closeWindow();
                };
            }
        })
    }
        
    fileprivate var defaultCallConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: ["DtlsSrtpKeyAgreement": "true"]);
    
    func initiatePeerConnection(for session: JingleManager.Session) -> Bool {
        let configuration = RTCConfiguration();
        configuration.sdpSemantics = .unifiedPlan;
        
        let iceServers: [RTCIceServer] = [ RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302","stun:stun1.l.google.com:19302","stun:stun2.l.google.com:19302","stun:stun3.l.google.com:19302","stun:stun4.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stunserver.org:3478" ]) ];
        
//        if var urlComponents = URLComponents(string: Settings.turnServer.string() ?? "") {
//            let username = urlComponents.user;
//            let password = urlComponents.password;
//            urlComponents.user = nil;
//            urlComponents.password = nil;
//            let server = urlComponents.string!.replacingOccurrences(of: "/", with: "");
//            print("turn server:", server, "user:", username as Any, "pass:", password as Any);
//            iceServers.append(RTCIceServer(urlStrings: [server], username: username, credential: password, tlsCertPolicy: .insecureNoCheck));
//            let forceRelay = urlComponents.queryItems?.filter({ item in
//                item.name == "forceRelay" && item.value == "true"
//            }) != nil;
//            if forceRelay {
//                configuration.iceTransportPolicy = .relay;
//            }
//        }
        
        configuration.iceServers = iceServers;
        configuration.bundlePolicy = .maxCompat;
        configuration.rtcpMuxPolicy = .require;
        configuration.iceCandidatePoolSize = 3;
        
        return session.initiatePeerConnection(with: configuration, constraints: self.defaultCallConstraints) != nil;
    }
    
    // this may be called multiple times, needs to handle that with video capture!!!
    func initializeMedia(for session: JingleManager.Session, audio: Bool, video: Bool, completionHandler: @escaping (Bool)->Void) {
//        DispatchQueue.main.async {
        os_log(OSLogType.debug, log: .jingle, "intializing session for: %s sdpSemantics: %d", session.peerConnection?.description ?? "nil", session.peerConnection?.configuration.sdpSemantics.rawValue ?? -1)
            if (session.peerConnection?.configuration.sdpSemantics ?? RTCSdpSemantics.planB) == RTCSdpSemantics.unifiedPlan {
                // send audio?
                if audio, let localAudioTrack = self.localAudioTrack {
                    session.peerConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
                }
                
                // send video?
                if video, let localVideoTrack = self.localVideoTrack {
                    session.peerConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                }
                DispatchQueue.main.async {
                    completionHandler(true);
                }
            } else {
                DispatchQueue.main.async {
                    completionHandler(false);
                }
//                let localStream = JingleManager.instance.createLocalStream(audio: audio, video: video);
//                session.peerConnection?.add(localStream);
//                if let videoTrack = localStream.videoTracks.first {
//                    self.didAdd(localVideoTrack: videoTrack);
//                }
            }
//        }
    }
    
    fileprivate func startVideoCapture(videoCapturer: RTCCameraVideoCapturer, completionHandler: @escaping ()-> Void) {
        if let device = RTCCameraVideoCapturer.captureDevices().first {
            var bestFormat: AVCaptureDevice.Format? = nil;
            var bestFrameRate: AVFrameRateRange? = nil;
            RTCCameraVideoCapturer.supportedFormats(for: device).forEach({ (format) in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
                os_log(OSLogType.debug, log: .jingle, "checking format: %dx%d, fps: @f, type: %u, expected: %u", size.width, size.height, format.videoSupportedFrameRateRanges.map({ (range) -> Float64 in
                    return range.maxFrameRate;
                }).max() ?? 0, CMFormatDescriptionGetMediaSubType(format.formatDescription), videoCapturer.preferredOutputPixelFormat());
                // larger size causes issues during encoding...
                if (size.width > 640) {
                    return;
                }
                let currSize = bestFormat == nil ? nil : CMVideoFormatDescriptionGetDimensions(bestFormat!.formatDescription);
                let currRating = currSize == nil ? nil : (currSize!.width * currSize!.height);
                let rating = size.width * size.height;
                
                format.videoSupportedFrameRateRanges.forEach({ (range) in
                    if (bestFrameRate == nil || bestFrameRate!.maxFrameRate < range.maxFrameRate) {
                        bestFrameRate = range;
                        bestFormat = format;
                    } else if (bestFrameRate != nil && bestFrameRate!.maxFrameRate == range.maxFrameRate && (
                        (currRating! < rating)
                        || (CMFormatDescriptionGetMediaSubType(format.formatDescription)) == videoCapturer.preferredOutputPixelFormat())) {
                        bestFormat = format;
                    }
                });
            });
            
            if bestFormat != nil && bestFrameRate != nil {
                videoCapturer.startCapture(with: device, format: bestFormat!, fps: Int(bestFrameRate!.maxFrameRate), completionHandler: { error in
                    
                    // takes too long to initialize?
                    //print("video capturer started:", error);
                    
                    completionHandler();
                });
            } else {
                completionHandler();
            }
        }
    }
    
    func didAdd(remoteVideoTrack: RTCVideoTrack) {
        os_log(OSLogType.debug, log: .jingle, "remote view configured with: %@", remoteVideoTrack);
        DispatchQueue.main.async {
            if self.remoteVideoTrack != nil && self.remoteVideoTrack! == remoteVideoTrack {
                return;
            }
            self.remoteVideoTrack = remoteVideoTrack;
        }
    }
    
    func didAdd(localVideoTrack: RTCVideoTrack) {
        os_log(OSLogType.debug, log: .jingle, "skipping setting local video track!");
        DispatchQueue.main.async {
            if self.localVideoTrack != nil && self.localVideoTrack! ==  localVideoTrack {
                return;
            }
            self.localVideoTrack = localVideoTrack;
        }
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        self.localVideoCapturer?.stopCapture();
        self.localVideoCapturer = nil;
        if let session = self.session {
            session.delegate = nil;
            _ = session.terminate();
        }
        self.sessionsInProgress.forEach { sess in
            sess.delegate = nil;
            _ = sess.terminate();
        }
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
    
    func sessionTerminated(session: JingleManager.Session) {
        DispatchQueue.main.async {
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                if self.session == nil && self.sessionsInProgress.isEmpty {
                    self.showAlert(title: "Call rejected!", message: "Call was rejected by the recipient.", icon: NSImage(named: NSImage.infoName), buttons: ["OK"], completionHandler: { (response) in
                        self.closeWindow();
                    })
                }
            } else if let sess = self.session {
                if sess.sid == session.sid && sess.jid == session.jid && sess.account == session.account {
                    self.session = nil;
                    if let videoCapturer = self.localVideoCapturer {
                        videoCapturer.stopCapture(completionHandler: nil);
                        self.localVideoCapturer = nil;
                    }
                    if self.state == .created {
                        self.hideAlert();
                    } else {
                        self.showAlert(title: "Call ended!", message: "Call ended.", icon: NSImage(named: NSImage.infoName), buttons: ["OK"], completionHandler: { (response) in
                            self.closeWindow();
                        });
                    }
                }
            }
        }
    }
    
    func sessionAccepted(session: JingleManager.Session, sdpAnswer: SDP) {
        DispatchQueue.main.async {
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                self.session = session;
                self.sessionsInProgress.forEach({ (sess) in
                    _ = sess.terminate();
                })
                
                os_log(OSLogType.debug, log: .jingle, "setting remote description: %s", sdpAnswer.toString());
                let sessDesc = RTCSessionDescription(type: .answer, sdp: sdpAnswer.toString());
                self.setRemoteSessionDescription(sessDesc, for: session, completionHandler: { (result) in
                    switch result {
                    case .success(_):
                        os_log(OSLogType.debug, log: .jingle, "remote session description set");
                    case .failure(let err):
                        self.handle(error: err, for: session);
                    }
                });
            }
        }
    }
    
    func closeWindow() {
        logger?.stop();
        
        DispatchQueue.main.async {
            self.avplayer = nil;
            if let localVideoCapturer = self.localVideoCapturer {
                localVideoCapturer.stopCapture();
            }
            self.localVideoTrack = nil;
            self.remoteVideoTrack = nil;
            self.localVideoSource = nil;
            self.localVideoCapturer = nil;
            self.view.window?.orderOut(self);
        }
    }
    
    fileprivate func setLocalSessionDescription(_ sessDesc: RTCSessionDescription, for session: JingleManager.Session, completionHandler: @escaping (Result<Void,PeerConnectionError>)->Void) {
        DispatchQueue.main.async {
            session.peerConnection?.setLocalDescription(sessDesc, completionHandler: { (error) in
                if error == nil {
                    session.localDescriptionSet();
                    completionHandler(.success(Void()));
                } else {
                    completionHandler(.failure(PeerConnectionError.settingLocalDescriptionFailed(error: error!)));
                }
//                guard error == nil else {
//                    guard onError == nil else {
//                        onError!();
//                        return;
//                    }
//
//                    _ = session.decline();
//
//                    self.showAlert(title: "Call failed!", message: "Negotiation of the call failed", icon: NSImage(named: NSImage.infoName), buttons: ["OK"], completionHandler: { (reponse) in
//                        self.closeWindow();
//                    })
//                    return;
//                }
//
//
//                onSuccess();
            });
        }
    }
    
    fileprivate func setRemoteSessionDescription(_ sessDesc: RTCSessionDescription, for session: JingleManager.Session, completionHandler: @escaping (Result<Void,PeerConnectionError>)->Void) {
        session.peerConnection?.setRemoteDescription(sessDesc, completionHandler: { (error) in
            os_log(OSLogType.debug, log: .jingle, "remote description set: %s", session.peerConnection?.remoteDescription?.sdp ?? "nil");
            guard error == nil else {
                completionHandler(.failure(VideoCallController.PeerConnectionError.settingRemoteDescriptionFailed(error: error!)));
//                _ = session.decline();
//
//                self.showAlert(title: "Call failed!", message: "Negotiation of the call failed", icon: NSImage(named: NSImage.infoName), buttons: ["OK"], completionHandler: { (reponse) in
//                    self.closeWindow();
//                })
                return;
            }

            session.remoteDescriptionSet();
            completionHandler(.success(Void()));
//            onSuccess();
        });
    }
    
    enum PeerConnectionError: Error {
        case settingLocalDescriptionFailed(error: Error)
        case settingRemoteDescriptionFailed(error: Error)
        case mediaInitializationFailed
        case peerConnectionNotCreated
        case sdpOfferNotGenerated(error: Error)
        case sdpAnswerNotGenerated(error: Error)
        
        var description: String {
            switch self {
            case .settingLocalDescriptionFailed(let error), .settingRemoteDescriptionFailed(let error):
                return "Negotiation of the call failed: \(error.localizedDescription)";
            case .mediaInitializationFailed:
                return "Could not initialize recording devices";
            case .sdpAnswerNotGenerated(let error):
                return "Negotiation of the call failed: \(error.localizedDescription)";
            case .sdpOfferNotGenerated(let error):
                return "Negotiation of the call failed: \(error.localizedDescription)";
            case .peerConnectionNotCreated:
                return "Cound not initialize connection: peer connection not created!";
            }
        }
            
        var isFatal: Bool {
            return true;
        }
    }
}
