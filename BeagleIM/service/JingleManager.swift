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
    
    let connectionFactory = { () -> RTCPeerConnectionFactory in
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

    func open(for account: BareJID, with jid: JID, sid: String?, role: Jingle.Content.Creator) -> Session {
        return dispatcher.sync {
            let session = Session(account: account, jid: jid, sid: sid, role: role);
            self.connections.append(session);
            return session;
        }
    }
    
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
                case .sessionAccept:
                    self.sessionAccepted(event: e);
                case .transportInfo:
                    self.transportInfo(event: e);
                case .sessionTerminate:
                    self.sessionTerminated(event: e);
                default:
                    break;
                }
                break;
            default:
                break;
            }
        }
    }
    
    enum ContentType {
        case audio
        case video
        case filetransfer
    }
    
    func support(for jid: JID, on account: BareJID) -> Set<ContentType> {
        guard let client = XmppService.instance.getClient(for: account), let presenceStore = client.presenceStore else {
            return [];
        }
        
        return Set([.audio, .video]);
        
        var features: [String] = [];
        
        if jid.resource == nil {
            presenceStore.getPresences(for: jid.bareJid)?.values.forEach({ (p) in
                guard let node = p.capsNode, let f = DBCapabilitiesCache.instance.getFeatures(for: node) else {
                    return;
                }
                features.append(contentsOf: f);
            })
        } else {
            guard let node = presenceStore.getPresence(for: jid)?.capsNode, let f = DBCapabilitiesCache.instance.getFeatures(for: node) else {
                return [];
            }
            features.append(contentsOf: f);
        }
        
        var support: [ContentType] = [];
        
        // check jingle and supported transports...
        guard features.contains("urn:xmpp:jingle:1") && features.contains("urn:xmpp:jingle:transports:ice-udp:1") && features.contains("urn:xmpp:jingle:apps:dtls:0") && features.contains("urn:xmpp:jingle:apps:rtp:1") else {
            return Set(support);
        }
        
        if features.contains("urn:xmpp:jingle:apps:rtp:audio") {
            support.append(.audio);
        }
        
        if features.contains("urn:xmpp:jingle:apps:rtp:video") {
            support.append(.video);
        }
        
        if features.contains("urn:xmpp:jingle:apps:file-transfer:3") {
            support.append(.filetransfer);
        }
        
        return Set(support);
    }
    
    func sessionInitiated(event e: JingleModule.JingleEvent) {
        
        guard let content = e.contents.first, let description = content.description as? Jingle.RTP.Description else {
            return;
        }
        
        let session = open(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid, role: .responder);
        
        if !VideoCallController.accept(session: session, sdpOffer: SDP(sid: e.sid!, contents: e.contents, bundle: e.bundle)) {
            session.terminate();
        }
    }
    
    func sessionAccepted(event e: JingleModule.JingleEvent) {
        guard let session = session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
        
        session.accepted(sdpAnswer: SDP(sid: e.sid!, contents: e.contents, bundle: e.bundle));
    }
    
    func sessionTerminated(event e: JingleModule.JingleEvent) {
        guard let session = session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
        session.terminate();
    }
    
    func transportInfo(event e: JingleModule.JingleEvent) {
        print("processing transport info");
        guard let session = self.session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
        
        e.contents.forEach { (content) in
            content.transports.forEach({ (trans) in
                if let transport = trans as? Jingle.Transport.ICEUDPTransport {
                    transport.candidates.forEach({ (candidate) in
                        session.addCandidate(candidate, for: content.name);
                    })
                }
            })
        }
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
        weak var delegate: VideoCallController?;
        fileprivate(set) var sid: String;
        let role: Jingle.Content.Creator;
        
        var remoteCandidates: [[String]]? = [];
        var localCandidates: [RTCIceCandidate]? = [];
                
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
        
        func accepted(sdpAnswer: SDP) {
            self.state = .connecting;
            delegate?.sessionAccepted(session: self, sdpAnswer: sdpAnswer);
        }
        
        func decline() -> Bool {
            self.state = .disconnected;
            guard let jingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.declineSession(with: jid, sid: sid);
            
            self.delegate?.sessionTerminated(session: self);
            peerConnection?.close();
            peerConnection = nil;
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
            
            self.delegate?.sessionTerminated(session: self);
            peerConnection?.close();
            peerConnection = nil;
            
            JingleManager.instance.close(session: self);
            return true;
        }
        
        func addCandidate(_ candidate: Jingle.Transport.ICEUDPTransport.Candidate, for contentName: String) {
            let sdp = candidate.toSDP();

            if remoteCandidates != nil {
                remoteCandidates?.append([contentName, sdp]);
            } else {
                self.addCandidate(sdp: sdp, for: contentName);
            }
        }
        
        func remoteDescriptionSet() {
            JingleManager.instance.dispatcher.async {
                if let tmp = self.remoteCandidates {
                    self.remoteCandidates = nil;
                    tmp.forEach { (arr) in
                        self.addCandidate(sdp: arr[1], for: arr[0]);
                    }
                }
            }
        }
        
        fileprivate func onError(_ errorCondition: ErrorCondition) {
            
        }
        
        fileprivate func addCandidate(sdp: String, for contentName: String) {
            DispatchQueue.main.async {
                guard let lines = self.peerConnection?.remoteDescription?.sdp.split(separator: "\r\n").map({ (s) -> String in
                    return String(s);
                }) else {
                    return;
                }
                
                let contents = lines.filter { (line) -> Bool in
                    return line.starts(with: "a=mid:");
                };
                
                let idx = contents.firstIndex(of: "a=mid:\(contentName)") ?? lines.filter({ (line) -> Bool in
                    return line.starts(with: "m=")
                }).firstIndex(where: { (line) -> Bool in
                    return line.starts(with: "m=\(contentName) ");
                }) ?? 0;
                
                print("adding candidate for:", idx, "name:", contentName, "sdp:", sdp)
                self.peerConnection?.add(RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: contentName));
            }
        }

        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
            print("signaling state:", stateChanged.rawValue);
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
//            if stream.videoTracks.count > 0 {
//                self.delegate?.didAdd(remoteVideoTrack: stream.videoTracks[0]);
//            }
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
            if transceiver.direction == .recvOnly || transceiver.direction == .sendRecv {
                if transceiver.mediaType == .video {
                    print("got video transceiver");
                    guard let track = transceiver.receiver.track as? RTCVideoTrack else {
                        return;
                    }
                    self.delegate?.didAdd(remoteVideoTrack: track)
                }
            }
            if transceiver.direction == .sendOnly || transceiver.direction == .sendRecv {
                if transceiver.mediaType == .video {
                    guard let track = transceiver.sender.track as? RTCVideoTrack else {
                        return;
                    }
                    self.delegate?.didAdd(localVideoTrack: track);
                }
            }
        }
        
        func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
            print("ice connection state:", newState.rawValue);
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
            print("generated candidate for:", candidate.sdpMid, ", index:", candidate.sdpMLineIndex, "full SDP:", (peerConnection.localDescription?.sdp ?? ""));

            JingleManager.instance.dispatcher.async {
                if self.localCandidates == nil {
                    self.sendLocalCandidate(candidate);
                } else {
                    self.localCandidates?.append(candidate);
                }
            }
        }
        
        func localDescriptionSet() {
            JingleManager.instance.dispatcher.async {
                if let tmp = self.localCandidates {
                    self.localCandidates = nil;
                    tmp.forEach({ (candidate) in
                        self.sendLocalCandidate(candidate);
                    })
                }
            }
        }
        
        fileprivate func sendLocalCandidate(_ candidate: RTCIceCandidate) {
            print("sending candidate for:", candidate.sdpMid, ", index:", candidate.sdpMLineIndex, "full SDP:", (self.peerConnection?.localDescription?.sdp ?? ""));
           
            guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp), let peerConnection = self.peerConnection else {
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
            
            DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + 0.1) {
                if (!self.transportInfo(contentName: mid, creator: self.role, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]))) {
                    self.onError(.remote_server_timeout);
                }
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
