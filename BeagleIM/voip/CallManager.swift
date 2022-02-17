//
// CallManager.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import Network
import WebRTC
import TigaseSwift
import Combine
import TigaseLogging

class CallManager {
    
    static let instance = CallManager();

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "jingle")
    private let dispatcher = QueueDispatcher(label: "callManager");
    
    func reportIncomingCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        call.session = JingleManager.instance.session(forCall: call);
        dispatcher.async {
            call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
            call.changeState(.ringing);
            
            guard !MeetManager.instance.reportIncoming(call: call) else {
                completionHandler(.success(Void()));
                return;
            }
            
            self.checkMediaAvailability(forCall: call, completionHandler: { result in
                switch result {
                case .success(_):
                    VideoCallController.open(completionHandler: { controller in
                        call.delegate = controller;
                    })
                    completionHandler(.success(Void()));
                case .failure(let err):
                    call.session = nil;
                    call.reset();
                    completionHandler(.failure(err));
                }
            });
        }
    }
    
    func reportOutgoingCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        dispatcher.async {
            call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
            call.changeState(.ringing);
            VideoCallController.open(completionHandler: { controller in
                call.delegate = controller;
            })
            self.checkMediaAvailability(forCall: call, completionHandler: { result in
                switch result {
                case .success(_):
                    call.initiateOutgoingCall(completionHandler: { result in
                        switch result {
                        case .success(_):
                            completionHandler(.success(Void()));
                        case .failure(let err):
                            completionHandler(.failure(err));
                            call.reset();
                        }
                    });
                case .failure(let err):
                    completionHandler(.failure(err));
                    call.reset();
                }
            });
        }
    }
    
    func checkMediaAvailability(forCall call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        var errors: Bool = false;
        let group = DispatchGroup();
        group.enter();
        for media in call.media {
            group.enter();
            self.checkAccesssPermission(media: media, completionHandler: { result in
                self.dispatcher.async {
                    switch result {
                    case .success(_):
                        break;
                    case .failure(_):
                        errors = true;
                    }
                    group.leave();
                }
            })
        }
        group.leave();
        group.notify(queue: self.dispatcher.queue, execute: {
            completionHandler(errors ? .failure(ErrorCondition.forbidden) : .success(Void()));
        })
    }
    
    func checkAccesssPermission(media: Call.Media, completionHandler: @escaping(Result<Void,Error>)->Void) {
        CaptureDeviceManager.requestAccess(for: media.avmedia, completionHandler: { result in
            DispatchQueue.main.async {
                completionHandler(result ? .success(Void()) : .failure(ErrorCondition.forbidden));
            }
        });
    }
    
    private func initializeCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        call.initiateWebRTC(completionHandler: completionHandler);
    }
    
}

class Call: NSObject, JingleSessionActionDelegate {
    static func == (lhs: Call, rhs: Call) -> Bool {
        return lhs.account == rhs.account && lhs.jid == rhs.jid && lhs.sid == rhs.sid;
    }
    
    override func isEqual(_ object: Any?) -> Bool {
        guard let rhs = object as? Call else {
            return false;
        }
        return account == rhs.account && jid == rhs.jid && sid == rhs.sid;
    }
    
    
    let account: BareJID;
    let jid: BareJID;
    let sid: String;
    let direction: Direction;
    let media: [Media]
    
    private(set) var state: State = .new;

    var webrtcSid: String?;
    
    private(set) var currentConnection: RTCPeerConnection?;
    
    weak var delegate: CallDelegate? {
        didSet {
            delegate?.callDidStart(self);
        }
    }
    fileprivate(set) var session: JingleManager.Session? {
        didSet {
            session?.$state.removeDuplicates().sink(receiveValue: { [weak self] state in
                guard let that = self else {
                    return;
                }
                switch state {
                case .accepted:
                    switch that.direction {
                    case .incoming:
                        break;
                    case .outgoing:
                        that.acceptedOutgingCall();
                    }
                case .terminated:
                    that.sessionTerminated()
                default:
                    break;
                }
            }).store(in: &cancellables);
        }
    }

    private var establishingSessions: [JingleManager.Session] = [];
    
    private var localCandidates: [RTCIceCandidate] = [];
    
    private(set) var localVideoSource: RTCVideoSource?;
    private(set) var localVideoTrack: RTCVideoTrack?;
    private(set) var localAudioTrack: RTCAudioTrack?;
    private(set) var localCapturer: VideoCapturer?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Call");
    
    var currentCapturerDevice: VideoCaptureDevice? {
        return localCapturer?.currentDevice;
    }
    
    init(account: BareJID, with jid: BareJID, sid: String, direction: Direction, media: [Media]) {
        self.account = account;
        self.jid = jid;
        self.media = media;
        self.sid = sid;
        self.direction = direction;
    }
    
    func reset() {
        DispatchQueue.main.async {
            if self.localCapturer != nil {
                self.localCapturer?.stopCapture(completionHandler: {
                    self.localCapturer = nil;
                })
            }
            self.currentConnection?.close();
            self.currentConnection = nil;
            self.localVideoTrack = nil;
            self.localAudioTrack = nil;
            self.localVideoSource = nil;
            self.delegate?.callDidEnd(self);
            _ = self.session?.terminate();
            self.session = nil;
            self.delegate = nil;
            for session in self.establishingSessions {
                session.terminate();
            }
            self.establishingSessions.removeAll();
            self.state = .ended;
        }
    }

    enum Media: String {
        case audio
        case video
        
        static func from(string: String?) -> Media? {
            guard let v = string else {
                return nil;
            }
            return Media(rawValue: v);
        }
        
        var avmedia: AVMediaType {
            switch self {
            case .audio:
                return .audio;
            case .video:
                return .video;
            }
        }
    }

    enum Direction {
        case incoming
        case outgoing
    }
    
    enum State {
        case new
        case ringing
        case connecting
        case connected
        case ended
    }

    func initiateOutgoingCall(with callee: JID? = nil, completionHandler: @escaping (Result<Void,Error>)->Void) {
        guard let client = XmppService.instance.getClient(for: account) else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        }
        var withJingle: [JID] = [];
        var withJMI: [JID] = [];

        if let jid = callee {
            withJingle.append(jid);
        } else {
            let presences = PresenceStore.instance.presences(for: jid, context: client);
            guard !presences.isEmpty || Settings.ignoreJingleSupportCheck else {
                completionHandler(.failure(ErrorCondition.item_not_found));
                return;
            };
            for presence in presences {
                if let jid = presence.from, let capsNode = presence.capsNode {
                    if let features = DBCapabilitiesCache.instance.getFeatures(for: capsNode) {
                        if features.contains(JingleModule.XMLNS) && features.contains(Jingle.Transport.ICEUDPTransport.XMLNS) && features.contains("urn:xmpp:jingle:apps:rtp:audio") {
                            withJingle.append(jid);
                            if features.contains(JingleModule.MESSAGE_INITIATION_XMLNS) {
                                withJMI.append(jid);
                            }
                        }
                    }
                }
            }
            guard !withJingle.isEmpty || Settings.ignoreJingleSupportCheck else {
                completionHandler(.failure(ErrorCondition.item_not_found));
                return;
            }
        }
        
        self.changeState(.ringing);
        initiateWebRTC(completionHandler: { result in
            switch result {
            case .success(_):
                completionHandler(.success(Void()));
                if withJMI.count == withJingle.count {
                    let session = JingleManager.instance.open(for: client, with: JID(self.jid), sid: self.sid, role: .initiator, initiationType: .message);
                    self.session = session;
                    _ = session.initiate(descriptions: self.media.map({ Jingle.MessageInitiationAction.Description(xmlns: "urn:xmpp:jingle:apps:rtp:1", media: $0.rawValue) }));
                } else {
                    // we need to establish multiple 1-1 sessions...
                    guard let peerConnection = self.currentConnection else {
                        completionHandler(.failure(ErrorCondition.internal_server_error));
                        return;
                    }
                    self.generateOfferAndSet(peerConnection: peerConnection, creatorProvider: { _ in Jingle.Content.Creator.initiator }, localRole: .initiator, completionHandler: { result in
                        switch result {
                        case .failure(_):
                            self.reset();
                        case .success(let sdp):
                            DispatchQueue.main.async {
                                for jid in withJingle {
                                    let session = JingleManager.instance.open(for: client, with: jid, sid: self.sid, role: .initiator, initiationType: .iq);
                                    session.$state.removeDuplicates().receive(on: DispatchQueue.main).sink(receiveValue: { state in
                                        switch state {
                                        case .accepted:
                                            guard self.session == nil else {
                                                session.terminate();
                                                return;
                                            }
                                            for sess in self.establishingSessions {
                                                if sess.account == session.account && sess.jid == session.jid && sess.sid == session.sid {
                                                } else {
                                                    sess.terminate();
                                                }
                                            }
                                            self.establishingSessions.removeAll();
                                            self.session = session;
                                            self.state = .connecting;
                                            self.connectRemoteSDPPublishers(session: session);
                                            self.sendLocalCandidates();
                                        case .terminated:
                                            if let idx = self.establishingSessions.firstIndex(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid }) {
                                                self.establishingSessions.remove(at: idx);
                                            }
                                            if self.establishingSessions.isEmpty && self.session == nil {
                                                self.reset();
                                            }
                                        default:
                                            break;
                                        }
                                    }).store(in: &self.cancellables);
                                    self.establishingSessions.append(session);
                                    _ = session.initiate(contents: sdp.contents, bundle: sdp.bundle);
                                }
                            }
                        }
                    })
                }
            case .failure(let err):
                completionHandler(.failure(err));
            }
        })
    }
        
    private func acceptedOutgingCall() {
        guard let session = session, session.initiationType == .message, state == .ringing, let peerConnection = currentConnection else {
            return;
        }
        changeState(.connecting);
        generateOfferAndSet(peerConnection: peerConnection, creatorProvider: session.contentCreator(of:), localRole: session.role, completionHandler: { result in
            switch result {
            case .success(let sdp):
                guard let session = self.session else {
                    self.reset();
                    return
                }
                self.connectRemoteSDPPublishers(session: session);
                _ = session.initiate(contents: sdp.contents, bundle: sdp.bundle);
            case .failure(_):
                self.reset();
            }
        });
    }
    
    private func connectRemoteSDPPublishers(session: JingleManager.Session) {
        session.setDelegate(self);
    }
            
    static let VALID_SERVICE_TYPES = ["stun", "stuns", "turn", "turns"];
    
    func initiateWebRTC(completionHandler: @escaping (Result<Void,Error>)->Void) {
        if let module: ExternalServiceDiscoveryModule = XmppService.instance.getClient(for: self.account)?.module(.externalServiceDiscovery), module.isAvailable {
            module.discover(from: nil, type: nil, completionHandler: { [weak self] result in
                switch result {
                case .success(let services):
                    var servers: [RTCIceServer] = [];
                    for service in services {
                        if let server = service.rtcIceServer() {
                            servers.append(server);
                        }
                    }
                    self?.initiateWebRTC(iceServers: servers, completionHandler: completionHandler);
                case .failure(_):
                    self?.initiateWebRTC(iceServers: [], completionHandler: completionHandler);
                }
            })
        } else {
            initiateWebRTC(iceServers: [], completionHandler: completionHandler);
        }
    }
    
    private func initiateWebRTC(iceServers: [RTCIceServer], completionHandler: @escaping (Result<Void,Error>)->Void) {
        // moved initialization to main queue to sync with a call to reset()
        DispatchQueue.main.async { [self] in
        self.currentConnection = VideoCallController.initiatePeerConnection(iceServers: iceServers, withDelegate: self);
        if self.currentConnection != nil {
            self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
            if let localAudioTrack = self.localAudioTrack {
                self.currentConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
            }
            if self.media.contains(.video) && CaptureDeviceManager.authorizationStatus(for: .video) == .authorized {
                let videoSource = VideoCallController.peerConnectionFactory.videoSource();
                self.localVideoSource = videoSource;
                let localVideoTrack = VideoCallController.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video-" + UUID().uuidString);
                self.localVideoTrack = localVideoTrack;
                
                if let device = VideoCaptureDevice.default {
                    self.startVideoCapturer(device: device, completionHandler: { _ in
                        print("video capture started!");
                    })
                    self.delegate?.call(self, didReceiveLocalVideoTrack: localVideoTrack);
                    self.currentConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                    completionHandler(.success(Void()));
                } else {
                    completionHandler(.failure(ErrorCondition.item_not_found));
                }
            } else {
                completionHandler(.success(Void()));
            }
        } else {
            completionHandler(.failure(ErrorCondition.internal_server_error));
        }
        }
    }
    
    func startVideoCapturer(device: VideoCaptureDevice, completionHandler: @escaping (Result<Void,Error>)->Void) {
        guard let localVideoSource = localVideoSource else {
            return
        }
 
        if let prevCapturer = localCapturer {
            prevCapturer.stopCapture {
                print("old capturer stopped!");
            }
        }
        
        localCapturer = device.capturer(for: localVideoSource);
        localCapturer?.startCapture(completionHandler: completionHandler);
    }

    func accept() {
        guard let session = self.session else {
            reset();
            return;
        }
        changeState(.connecting);
        initiateWebRTC(completionHandler: { result in
            switch result {
            case .success(_):
                guard self.currentConnection != nil else {
                    self.reject();
                    return;
                }
                session.accept();
                self.connectRemoteSDPPublishers(session: session);
            case .failure(_):
                // there was an error, so we should reject this call
                self.reject();
            }
        })
    }
    
    func reject() {
        guard let session = self.session else {
            reset();
            return;
        }
        session.decline();
        reset();
    }
    
    private var localSessionDescription: SDP?;
    private var remoteSessionDescription: SDP?;
    
    private let remoteSessionSemaphore = DispatchSemaphore(value: 1);
    
    public func received(action: JingleManager.Session.Action) {
        guard let peerConnection = self.currentConnection, let session = self.session else {
            return;
        }
    
        
        remoteSessionSemaphore.wait();
        
        if case let .transportAdd(candidate, contentName) = action {
            if let idx = remoteSessionDescription?.contents.firstIndex(where: { $0.name == contentName }) {
                peerConnection.add(RTCIceCandidate(sdp: candidate.toSDP(), sdpMLineIndex: Int32(idx), sdpMid: contentName));
            }
            remoteSessionSemaphore.signal();
            return;
        }
        
        let result = apply(action: action, on: self.remoteSessionDescription);
        
        guard let newSDP = result else {
            remoteSessionSemaphore.signal();
            return;
        }
        
        let prevLocalSDP = self.localSessionDescription;
        setRemoteDescription(newSDP, peerConnection: peerConnection, session: session, completionHandler: { result in
            self.remoteSessionSemaphore.signal();
            switch result {
            case .failure(let error):
                self.logger.debug("error setting remote description: \(error.localizedDescription)");
                self.reset();
            case .success(let localSDP):
                if let sdp = localSDP {
                    if prevLocalSDP != nil {
                        let changes = sdp.diff(from: prevLocalSDP!);
                        if let addSDP = changes[.add] {
                            _ = session.contentModify(action: .accept, contents: addSDP.contents, bundle: addSDP.bundle);
                        }
                        if let modifySDP = changes[.modify] {
                            // can we safely ignore this?
                        }
                    } else {
                        _ = session.accept(contents: sdp.contents, bundle: sdp.bundle)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                            self.sendLocalCandidates();
                        })
                    }
                }
                break;
            }
        });
    }
    
    private func apply(action: JingleManager.Session.Action, on prevSDP: SDP?) -> SDP? {
        switch action {
        case .contentSet(let newSDP):
            return newSDP;
        case .contentApply(let action, let diffSDP):
            switch action {
            case .add, .accept, .remove, .modify:
                return prevSDP?.applyDiff(action: action, diff: diffSDP);
            }
        case .transportAdd(_, _):
            return nil;
        case .sessionInfo(let infos):
            for info in infos {
                logger.debug("received session-info: \(String(describing: info))")
            }
            return nil;
        }
    }

    private func setRemoteDescription(_ remoteDescription: SDP, peerConnection: RTCPeerConnection, session: JingleSession, completionHandler: @escaping (Result<SDP?,Error>)->Void) {
        logger.debug("setting remote description: \(remoteDescription.toString(withSid: "", localRole: session.role, direction: .incoming))");
        peerConnection.setRemoteDescription(RTCSessionDescription(type: self.direction == .incoming ? .offer : .answer, sdp: remoteDescription.toString(withSid: self.webrtcSid!, localRole: session.role, direction: .incoming)), completionHandler: { err in
            guard let error = err else {
                self.remoteSessionDescription = remoteDescription;
                if peerConnection.signalingState == .haveRemoteOffer {
                    self.generateAnswerAndSet(peerConnection: peerConnection, creatorProvider: session.contentCreator(of:), localRole: session.role, completionHandler: { result in
                        switch result {
                        case .success(let localSDP):
                            completionHandler(.success(localSDP));
                        case .failure(let error):
                            completionHandler(.failure(error));
                        }
                    })
                } else {
                    completionHandler(.success(nil));
                }
                return;
            }
            completionHandler(.failure(error));
        });
    }
    
    private func generateOfferAndSet(peerConnection: RTCPeerConnection, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator, completionHandler: @escaping (Result<SDP,Error>)->Void) {
        logger.debug("generating offer");
        peerConnection.offer(for: VideoCallController.defaultCallConstraints, completionHandler: { sdpOffer, err in
            guard let error = err else {
                self.setLocalDescription(peerConnection: peerConnection, sdp: sdpOffer!, creatorProvider: creatorProvider, localRole: localRole, completionHandler: completionHandler);
                return;
            }
            completionHandler(.failure(error));
        });
    };
        
    private func generateAnswerAndSet(peerConnection: RTCPeerConnection, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator, completionHandler: @escaping (Result<SDP,Error>)->Void) {
        logger.debug("generating answer");
        peerConnection.answer(for: VideoCallController.defaultCallConstraints, completionHandler: { sdpAnswer, err in
            guard let error = err else {
                self.setLocalDescription(peerConnection: peerConnection, sdp: sdpAnswer!, creatorProvider: creatorProvider, localRole: localRole, completionHandler: completionHandler);
                return;
            }
            completionHandler(.failure(error));
        });
    }
    
    private func setLocalDescription(peerConnection: RTCPeerConnection, sdp localSDP: RTCSessionDescription, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator, completionHandler: @escaping (Result<SDP,Error>)->Void) {
        logger.debug("setting local description: \(localSDP.sdp)");
        peerConnection.setLocalDescription(localSDP, completionHandler: { err in
            guard let error = err else {
                guard let (sdp, _) = SDP.parse(sdpString: localSDP.sdp, creatorProvider: creatorProvider, localRole: localRole) else {
                    completionHandler(.failure(ErrorCondition.not_acceptable));
                    return;
                }
                self.localSessionDescription = sdp;
                completionHandler(.success(sdp));
                return;
            }
            completionHandler(.failure(error));
        });
    }
    
    func changeState(_ state: State) {
        self.state = state;
        self.delegate?.callStateChanged(self);
    }

    func muted(value: Bool) {
        self.localAudioTrack?.isEnabled = !value;
        self.localVideoTrack?.isEnabled = !value;
        let infos: [Jingle.SessionInfo] = self.localSessionDescription?.contents.filter({ $0.description?.media == "audio" || $0.description?.media == "video" }).map({ $0.name }).map({ value ? .mute(contentName: $0) : .unmute(contentName: $0) }) ?? [];
        if !infos.isEmpty {
            session?.sessionInfo(infos);
        }
    }
    
}

protocol CallDelegate: AnyObject {
    
    func callDidStart(_ sender: Call);
    func callDidEnd(_ sender: Call);
    
    func callStateChanged(_ sender: Call);
    
    func call(_ sender: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack);
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack, forStream stream: String, fromReceiver: String);
    
    //func call(_ sender: Call, goneLocalVideoTrack localTrack: RTCVideoTrack, forStream stream: String);
    func call(_ sender: Call, goneRemoteVideoTrack remoteTrack: RTCVideoTrack, fromReceiver: String);

    
}


extension Call: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        logger.debug("signaling state: \(stateChanged.rawValue)");
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
        
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        logger.debug("negotiation required");
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .disconnected:
            break;
            //self.reset();
        case .connected:
            DispatchQueue.main.async {
                self.changeState(.connected);
            }
        default:
            break;
        }
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        JingleManager.instance.dispatcher.async {
            self.localCandidates.append(candidate);
            self.sendLocalCandidates();
        }
    }
        
    private func sendLocalCandidates() {
        guard let session = self.session else {
            return;
        }
        for candidate in localCandidates {
            self.sendLocalCandidate(candidate, session: session);
        }
        self.localCandidates = [];
    }
    
    private func sendLocalCandidate(_ candidate: RTCIceCandidate, session: JingleManager.Session) {
        guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp) else {
            return;
        }
        guard let mid = candidate.sdpMid else {
            return;
        }
        guard let sdp = self.localSessionDescription else {
            return;
        }
        
        guard let content = sdp.contents.first(where: { c -> Bool in
            return c.name == mid;
        }), let transport = content.transports.first(where: {t -> Bool in
            return (t as? Jingle.Transport.ICEUDPTransport) != nil;
        }) as? Jingle.Transport.ICEUDPTransport else {
            return;
        }
        
        _ = session.transportInfo(contentName: mid, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]));
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
            
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        logger.debug("added receiver: \(rtpReceiver.receiverId)");
        if let track = rtpReceiver.track as? RTCVideoTrack, let stream = mediaStreams.first {
            let mid = peerConnection.transceivers.first(where: { $0.receiver.receiverId == rtpReceiver.receiverId })?.mid;
            logger.debug("added video track: \(track), \(peerConnection.transceivers.map({ "[\($0.mid) - stopped: \($0.isStopped), \($0.receiver.receiverId), \($0.direction.rawValue)]" }).joined(separator: ", "))");
            self.delegate?.call(self, didReceiveRemoteVideoTrack: track, forStream: mid ?? stream.streamId, fromReceiver: rtpReceiver.receiverId);
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove rtpReceiver: RTCRtpReceiver) {
        logger.debug("removed receiver: \(rtpReceiver.receiverId)")
        if let track = rtpReceiver.track as? RTCVideoTrack {
            logger.debug("removed video track: \(track)");
            self.delegate?.call(self, goneRemoteVideoTrack: track, fromReceiver: rtpReceiver.receiverId);
        }
    }
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if transceiver.direction == .recvOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                logger.debug("got video transceiver");
//                guard let track = transceiver.receiver.track as? RTCVideoTrack else {
//                    return;
//                }
//                self.delegate?.call(self, didReceiveRemoteVideoTrack: track, forStream: transceiver.mid, fromReceiver: transceiver.receiver.receiverId)
            }
        }

        if transceiver.direction == .sendOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                guard let track = transceiver.sender.track as? RTCVideoTrack else {
                    return;
                }
                self.delegate?.call(self, didReceiveLocalVideoTrack: track)
            }
        }
    }
}

extension Call {
    
    func sessionTerminated() {
        DispatchQueue.main.async {
            self.reset();
        }
    }
    
    func addRemoteCandidate(_ candidate: RTCIceCandidate) {
        DispatchQueue.main.async {
        guard let peerConnection = self.currentConnection else {
                return;
            }
            peerConnection.add(candidate);
        }
    }
    
    
}
