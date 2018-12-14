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

class VideoCallController: NSViewController {
    
    public static func call(jid: BareJID, from account: BareJID, withAudio: Bool, withVideo: Bool) {
        DispatchQueue.main.async {
            let windowController = NSStoryboard(name: "VoIP", bundle: nil).instantiateController(withIdentifier: "VideoCallWindowController") as! NSWindowController;
            windowController.showWindow(nil);
            DispatchQueue.main.async {
                (windowController.contentViewController as? VideoCallController)?.call(jid: jid, from: account, withAudio: withAudio, withVideo: withVideo);
            }
        }
    }
    
    @IBOutlet var remoteVideoView: RTCMTLNSVideoView!
    @IBOutlet var localVideoView: RTCMTLNSVideoView!;
    
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
    
    fileprivate var videoCapturer: RTCCameraVideoCapturer?;
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
        //videoView.translatesAutoresizingMaskIntoConstraints = false;
    }
    
    fileprivate var sessionsInProgress: [JingleManager.Session] = [];
    fileprivate var videoCapturers: [String: RTCCameraVideoCapturer] = [:];
    
    func accept(session: JingleManager.Session, sdpOffer: SDP) {
        DispatchQueue.main.async {
            let name = session.client?.rosterStore?.get(for: session.jid.withoutResource)?.name ?? session.jid.bareJid.stringValue;
            
            let alert = NSAlert();
            alert.messageText = "Incoming call from \(name)";
            //alert.icon = NSImage(named: NSImage.)
            alert.informativeText = "Do you want to accept this call?"
            
            alert.addButton(withTitle: "Accept");
            alert.addButton(withTitle: "Deny");
            
            alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                let accept = response == NSApplication.ModalResponse.alertFirstButtonReturn;
                
                if accept {
                    self.accept(session: session, sdpOffer: sdpOffer, withAudio: true, withVideo: true);
                } else {
                    _ = session.decline();
                    self.view.window?.orderOut(self);
                }
            });
        }
    }
    
    fileprivate func accept(session: JingleManager.Session, sdpOffer: SDP, withAudio: Bool, withVideo: Bool) {
        session.initiated();
        let configuration = RTCConfiguration();
        configuration.sdpSemantics = .unifiedPlan;
        configuration.iceServers = [ RTCIceServer(urlStrings: ["stun://64.233.161.127:19302"]) ];
        configuration.bundlePolicy = .balanced;
        configuration.rtcpMuxPolicy = .require;
//        configuration.continualGatheringPolicy = .gatherContinually;
        
        let callConstraints = RTCMediaConstraints(mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveAudio: withAudio ? "true" : "false", kRTCMediaConstraintsOfferToReceiveVideo: withVideo ? "true" : "false"], optionalConstraints: nil);
        session.peerConnection = JingleManager.instance.connectionFactory.peerConnection(with: configuration, constraints: callConstraints, delegate: session);
        
        let sessDesc = RTCSessionDescription(type: .offer, sdp: sdpOffer.toString());

        self.initializeMedia(for: session, audio: withAudio, video: withVideo) {
            print("setting remote description:", sdpOffer.toString());
            session.peerConnection?.setRemoteDescription(sessDesc, completionHandler: { (error) in
                print("remote description set:", session.peerConnection?.remoteDescription?.sdp);
                guard error == nil else {
                    session.decline();
                    
                    let alert = NSAlert();
                    alert.icon = NSImage(named: NSImage.infoName);
                    alert.messageText = "Call failed";
                    alert.informativeText = "Negotiation of the call failed";
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        self.view.window?.orderOut(self);
                    })
                    return;
                }
                
                session.remoteDescriptionSet();
                
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
                
                session.peerConnection?.answer(for: callConstraints, completionHandler: { (sdpAnswer, error) in
                    guard error == nil else {
                        _ = session.decline();
                        
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.infoName);
                        alert.messageText = "Call failed";
                        alert.informativeText = "Negotiation of the call failed";
                        alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                            self.view.window?.orderOut(self);
                        })
                        return;
                    }
                    print("generated local description:", sdpAnswer!.sdp, sdpAnswer!.type);
                    session.peerConnection?.setLocalDescription(sdpAnswer!, completionHandler: { (error) in
                        guard error == nil else {
                            _ = session.decline();
                            
                            let alert = NSAlert();
                            alert.icon = NSImage(named: NSImage.infoName);
                            alert.messageText = "Call failed";
                            alert.informativeText = "Negotiation of the call failed";
                            alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                                self.view.window?.orderOut(self);
                            })
                            return;
                        }
                        
                        print("set local description:", session.peerConnection?.localDescription?.sdp);
                        
                        let sdp = SDP(from: sdpAnswer!.sdp, creator: session.role);
                        
                        self.videoCapturer = self.videoCapturers[session.jid.resource!];
                        if self.videoCapturer != nil {
                            self.startVideoCapture(videoCapturer: self.videoCapturer!, completionHandler: {
                                print("Started!");
                                
                                self.session = session;
                                
                                _  = session.accept(contents: sdp!.contents, bundle: sdp!.bundle);
                            });
                        }
                    });
                })
            })
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
                    self.view.window?.orderOut(self);
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
                        that.view.window?.orderOut(self);
                    });
                }
            }
        }
        
        presences.forEach { (resource) in
            let session = JingleManager.instance.open(for: account, with: JID(jid, resource: resource), sid: nil, role: .initiator);
            
            session.delegate = self;
            
            let configuration = RTCConfiguration();
            configuration.sdpSemantics = .unifiedPlan;
            configuration.iceServers = [ RTCIceServer(urlStrings: ["stun://64.233.161.127:19302"]) ];
            configuration.bundlePolicy = .balanced;
            configuration.rtcpMuxPolicy = .require;

            let callConstraints = RTCMediaConstraints(mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveAudio: withAudio ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse, kRTCMediaConstraintsOfferToReceiveVideo: withVideo ? kRTCMediaConstraintsValueTrue : kRTCMediaConstraintsValueFalse], optionalConstraints: nil);
            session.peerConnection = JingleManager.instance.connectionFactory.peerConnection(with: configuration, constraints: callConstraints, delegate: session);
            
            self.initializeMedia(for: session, audio: withAudio, video: withVideo) {
                session.peerConnection?.offer(for: callConstraints, completionHandler: { (sdp, error) in
                    if sdp != nil && error == nil {
                        print("setting local description:", sdp!.sdp);
                        session.peerConnection?.setLocalDescription(sdp!, completionHandler: { (error) in
                            guard error == nil else {
                                finisher();
                                return;
                            }
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
    
    var videoSource: RTCVideoSource?;
    
    // this may be called multiple times, needs to handle that with video capture!!!
    func initializeMedia(for session: JingleManager.Session, audio: Bool, video: Bool, completionHandler: @escaping ()->Void) {
        DispatchQueue.main.async {
            if (session.peerConnection?.configuration.sdpSemantics ?? RTCSdpSemantics.planB) == RTCSdpSemantics.unifiedPlan {
                // send audio?
                if audio {
                    session.peerConnection?.add(JingleManager.instance.connectionFactory.audioTrack(withTrackId: "RTCaS0"), streamIds: ["RTCmS"]);
                }
                
                // send video?
                if video {
                    if  let device = RTCCameraVideoCapturer.captureDevices().first {
                        let videoSource = JingleManager.instance.connectionFactory.videoSource();
                        self.videoSource = videoSource;
                        print("video source:", videoSource);
                        
//                        var bestFormat: AVCaptureDevice.Format? = nil;
//                        var bestFrameRate: AVFrameRateRange? = nil;
//                        device.formats.forEach({ (format) in
//                            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
//                            print("checking format:", size.width, "x", size.height, ", type:", CMFormatDescriptionGetMediaSubType(format.formatDescription), "expected: FourCharCode")//, videoCapturer.preferredOutputPixelFormat());
//                            if CMFormatDescriptionGetMediaSubType(format.formatDescription) == 875704438 { //videoCapturer.preferredOutputPixelFormat() {
//                                format.videoSupportedFrameRateRanges.forEach({ (range) in
//                                    if (bestFrameRate == nil || bestFrameRate!.maxFrameRate < range.maxFrameRate) {
//                                        bestFrameRate = range;
//                                        bestFormat = format;
//                                    }
//                                });
//                            }
//                        });
//
//                        if bestFormat != nil && bestFrameRate != nil {
//                            try! device.lockForConfiguration();
//                            device.activeFormat = bestFormat!;
//                            device.unlockForConfiguration();
//                        }

                        
                        let videoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                        self.videoCapturers[session.jid.resource!] = videoCapturer;
                        let videoTrack = JingleManager.instance.connectionFactory.videoTrack(with: videoSource, trackId: "RTCvS0");
                        videoTrack.isEnabled = true;
                        print("added:", session.peerConnection?.add(videoTrack, streamIds: ["RTCmS"]));
                    }
                }
                completionHandler();
            } else {
//                let localStream = JingleManager.instance.createLocalStream(audio: audio, video: video);
//                session.peerConnection?.add(localStream);
//                if let videoTrack = localStream.videoTracks.first {
//                    self.didAdd(localVideoTrack: videoTrack);
//                }
            }
        }
    }
    
    fileprivate func startVideoCapture(videoCapturer: RTCCameraVideoCapturer, completionHandler: @escaping ()-> Void) {
        if let device = RTCCameraVideoCapturer.captureDevices().first {
            var bestFormat: AVCaptureDevice.Format? = nil;
            var bestFrameRate: AVFrameRateRange? = nil;
            RTCCameraVideoCapturer.supportedFormats(for: device).forEach({ (format) in
                let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
                print("checking format:", size.width, "x", size.height, ", type:", CMFormatDescriptionGetMediaSubType(format.formatDescription), "expected:", videoCapturer.preferredOutputPixelFormat());
                if CMFormatDescriptionGetMediaSubType(format.formatDescription) == videoCapturer.preferredOutputPixelFormat() {
                    format.videoSupportedFrameRateRanges.forEach({ (range) in
                        if (bestFrameRate == nil || bestFrameRate!.maxFrameRate < range.maxFrameRate) {
                            bestFrameRate = range;
                            bestFormat = format;
                        }
                    });
                }
            });
            
            if bestFormat != nil && bestFrameRate != nil {
                videoCapturer.startCapture(with: device, format: bestFormat!, fps: Int(25), completionHandler: { error in
                    
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
            if let videoCapturer = self.videoCapturers.removeValue(forKey: session.jid.resource!) {
                videoCapturer.stopCapture(completionHandler: nil);
            }
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                if self.session == nil && self.sessionsInProgress.isEmpty {
                    let alert = NSAlert();
                    alert.messageText = "Call rejected!";
                    alert.informativeText = "Call was rejected by the recipient.";
                    alert.icon = NSImage(named: NSImage.infoName);
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        self.view.window?.orderOut(self);
                    });
                }
            } else if let sess = self.session {
                if sess.sid == session.sid && sess.jid == session.jid && sess.account == session.account {
                    self.session = nil;
                    
                    //self.videoCapturer?.stopCapture();
                    
                    let alert = NSAlert();
                    alert.messageText = "Call ended!";
                    alert.informativeText = "Call ended.";
                    alert.icon = NSImage(named: NSImage.infoName);
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        self.view.window?.orderOut(self);
                    });
                }
            }
        }
    }
    
    func sessionAccepted(session: JingleManager.Session) {
        DispatchQueue.main.async {
            if let idx = self.sessionsInProgress.firstIndex(of: session) {
                self.sessionsInProgress.remove(at: idx);
                self.session = session;
                self.sessionsInProgress.forEach({ (sess) in
                    _ = sess.terminate();
                })
                self.videoCapturer = self.videoCapturers[session.jid.resource!];
//                if let videoSource = (session.peerConnection?.transceivers.first(where: { (trans) -> Bool in
//                    return trans.mediaType == .video && (trans.direction == .sendOnly || trans.direction == .sendRecv)
//                })?.sender.track as? RTCVideoTrack)?.source {
//                    self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                    if self.videoCapturer != nil {
                        self.startVideoCapture(videoCapturer: self.videoCapturer!, completionHandler: {
                            print("started!");
                        });
                    }
//                }
            }
        }
    }
}
