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
import Martin
import Combine
import TigaseLogging

class CallManager {
    
    static let instance = CallManager();

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "jingle")
    
    func reportIncomingCall(_ call: Call) async throws {
        call.session = JingleManager.instance.session(forCall: call);
        call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        call.changeState(.ringing);
                
        guard !MeetManager.instance.reportIncoming(call: call) else {
            return;
        }
                
        do {
            try await checkMediaAvailability(forCall: call);
            try await call.start();
        } catch {
            call.session = nil;
            call.reset();
            throw error;
        }
    }
    
    func reportOutgoingCall(_ call: Call) async throws {
        call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        call.changeState(.ringing);
        do {
            try await call.start();
            try await self.checkMediaAvailability(forCall: call);
            try await call.initiateOutgoingCall();
        } catch {
            call.reset();
            throw error;
        }
    }
    
    func checkMediaAvailability(forCall call: Call) async throws {
        for media in call.media {
            try await self.checkAccesssPermission(media: media);
        }
    }
    
    func checkAccesssPermission(media: Call.Media) async throws {
        try await withUnsafeThrowingContinuation({ continuation in
            CaptureDeviceManager.requestAccess(for: media.avmedia, completionHandler: { result in
                if result {
                    continuation.resume();
                } else {
                    continuation.resume(throwing: XMPPError(condition: .forbidden));
                }
            })
        })
    }
    
//    private func initializeCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
//        call.initiateWebRTC(completionHandler: completionHandler);
//    }
    
}

class Call: NSObject, JingleSessionActionDelegate, @unchecked Sendable {
    
    var name: String {
        return DBRosterStore.instance.item(for: client, jid: JID(jid))?.name ?? jid.description;
    }

    
    let client: XMPPClient;
    let jid: BareJID;
    let sid: String;
    let direction: Direction;
    let media: [Media]
    
    var account: BareJID {
        return client.userBareJid;
    }
    
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

    private var establishingSessions = EstablishingSessions();
    
    private class EstablishingSessions: @unchecked Sendable {
        
        private let lock = UnfairLock();
        private var _completed: Bool = false;
        private var _sessions: [JingleManager.Session] = [];
        
        var isCompleted: Bool {
            lock.lock();
            defer {
                lock.unlock();
            }
            return _completed;
        }
        
        func add(session: JingleManager.Session) throws {
            lock.lock();
            defer {
                lock.unlock();
            }
            guard !_completed else {
                throw XMPPError(condition: .not_acceptable);
            }
            _sessions.append(session);
        }
        
        func sessions() -> [JingleManager.Session] {
            lock.lock();
            defer {
                lock.unlock();
            }
            return _sessions;
        }
        
        func accepted(session: JingleManager.Session) throws -> [JingleManager.Session] {
            lock.lock();
            defer {
                lock.unlock();
            }
            guard !_completed else {
                throw XMPPError(condition: .not_acceptable);
            }
            _completed = true;
            _sessions.removeAll(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid })
            return _sessions;
        }
        
        func rejected(session: JingleManager.Session) {
            lock.lock();
            defer {
                lock.unlock();
            }
            _sessions.removeAll(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid })
            _completed = _completed || _sessions.isEmpty;
        }
        
        func rejectAll() -> [JingleManager.Session] {
            lock.lock();
            defer {
                lock.unlock();
            }
            _completed = true;
            let sessions = _sessions;
            _sessions.removeAll()
            return sessions;
        }
    }
    
    private var localCandidates: [RTCIceCandidate] = [];
    
    private(set) var localVideoSource: RTCVideoSource?;
    private(set) var localVideoTrack: RTCVideoTrack?;
    private(set) var localAudioTrack: RTCAudioTrack?;
    private(set) var localCapturer: VideoCapturer?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override var description: String {
        return "Call[on: \(client.userBareJid), with: \(jid), sid: \(sid)]";
    }
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Call");
    
    var currentCapturerDevice: VideoCaptureDevice? {
        return localCapturer?.currentDevice;
    }
    
    init(client: XMPPClient, with jid: BareJID, sid: String, direction: Direction, media: [Media]) {
        self.client = client;
        self.jid = jid;
        self.media = media;
        self.sid = sid;
        self.direction = direction;
    }
    
    func isEqual(_ c: Call) -> Bool {
        return c.account == account && c.jid == jid && c.sid == sid;
    }
    
    func start() async throws {
        await MainActor.run(body: {
            VideoCallController.open(completionHandler: { controller in
                self.delegate = controller;
            })
        })
        try await initiateOutgoingCall();
    }
    
    func accept(offerMedia: [Media]) async throws {
        await MainActor.run(body: {
            VideoCallController.open(completionHandler: { controller in
                self.delegate = controller;
            })
        })
        try await self.accept(offerMedia: media);
    }
    
    func end() {
        if self.state == .new || self.state == .ringing {
            self.reject();
        } else {
            self.reset();
        }
    }
    
    func mute(value: Bool) {
        self.localAudioTrack?.isEnabled = !value;
        self.localVideoTrack?.isEnabled = !value;
        let infos: [Jingle.SessionInfo] = self.localSessionDescription?.contents.filter({ $0.description?.media == "audio" || $0.description?.media == "video" }).map({ $0.name }).map({ value ? .mute(contentName: $0) : .unmute(contentName: $0) }) ?? [];
        if !infos.isEmpty {
            Task {
                try await session?.sessionInfo(infos);
            }
        }
    }
    
    func ringing() {
        if direction == .incoming {
            session = JingleManager.instance.session(forCall: self);
        }
        webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        changeState(.ringing);
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
            Task {
                _ = try await self.session?.terminate();
            }
            self.session = nil;
            self.delegate = nil;
            for session in self.establishingSessions.rejectAll() {
                Task {
                    try await session.terminate();

                }
            }
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
    
    private func findJidsWithJingle() -> [JID] {
        return PresenceStore.instance.presences(for: jid, context: client).compactMap({
            guard let jid = $0.from, let node = $0.capsNode, DBCapabilitiesCache.instance.areSupported(features: [JingleModule.XMLNS, Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:rtp:audio"], for: node) else {
                return nil;
            }
            return jid;
        });
    }
    
    private func findJidsWithMessageInitiation() -> [JID] {
        return PresenceStore.instance.presences(for: jid, context: client).compactMap({
            guard let jid = $0.from, let node = $0.capsNode, DBCapabilitiesCache.instance.isSupported(feature: JingleModule.MESSAGE_INITIATION_XMLNS, for: node) else {
                return nil;
            }
            return jid;
        });
    }
    
    private func checkAllHaveJMI(jids: [JID]) -> Bool {
        for jid in jids {
            if let node = PresenceStore.instance.presence(for: jid, context: client)?.capsNode {
                if !DBCapabilitiesCache.instance.isSupported(feature: JingleModule.MESSAGE_INITIATION_XMLNS, for: node) {
                    return false;
                }
            }
        }
        return true;
    }

    func initiateOutgoingCall(with callee: JID? = nil) async throws {
        guard let client = XmppService.instance.getClient(for: account) else {
            throw XMPPError(condition: .item_not_found);
        }
        let withJingle: [JID] = callee != nil ? [callee!] : findJidsWithJingle();
        let allHaveJMI = callee == nil && checkAllHaveJMI(jids: withJingle);
                
        self.changeState(.ringing);
        do {
            try initiateWebRTC(iceServers: await discoverIceServers(), offerMedia: media);
        } catch {
            reset();
            throw error;
        }
        
        Task {
            if allHaveJMI {
                let session = JingleManager.instance.open(for: client, with: JID(self.jid), sid: self.sid, role: .initiator, initiationType: .message);
                self.session = session;
                do {
                    try await session.initiate(descriptions: self.media.map({ Jingle.MessageInitiationAction.Description(xmlns: "urn:xmpp:jingle:apps:rtp:1", media: $0.rawValue) }));
                } catch {
                    self.reset();
                }
            } else {
                // we need to establish multiple 1-1 sessions...
                guard let peerConnection = self.currentConnection else {
                    return;
                }
                do {
                    let sdp = try await generateOfferAndSet(peerConnection: peerConnection, creatorProvider: { _ in Jingle.Content.Creator.initiator }, localRole: .initiator);
                    let sessions = withJingle.compactMap({ jid -> JingleManager.Session? in
                        let session = JingleManager.instance.open(for: client, with: jid, sid: self.sid, role: .initiator, initiationType: .iq);
                        session.$state.removeDuplicates().sink(receiveValue: { state in
                            switch state {
                            case .accepted:
                                Task {
                                    guard self.session == nil else {
                                        try await session.terminate();
                                        return;
                                    }
                                    
                                    do {
                                        for sess in try self.establishingSessions.accepted(session: session) {
                                            Task {
                                                try await sess.terminate();
                                            }
                                        }
                                        
                                        self.session = session;
                                        self.state = .connecting;
                                        self.connectRemoteSDPPublishers(session: session);
                                        self.sendLocalCandidates();
                                    } catch {
                                        try await session.terminate();
                                    }
                                }
                            case .terminated:
                                Task {
                                    self.establishingSessions.rejected(session: session);
                                    if self.establishingSessions.isCompleted && self.session == nil {
                                        self.reset();
                                    }
                                }
                            default:
                                break;
                            }
                        }).store(in: &self.cancellables);
                        do {
                            try self.establishingSessions.add(session: session);
                            return session;
                        } catch {
                            return nil;
                        }
                    })
                    for session in sessions {
                        Task {
                            do {
                                try await session.initiate(contents: sdp.contents, bundle: sdp.bundle);
                            } catch let error as XMPPError {
                                if error.condition == .remote_server_timeout {
                                    self.establishingSessions.rejected(session: session);
                                    if self.establishingSessions.isCompleted && self.session == nil {
                                        self.reset();
                                    }
                                } else {
                                    throw error;
                                }
                            }
                        }
                    }
                } catch {
                    self.reset();
                }
            }
        }
    }
        
    private func acceptedOutgingCall() {
        guard let session = session, session.initiationType == .message, state == .ringing, let peerConnection = currentConnection else {
            return;
        }
        changeState(.connecting);
        Task {
            do {
                let sdp = try await generateOfferAndSet(peerConnection: peerConnection, creatorProvider: session.contentCreator(of:), localRole: session.role);
                self.connectRemoteSDPPublishers(session: session);
                try await session.initiate(contents: sdp.contents, bundle: sdp.bundle);
            } catch {
                self.reset();
            }
        }
    }
    
    private func connectRemoteSDPPublishers(session: JingleManager.Session) {
        session.setDelegate(self);
    }
            
    static let VALID_SERVICE_TYPES = ["stun", "stuns", "turn", "turns"];
    
    private func discoverIceServers() async -> [RTCIceServer] {
        if let module: ExternalServiceDiscoveryModule = XmppService.instance.getClient(for: self.account)?.module(.externalServiceDiscovery), module.isAvailable {
            do {
                let services = try await module.discover(from: nil, type: nil);
                return services.compactMap({ $0.rtcIceServer() })
            } catch {}
        }
        return [];
    }
    
//    func initiateWebRTC(completionHandler: @escaping (Result<Void,Error>)->Void) {
//        if let module: ExternalServiceDiscoveryModule = XmppService.instance.getClient(for: self.account)?.module(.externalServiceDiscovery), module.isAvailable {
//            module.discover(from: nil, type: nil, completionHandler: { [weak self] result in
//                switch result {
//                case .success(let services):
//                    var servers: [RTCIceServer] = [];
//                    for service in services {
//                        if let server = service.rtcIceServer() {
//                            servers.append(server);
//                        }
//                    }
//                    self?.initiateWebRTC(iceServers: servers, completionHandler: completionHandler);
//                case .failure(_):
//                    self?.initiateWebRTC(iceServers: [], completionHandler: completionHandler);
//                }
//            })
//        } else {
//            initiateWebRTC(iceServers: [], completionHandler: completionHandler);
//        }
//    }
    
    private func initiateWebRTC(iceServers: [RTCIceServer], offerMedia media: [Media]) throws {
        // moved initialization to main queue to sync with a call to reset()
        self.currentConnection = VideoCallController.initiatePeerConnection(iceServers: iceServers, withDelegate: self);
        if self.currentConnection != nil {
            self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
            if let localAudioTrack = self.localAudioTrack {
                self.currentConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
            }
            if media.contains(.video) && CaptureDeviceManager.authorizationStatus(for: .video) == .authorized {
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
                    return;
                } else {
                    throw XMPPError(condition: .item_not_found);
                }
            } else {
                return;
            }
        } else {
            throw XMPPError(condition: .internal_server_error);
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

    func accept(offerMedia media: [Media]) {
        guard let session = self.session else {
            reset();
            return;
        }
        changeState(.connecting);
        Task {
            do {
                try initiateWebRTC(iceServers: await discoverIceServers(), offerMedia: media);
                guard self.currentConnection != nil else {
                    self.reject();
                    return;
                }
                try await session.accept();
                self.connectRemoteSDPPublishers(session: session);
            } catch {
                self.reject();
            }
        }
    }
    
    func reject() {
        guard let session = self.session else {
            reset();
            return;
        }
        Task {
            try await session.decline();
        }
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
                peerConnection.add(RTCIceCandidate(sdp: candidate.toSDP(), sdpMLineIndex: Int32(idx), sdpMid: contentName), completionHandler: { _ in });
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
        Task {
            do {
                if let localSDP = try await setRemoteDescription(newSDP, peerConnection: peerConnection, session: session) {
                    if let prevLocalSDP = prevLocalSDP {
                        let changes = localSDP.diff(from: prevLocalSDP);
                        if let addSDP = changes[.add] {
                            Task {
                                try await session.contentModify(action: .accept, contents: addSDP.contents, bundle: addSDP.bundle);
                            }
                        }
                        if let modifySDP = changes[.modify] {
                            // can we safely ignore this?
                        }
                    } else {
                        Task {
                            try await session.accept(contents: localSDP.contents, bundle: localSDP.bundle)
                        }
                        Task {
                            try await Task.sleep(nanoseconds: 100 * 1000 * 1000);
                            sendLocalCandidates();
                        }
                    }
                }
            } catch {
                self.logger.error("error setting remote description: \(error)");
                self.reset();
            }
        }
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

    private func setRemoteDescription(_ remoteDescription: SDP, peerConnection: RTCPeerConnection, session: JingleSession) async throws -> SDP? {
        logger.debug("\(self), setting remote description: \(remoteDescription.toString(withSid: "", localRole: session.role, direction: .incoming))");
        try await peerConnection.setRemoteDescription(RTCSessionDescription(type: self.direction == .incoming ? .offer : .answer, sdp: remoteDescription.toString(withSid: self.webrtcSid!, localRole: session.role, direction: .incoming)));
        self.remoteSessionDescription = remoteDescription;
        if peerConnection.signalingState == .haveRemoteOffer {
            return try await self.generateAnswerAndSet(peerConnection: peerConnection, creatorProvider: session.contentCreator(of:), localRole: session.role);
        } else {
            return nil;
        }
    }
    
    private func generateOfferAndSet(peerConnection: RTCPeerConnection, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator) async throws -> SDP {
        logger.debug("\(self), generating offer");
        let sdpOffer = try await peerConnection.offer(for: VideoCallController.defaultCallConstraints);
        return try await setLocalDescription(peerConnection: peerConnection, sdp: sdpOffer, creatorProvider: creatorProvider, localRole: localRole);
    }
        
    private func generateAnswerAndSet(peerConnection: RTCPeerConnection, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator) async throws -> SDP {
        logger.debug("\(self), generating answer");
        let sdpAnswer = try await peerConnection.answer(for: VideoCallController.defaultCallConstraints);
        return try await setLocalDescription(peerConnection: peerConnection, sdp: sdpAnswer, creatorProvider: creatorProvider, localRole: localRole);
    }
    
    private func setLocalDescription(peerConnection: RTCPeerConnection, sdp localSDP: RTCSessionDescription, creatorProvider: @escaping (String)->Jingle.Content.Creator, localRole: Jingle.Content.Creator) async throws -> SDP {
        logger.debug("\(self), setting local description: \(localSDP.sdp)");
        try await peerConnection.setLocalDescription(localSDP);
        guard let (sdp, _) = SDP.parse(sdpString: localSDP.sdp, creatorProvider: creatorProvider, localRole: localRole) else {
            throw XMPPError(condition: .not_acceptable);
        }
        localSessionDescription = sdp;
        return sdp;
    }
    
    func changeState(_ state: State) {
        self.state = state;
        self.delegate?.callStateChanged(self);
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
        JingleManager.instance.queue.async {
            self.localCandidates.append(candidate);
            self.sendLocalCandidates();
        }
    }
        
    private func sendLocalCandidates() {
        guard let session = self.session else {
            return;
        }
        for candidate in localCandidates {
            Task {
                try await sendLocalCandidate(candidate, session: session)
            }
        }
        self.localCandidates = [];
    }
    
    private func sendLocalCandidate(_ candidate: RTCIceCandidate, session: JingleManager.Session) async throws {
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
        
        try await session.transportInfo(contentName: mid, transport: Jingle.Transport.ICEUDPTransport(pwd: transport.pwd, ufrag: transport.ufrag, candidates: [jingleCandidate]));
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
            peerConnection.add(candidate, completionHandler: { _ in });
        }
    }
    
    
}
