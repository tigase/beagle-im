//
//  VideoCallController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 07/12/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import WebRTC
import TigaseSwift

class VideoCallController: NSViewController, RTCVideoViewDelegate {
    
    public static func accept(session: JingleManager.Session, sdpOffer: SDP) -> Bool {
        guard !sdpOffer.contents.filter({ (content) -> Bool in
            return (content.description?.media == "audio") || (content.description?.media == "video");
        }).isEmpty else {
            return false;
        }
        open { (windowController) in
            (windowController.contentViewController as? VideoCallController)?.accept(session: session, sdpOffer: sdpOffer);
        }
        return true;
    }
    
    public static func open(completionHandler: @escaping (NSWindowController)->Void) {
        DispatchQueue.main.async {
            let windowController = NSStoryboard(name: "VoIP", bundle: nil).instantiateController(withIdentifier: "VideoCallWindowController") as! NSWindowController;
            windowController.showWindow(nil);
            DispatchQueue.main.async {
                windowController.window?.makeKey();
                completionHandler(windowController);
                NSApp.activate(ignoringOtherApps: true);
            }
        }
    }
    
    public static func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool) {
        open { (windowController) in
            (windowController.contentViewController as? VideoCallController)?.call(jid: jid, from: account, withAudio: withAudio, withVideo: withVideo);
        }
    }
    
    @IBOutlet var remoteVideoView: RTCMTLNSVideoView!
    @IBOutlet var localVideoView: RTCMTLNSVideoView!;
    
    var remoteVideoViewAspect: NSLayoutConstraint?
    var localVideoViewAspect: NSLayoutConstraint?
    
    var session: JingleManager.Session? {
        didSet {
            if let conn = session?.peerConnection {
                if conn.configuration.sdpSemantics == .unifiedPlan {
                    if remoteVideoView != nil {
                        conn.transceivers.forEach { (trans) in
                            if trans.mediaType == .video && (trans.direction == .sendRecv || trans.direction == .recvOnly) {
                                guard let track = trans.receiver.track as? RTCVideoTrack else {
                                    return;
                                }
                                self.didAdd(remoteVideoTrack: track);
                            }
                        }
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
    
    override func viewDidLoad() {
        super.viewDidLoad();
        localVideoView.wantsLayer = true;
        //videoView.translatesAutoresizingMaskIntoConstraints = false;
        localVideoView.layer?.transform = CATransform3DMakeScale(1.0, -1.0, 1.0);

        remoteVideoView.heightAnchor.constraint(greaterThanOrEqualTo: localVideoView.heightAnchor, multiplier: 4).isActive = true;
        remoteVideoView.heightAnchor.constraint(lessThanOrEqualTo: localVideoView.heightAnchor, multiplier: 5).isActive = true;
        localVideoViewAspect = localVideoView.widthAnchor.constraint(equalTo: localVideoView.heightAnchor, multiplier: 640.0/480.0);
        localVideoViewAspect?.isActive = true;
        
        remoteVideoViewAspect = remoteVideoView.widthAnchor.constraint(equalTo: remoteVideoView.heightAnchor, multiplier: 640.0/480.0);
        remoteVideoViewAspect?.isActive = true;
        
        localVideoView.delegate = self;
        remoteVideoView.delegate = self;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();

        self.localAudioTrack = JingleManager.instance.connectionFactory.audioTrack(withTrackId: "audio0");
        self.localVideoSource = JingleManager.instance.connectionFactory.videoSource();
        self.localVideoCapturer = RTCCameraVideoCapturer(delegate: self.localVideoSource!);
        self.localVideoTrack = JingleManager.instance.connectionFactory.videoTrack(with: self.localVideoSource!, trackId: "video-" + UUID().uuidString);
        
        self.startVideoCapture(videoCapturer: self.localVideoCapturer!) {
            print("started!");
        }
    }
    
    func videoView(_ videoView: RTCVideoRenderer, didChangeVideoSize size: CGSize) {
        DispatchQueue.main.async {
            if videoView === self.localVideoView! {
                self.localVideoViewAspect?.isActive = false;
                self.localVideoView.removeConstraint(self.localVideoViewAspect!);
                self.localVideoViewAspect = self.localVideoView.widthAnchor.constraint(equalTo: self.localVideoView.heightAnchor, multiplier: size.width / size.height);
                self.localVideoViewAspect?.isActive = true;
                print("local frame:", self.localVideoView!.frame);
            } else if videoView === self.remoteVideoView! {
                self.remoteVideoViewAspect?.isActive = false;
                self.remoteVideoView.removeConstraint(self.remoteVideoViewAspect!);
                self.remoteVideoViewAspect = self.remoteVideoView.widthAnchor.constraint(equalTo: self.remoteVideoView.heightAnchor, multiplier: size.width / size.height);
                self.remoteVideoViewAspect?.isActive = true;
                print("remote frame:", self.localVideoView!.frame);
            }
        }
    }

    fileprivate var sessionsInProgress: [JingleManager.Session] = [];
    
    func accept(session: JingleManager.Session, sdpOffer: SDP) {
        DispatchQueue.main.async {
            let name = session.client?.rosterStore?.get(for: session.jid.withoutResource)?.name ?? session.jid.bareJid.stringValue;
            
            let alert = NSAlert();
            alert.messageText = "Incoming call from \(name)";
            //alert.icon = NSImage(named: NSImage.)
            alert.informativeText = "Do you want to accept this call?"
            
            alert.addButton(withTitle: "Accept video");
            alert.addButton(withTitle: "Accept audio")
            alert.addButton(withTitle: "Deny");
            
            alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                switch response {
                case .alertFirstButtonReturn:
                    self.accept(session: session, sdpOffer: sdpOffer, withAudio: true, withVideo: true);
                case .alertSecondButtonReturn:
                    self.accept(session: session, sdpOffer: sdpOffer, withAudio: true, withVideo: false);
                default:
                    _ = session.decline();
                    self.closeWindow();
                }
            });
        }
    }
    
    fileprivate func accept(session: JingleManager.Session, sdpOffer: SDP, withAudio: Bool, withVideo: Bool) {
        self.session = session;
        session.delegate = self;
        session.initiated();
        
        session.peerConnection = self.initiatePeerConnection();
        
        let sessDesc = RTCSessionDescription(type: .offer, sdp: sdpOffer.toString());

        self.initializeMedia(for: session, audio: withAudio, video: withVideo) {
            session.peerConnection?.delegate = session;
            print("setting remote description:", sdpOffer.toString());
            self.setRemoteSessionDescription(sessDesc) {
                DispatchQueue.main.async {
                    if (session.peerConnection?.configuration.sdpSemantics ?? RTCSdpSemantics.planB) == RTCSdpSemantics.unifiedPlan {
                        session.peerConnection?.transceivers.forEach({ transceiver in
                            if !withAudio && transceiver.mediaType == .audio {
                                transceiver.stop();
                            }
                            if !withVideo && transceiver.mediaType == .video {
                                transceiver.stop();
                            }
                        });
                    }
                    
                    session.peerConnection?.answer(for: self.defaultCallConstraints, completionHandler: { (sdpAnswer, error) in
                        guard error == nil else {
                            _ = session.decline();
                            
                            DispatchQueue.main.async {
                                let alert = NSAlert();
                                alert.icon = NSImage(named: NSImage.infoName);
                                alert.messageText = "Call failed";
                                alert.informativeText = "Negotiation of the call failed";
                                alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                                    self.closeWindow();
                                })
                            }
                            return;
                        }
                        print("generated local description:", sdpAnswer!.sdp, sdpAnswer!.type);
                        self.setLocalSessionDescription(sdpAnswer!, for: session, onSuccess: {
                            print("set local description:", session.peerConnection?.localDescription?.sdp);
                            
                            let sdp = SDP(from: sdpAnswer!.sdp, creator: session.role);
                            _  = session.accept(contents: sdp!.contents, bundle: sdp!.bundle);
                        })
                    })
                }
            }
        }
    }

    func setAudioEnabled(value: Bool) {
        guard let videoTracks = self.session?.peerConnection?.senders.compactMap({ (sender) -> RTCAudioTrack? in
            return sender.track as? RTCAudioTrack;
        }) else {
            return;
        }
        videoTracks.forEach { (track) in
            print("audio is enbled:", track, track.isEnabled);
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
            print("video is enbled:", track, track.isEnabled);
            track.isEnabled = value;
        }
    }
    
    func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool) {
        guard let presences = XmppService.instance.getClient(for: account)?.presenceStore?.getPresences(for: jid)?.keys, !presences.isEmpty
            else {
                let alert = NSAlert();
                alert.messageText = "Call failed";
                alert.informativeText = "It was not possible to establish connection. Recipient is unavailable.";
                alert.icon = NSImage(named: NSImage.cautionName);
                alert.addButton(withTitle: "OK");
                alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                     self.closeWindow();
                });
                return;
        }
        
        var waitingFor: Int = presences.count;
        
        let finisher = { [weak self] in
            guard let that = self else {
                return;
            }
            DispatchQueue.main.async {
                waitingFor = waitingFor - 1;
                if waitingFor == 0 && that.sessionsInProgress.isEmpty {
                    let alert = NSAlert();
                    alert.messageText = "Call failed";
                    alert.informativeText = "It was not possible to establish connection.";
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: that.view.window!, completionHandler: { (response) in
                        that.closeWindow();
                    });
                }
            }
        }
        
        presences.forEach { (resource) in
            let session = JingleManager.instance.open(for: account, with: JID(jid, resource: resource), sid: nil, role: .initiator);
            
            session.delegate = self;
            
            session.peerConnection = self.initiatePeerConnection();
            self.initializeMedia(for: session, audio: withAudio, video: withVideo) {
                session.peerConnection?.offer(for: self.defaultCallConstraints, completionHandler: { (sdp, error) in
                    if sdp != nil && error == nil {
                        print("setting local description:", sdp!.sdp);
                        
                        self.setLocalSessionDescription(sdp!, for: session, onError: finisher, onSuccess: {
                            let sdpOffer = SDP(from: sdp!.sdp, creator: .initiator)!;
                            
                            if session.initiate(sid: sdpOffer.sid, contents: sdpOffer.contents, bundle: sdpOffer.bundle) {
                                DispatchQueue.main.async {
                                    self.sessionsInProgress.append(session);
                                    session.delegate = self;
                                }
                            } else {
                                _ = session.terminate();
                            }
                            
                            finisher();
                        })
                    } else {
                        finisher();
                    }
                });
            }
        }
    }
    
    fileprivate var defaultCallConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil);
    
    func initiatePeerConnection() -> RTCPeerConnection {
        let configuration = RTCConfiguration();
        configuration.sdpSemantics = .unifiedPlan;
        configuration.iceServers = [ RTCIceServer(urlStrings: ["stun:stun1.l.google.com:19302"]), RTCIceServer(urlStrings: ["stun:stunserver.org:3478"]) ];
        configuration.bundlePolicy = .maxBundle;
        configuration.rtcpMuxPolicy = .require;
        
        return JingleManager.instance.connectionFactory.peerConnection(with: configuration, constraints: self.defaultCallConstraints, delegate: session);
    }
    
    // this may be called multiple times, needs to handle that with video capture!!!
    func initializeMedia(for session: JingleManager.Session, audio: Bool, video: Bool, completionHandler: @escaping ()->Void) {
//        DispatchQueue.main.async {
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
                    completionHandler();
                }
            } else {
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
                print("checking format:", size.width, "x", size.height, ", type:", CMFormatDescriptionGetMediaSubType(format.formatDescription), "expected:", videoCapturer.preferredOutputPixelFormat());
                // larger size causes issues during encoding...
//                if (size.width > 640) {
//                    return;
//                }
                
                format.videoSupportedFrameRateRanges.forEach({ (range) in
                    if (bestFrameRate == nil || bestFrameRate!.maxFrameRate < range.maxFrameRate) {
                        bestFrameRate = range;
                        bestFormat = format;
                    } else if (bestFrameRate != nil && bestFrameRate!.maxFrameRate == range.maxFrameRate && CMFormatDescriptionGetMediaSubType(format.formatDescription) == videoCapturer.preferredOutputPixelFormat()) {
                        bestFormat = format;
                    }
                });
            });
            
            if bestFormat != nil && bestFrameRate != nil {
                videoCapturer.startCapture(with: device, format: bestFormat!, fps: Int(bestFrameRate!.maxFrameRate*0.86), completionHandler: { error in
                    
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
        if self.remoteVideoTrack != nil && self.remoteVideoTrack! == remoteVideoTrack {
            return;
        }
        self.remoteVideoTrack = remoteVideoTrack;
    }
    
    func didAdd(localVideoTrack: RTCVideoTrack) {
        if self.localVideoTrack != nil && self.localVideoTrack! == localVideoTrack {
            return;
        }
        self.localVideoTrack = localVideoTrack;
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        _ = session?.terminate();
        self.sessionsInProgress.forEach { sess in
            _ = sess.terminate();
        }
    }

    func sessionTerminated(session: JingleManager.Session) {
        DispatchQueue.main.async {
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                if self.session == nil && self.sessionsInProgress.isEmpty {
                    let alert = NSAlert();
                    alert.messageText = "Call rejected!";
                    alert.informativeText = "Call was rejected by the recipient.";
                    alert.icon = NSImage(named: NSImage.infoName);
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                         self.closeWindow();
                    });
                }
            } else if let sess = self.session {
                if sess.sid == session.sid && sess.jid == session.jid && sess.account == session.account {
                    self.session = nil;

                    if let videoCapturer = self.localVideoCapturer {
                        videoCapturer.stopCapture(completionHandler: nil);
                    }
                    
                    let alert = NSAlert();
                    alert.messageText = "Call ended!";
                    alert.informativeText = "Call ended.";
                    alert.icon = NSImage(named: NSImage.infoName);
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        self.closeWindow();
                    });
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
                
                print("setting remote description:", sdpAnswer.toString());
                let sessDesc = RTCSessionDescription(type: .answer, sdp: sdpAnswer.toString());
                self.setRemoteSessionDescription(sessDesc, onSuccess: {
                    print("remote session description set");
                })
            }
        }
    }
    
    func closeWindow() {
        DispatchQueue.main.async {
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
    
    fileprivate func setLocalSessionDescription(_ sessDesc: RTCSessionDescription, for session: JingleManager.Session, onError: (()->Void)? = nil, onSuccess: @escaping ()->Void) {
        DispatchQueue.main.async {
            session.peerConnection?.setLocalDescription(sessDesc, completionHandler: { (error) in
                guard error == nil else {
                    guard onError == nil else {
                        onError!();
                        return;
                    }
                    
                    _ = session.decline();
                    
                    DispatchQueue.main.async {
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.infoName);
                        alert.messageText = "Call failed";
                        alert.informativeText = "Negotiation of the call failed";
                        alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                            self.closeWindow();
                        })
                    }
                    return;
                }
                
                
                session.localDescriptionSet();
            });
            
            onSuccess();
        }
    }
    
    fileprivate func setRemoteSessionDescription(_ sessDesc: RTCSessionDescription, onSuccess: @escaping ()->Void) {
        guard let session = self.session else {
            return;
        }
        
        session.peerConnection?.setRemoteDescription(sessDesc, completionHandler: { (error) in
            print("remote description set:", session.peerConnection?.remoteDescription?.sdp);
            guard error == nil else {
                session.decline();
                
                DispatchQueue.main.async {
                    let alert = NSAlert();
                    alert.icon = NSImage(named: NSImage.infoName);
                    alert.messageText = "Call failed";
                    alert.informativeText = "Negotiation of the call failed";
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        self.closeWindow();
                    })
                }
                return;
            }

            session.remoteDescriptionSet();
            onSuccess();
        });
    }
}
