//
//  JingleManager
//  BeagleIM
//
//  Created by Andrzej Wójcik on 19/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift
import WebRTC

class JingleManager: XmppServiceEventHandler {

    static let instance = JingleManager();
    
    fileprivate var videoCapturer: RTCCameraVideoCapturer?;
    
    fileprivate let connectionFactory = { () -> RTCPeerConnectionFactory in
        RTCPeerConnectionFactory.initialize();
        return RTCPeerConnectionFactory();
    }();
    
    let events: [Event] = [JingleModule.JingleEvent.TYPE];
    
    fileprivate var connections: [Session] = [];
    
    fileprivate let dispatcher = QueueDispatcher(label: "jingleEventHandler");
    
    func session(for account: BareJID, with jid: JID, sid: String) -> Session? {
        return dispatcher.sync {
            return connections.first(where: {(sess) -> Bool in
                return sess.sid == sid && sess.account == account && sess.jid == jid;
            });
        }
    }
    
    fileprivate func session(peerConnection: RTCPeerConnection) -> Session? {
        return dispatcher.sync {
            return connections.first(where: {(sess) -> Bool in
                return sess.peerConnection == peerConnection;
            })
        }
    }

    fileprivate func open(for account: BareJID, with jid: JID, sid: String, role: Jingle.Content.Creator) -> Session {
        return dispatcher.sync {
            let session = Session(account: account, jid: jid, sid: sid, role: role);
            self.connections.append(session);
            return session;
        }
    }

//    fileprivate func open(session jingleSession: Jingle.Session, role: Jingle.Content.Creator) -> Session {
//        return dispatcher.sync {
//            let session = Session(jingleSession: jingleSession, role: role);
//            self.connections.append(session);
//            return session;
//        }
//    }
    
    fileprivate func close(for account: BareJID, with jid: JID, sid: String) -> Session? {
        return dispatcher.sync {
            guard let idx = self.connections.firstIndex(where: { sess -> Bool in
                return sess.sid == sid && sess.account == account && sess.jid == jid;
            }) else {
                return nil;
            }
            let session =  self.connections.remove(at: idx);
            session.terminate();
            return session;
        }
    }
    
    fileprivate func close(session: Session) {
        dispatcher.async {
            guard let idx = self.connections.firstIndex(of: session) else {
                return;
            }
            let session = self.connections.remove(at: idx);
            session.terminate();
        }
    }
    
    func handle(event: Event) {
        dispatcher.async {
            switch event {
            case let e as JingleModule.JingleEvent:
                switch e.action! {
                case .sessionInitiate:
                    self.sessionInitiated(event: e);
                case .transportInfo:
                    self.transportInfo(event: e);
                default:
                    break;
                }
                break;
            default:
                break;
            }
        }
    }
    
    func initiateSession(for account: BareJID, with jid: JID, withAudio: Bool, withVideo: Bool, completionHandler: @escaping (Session?, Error?)->Void) {
        let configuration = RTCConfiguration();
        configuration.iceServers = [ RTCIceServer(urlStrings: ["stun://64.233.161.127:19302"]) ];

        let session = Session(account: account, jid: jid, role: .initiator);
        let callConstraints = RTCMediaConstraints(mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveAudio: "true", kRTCMediaConstraintsOfferToReceiveVideo: "false"], optionalConstraints: nil);
        let peerConnection = self.connectionFactory.peerConnection(with: configuration, constraints: callConstraints, delegate: session);
        let localStream = self.createLocalStream(audio: withAudio, video: withVideo);
        peerConnection.add(localStream);
        
        peerConnection.offer(for: callConstraints, completionHandler: { (sdp, error) in
            if let error = error {
                completionHandler(nil, error);
            } else {
                let tmp = SDP(from: sdp!.sdp, creator: .initiator);
                session.peerConnection = peerConnection;
                if (session.initiate(sid: tmp!.sid, contents: tmp!.contents, bundle: tmp!.bundle)) {
                    self.connections.append(session);
                    completionHandler(session, nil);
                } else {
                    completionHandler(nil, nil);
                }
            }
        })
    }
    
    func sessionInitiated(event e: JingleModule.JingleEvent) {
        guard let content = e.contents.first, let description = content.description as? Jingle.RTP.Description else {
            return;
        }
        
        let session = open(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid, role: .responder);
        
        guard let client = session.client else {
            close(session: session);
            return;
        }
        
        DispatchQueue.main.async {
            let name = client.rosterStore?.get(for: e.initiator!.withoutResource)?.name ?? e.initiator!.bareJid.stringValue;
            
            let alert = Alert();
            alert.messageText = "Incoming call from \(name)";
            //alert.icon = NSImage(named: NSImage.)
            alert.informativeText = "Do you want to accept this call?"
            
            alert.addButton(withTitle: "Accept");
            alert.addButton(withTitle: "Deny");
            
            //alert.styleMask = [NSWindow.StyleMask.borderless, NSWindow.StyleMask.hudWindow ];
            
            alert.run(completionHandler: { (response) in
                let accept = response == NSApplication.ModalResponse.alertFirstButtonReturn;
                
                if accept {
                    session.initiated();
                    let configuration = RTCConfiguration();
                    configuration.iceServers = [ RTCIceServer(urlStrings: ["stun://64.233.161.127:19302"]) ];
                    configuration.bundlePolicy = .maxBundle;
                    configuration.rtcpMuxPolicy = .require;
                    
                    let callConstraints = RTCMediaConstraints(mandatoryConstraints: [kRTCMediaConstraintsOfferToReceiveAudio: "true", kRTCMediaConstraintsOfferToReceiveVideo: "true"], optionalConstraints: nil);
                    session.peerConnection = self.connectionFactory.peerConnection(with: configuration, constraints: callConstraints, delegate: session);
                    
                    let localStream = self.createLocalStream(audio: true, video: true);
                    session.peerConnection?.add(localStream);
                    
                    // add support for groups directly in jingle element...
//                    <group semantics='BUNDLE' xmlns='urn:xmpp:jingle:apps:grouping:0'>
//                    <content name='audio'/>
//                    </group>
                    
                    let offer = SDP(sid: e.sid!, contents: e.contents, bundle: e.bundle).toString();
                    let sessDesc = RTCSessionDescription(type: .offer, sdp: offer);
                    session.peerConnection?.setRemoteDescription(sessDesc, completionHandler: { (error) in
                        guard error == nil else {
                            self.close(session: session);
                            print("closed due to invalid offer:", error, ", ", offer);
                            return;
                        }
                        
                        // add remote ice candidates???
                        
                        // implement the rest of the handling process...
                        // or is it done??
                        session.remoteDescriptionSet();
                        
                        session.peerConnection?.answer(for: callConstraints, completionHandler: { (sdpAnswer, error) in
                            guard error == nil else {
                                self.close(session: session);
                                return;
                            }
                            session.peerConnection?.setLocalDescription(sdpAnswer!, completionHandler: { [weak self] (error) in
                                guard error == nil else {
                                    self?.close(session: session);
                                    return;
                                }
                            });
                            
                            let sdp = SDP(from: sdpAnswer!.sdp, creator: content.creator);
                            _  = session.accept(contents: sdp!.contents, bundle: sdp!.bundle);
                        })
                    });
                } else {
                    _ = session.decline();
                    self.close(session: session);
                }
            })
        }
    }
    
    func sessionAccepted(event e: JingleModule.JingleEvent) {
        guard let session = session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
        
        let sessDesc = RTCSessionDescription(type: .offer, sdp: SDP(sid: e.sid!, contents: e.contents, bundle: e.bundle).toString());
        session.peerConnection?.setRemoteDescription(sessDesc, completionHandler: { (error) in
            guard error == nil else {
                // for now we are closing but maybe we should send content-remove or content-modify instead....
                self.close(session: session);
                return;
            }
            session.remoteDescriptionSet();
            session.accepted();
        });
    }
    
    func sessionTerminated(event e: JingleModule.JingleEvent) {
        guard let session = close(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
    }
    
    func transportInfo(event e: JingleModule.JingleEvent) {
        print("processing transport info");
        
        // add support for multiple contents...
        guard let content = e.contents.first, let transport = content.transports.first as? Jingle.Transport.ICEUDPTransport else {
            return;
        }
        
        guard let session = self.session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
        
        transport.candidates.forEach { (candidate) in
            session.addCandidate(candidate, for: content.name);
        }
    }
    
    func createLocalStream(audio: Bool, video: Bool) -> RTCMediaStream {
        let localStream = self.connectionFactory.mediaStream(withStreamId: "RTCmS");
        if video {
            let videoSource = self.connectionFactory.videoSource();
            if self.videoCapturer == nil {
                self.videoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                //if let device = AVCaptureDevice.default(for: .video) {
                if let device = RTCCameraVideoCapturer.captureDevices().first {
                    var bestFormat: AVCaptureDevice.Format? = nil;
                    var bestFrameRate: AVFrameRateRange? = nil;
                    device.formats.forEach({ (format) in
                        if CMFormatDescriptionGetMediaSubType(format.formatDescription) == videoCapturer!.preferredOutputPixelFormat() {
                            format.videoSupportedFrameRateRanges.forEach({ (range) in
                                if (bestFrameRate == nil || bestFrameRate!.maxFrameRate < range.maxFrameRate) {
                                    bestFrameRate = range;
                                    bestFormat = format;
                                }
                            });
                        }
                    });
                    
                    self.videoCapturer!.startCapture(with: device, format: bestFormat!, fps: Int(fmin(bestFrameRate!.maxFrameRate, 30.0)));
                }
            }
            let videoTrack = self.connectionFactory.videoTrack(with: videoSource, trackId: "RTCvS0");
            videoTrack.isEnabled = true;
            localStream.addVideoTrack(videoTrack);
        }
        if audio {
            localStream.addAudioTrack(self.connectionFactory.audioTrack(withTrackId: "RTCaS0"));
        }
        return localStream;
    }
 
    class Session: NSObject, RTCPeerConnectionDelegate {
        
        fileprivate(set) weak var client: XMPPClient?;
        fileprivate(set) var state: State = .created {
            didSet {
                print("RTPSession:", self, "state:", state);
            }
        }

        fileprivate var jingleModule: JingleModule? {
            guard let client = self.client, client.state == .connected else {
                return nil;
            }
            return client.modulesManager.getModule(JingleModule.ID);
        }
        
        let account: BareJID;
        let jid: JID;
        var peerConnection: RTCPeerConnection?;
        fileprivate(set) var sid: String;
        let role: Jingle.Content.Creator;
        
        var remoteCandidates: [[String]] = [];
        
        init(account: BareJID, jid: JID, sid: String? = nil, role: Jingle.Content.Creator) {
            self.account = account;
            self.client = XmppService.instance.getClient(for: account);
            self.jid = jid;
            self.sid = sid ?? "";
            self.role = role;
            self.state = sid == nil ? .created : .negotiating;
        }
        
        func initiate(sid: String, contents: [Jingle.Content], bundle: [String]?) -> Bool {
            self.sid = sid;
            guard let client = self.client, let accountJid = ResourceBinderModule.getBindedJid(client.sessionObject), let jingleModule = self.jingleModule else {
                return false;
            }
            
            self.state = .negotiating;
            jingleModule.initiateSession(to: jid, sid: sid, initiator: accountJid, contents: contents, bundle: bundle) { (error) in
                if (error != nil) {
                    self.onError(error!);
                }
            }
            return true;
        }
        
        func initiated() {
            self.state = .negotiating;
        }
        
        func accept(contents: [Jingle.Content], bundle: [String]?) -> Bool {
            guard let client = self.client, let accountJid = ResourceBinderModule.getBindedJid(client.sessionObject), let jingleModule: JingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.acceptSession(with: jid, sid: sid, initiator: role == .initiator ? accountJid : jid, contents: contents, bundle: bundle) { (error) in
                if (error != nil) {
                    self.onError(error!);
                } else {
                    self.state = .connecting;
                }
            }
            
            return true;
        }
        
        func accepted() {
            self.state = .connecting;
        }
        
        func decline() -> Bool {
            self.state = .disconnected;
            guard let jingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.declineSession(with: jid, sid: sid);
            return true;
        }
        
        func transportInfo(contentName: String, creator: Jingle.Content.Creator, transport: JingleTransport) -> Bool {
            guard let jingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.transportInfo(with: jid, sid: sid, contents: [Jingle.Content(name: contentName, creator: creator, description: nil, transports: [transport])]);
            return true;
        }

        func terminate() -> Bool {
            guard let jingleModule: JingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.terminateSession(with: jid, sid: sid);
            return true;
        }
        
        func addCandidate(_ candidate: Jingle.Transport.ICEUDPTransport.Candidate, for contentName: String) {
            let sdp = candidate.toSDP();

            guard let remoteDesc = peerConnection?.remoteDescription else {
                self.remoteCandidates.append([contentName, sdp]);
                return;
            }
            self.addCandidate(sdp: sdp, for: contentName);
        }
        
        func remoteDescriptionSet() {
            let tmp = remoteCandidates;
            remoteCandidates.removeAll();
            tmp.forEach { (arr) in
                self.addCandidate(sdp: arr[1], for: arr[0]);
            }
        }
        
        fileprivate func onError(_ errorCondition: ErrorCondition) {
            
        }
        
        fileprivate func addCandidate(sdp: String, for contentName: String) {
            guard let idx = peerConnection?.remoteDescription?.sdp.split(separator: "\r\n").firstIndex(where: { (s) -> Bool in
                return s.starts(with: "m=\(contentName) ");
            }) else {
                return;
            }
            // if peer connection is nil we should queue those candidates...
            peerConnection?.add(RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: contentName));
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        }
        
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
            if newState == .connected {
                self.state = .connected;
            } else if (state == .connected && (newState == .disconnected || newState == .failed)) {
                self.state = .disconnected;
                _ = self.terminate();
            }
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp) else {
                return;
            }
            guard let mid = candidate.sdpMid else {
                return;
            }
            
            guard let desc = peerConnection.localDescription, let sdp = SDP(from: desc.sdp, creator: role) else {
                return;
            }
            
            guard let content = sdp.contents.first(where: { c -> Bool in
                return c.name == mid;
            }), let transport = content.transports.first(where: {t -> Bool in
                return (t as? Jingle.Transport.ICEUDPTransport) != nil;
            }) as? Jingle.Transport.ICEUDPTransport else {
                return;
            }
            
            if (!transportInfo(contentName: mid, creator: role, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]))) {
                self.onError(.remote_server_timeout);
            }
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        }

        enum State {
            case created
            case negotiating
            case connecting
            case connected
            case disconnected
        }
    }
}

extension String {
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        return String((0...length-1).map{ _ in letters.randomElement()! });
    }
}
