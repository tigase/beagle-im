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
import WebRTC
import TigaseSwift

class CallManager {
    
    static let instance = CallManager();

    private let dispatcher = QueueDispatcher(label: "callManager");
    
    private var activeCalls: [Call] = [];
    
    func reportIncomingCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        call.session = JingleManager.instance.session(forCall: call);
        call.session?.delegate = call;
        dispatcher.async {
            if !self.activeCalls.contains(call) {
                self.activeCalls.append(call);
                call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
                call.changeState(.ringing);
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
            } else {
                completionHandler(.failure(ErrorCondition.conflict));
            }
        }
    }
    
    func reportOutgoingCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        dispatcher.async {
            if !self.activeCalls.contains(call) {
                self.activeCalls.append(call);
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
            } else {
                completionHandler(.failure(ErrorCondition.conflict));
            }
        }
    }
    
    func acceptedOutgoingCall(_ call: Call, by jid: JID, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        dispatcher.async {
            if let idx = self.activeCalls.firstIndex(of: call) {
                self.activeCalls[idx].acceptedOutgingCall(for: jid, completionHandler: completionHandler);
            } else {
                completionHandler(.failure(.item_not_found));
            }
        }
    }
    
    func declinedOutgoingCall(_ call: Call) {
        dispatcher.async {
            if let idx = self.activeCalls.firstIndex(of: call) {
                self.activeCalls[idx].reset();
            }
        }
    }
    
    func terminateCalls(for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            let toTerminate = self.activeCalls.filter({ $0.account == account && $0.jid == jid });
            for call in toTerminate {
                call.reset();
            }
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
        switch AVCaptureDevice.authorizationStatus(for: media.avmedia) {
        case .authorized:
            completionHandler(.success(Void()));
        case .denied, .restricted:
            completionHandler(.failure(ErrorCondition.forbidden));
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: media.avmedia, completionHandler: { result in
                completionHandler(result ? .success(Void()) : .failure(ErrorCondition.forbidden));
            })
        default:
            completionHandler(.failure(ErrorCondition.forbidden));
        }
    }
    
    private func initializeCall(_ call: Call, completionHandler: @escaping (Result<Void,Error>)->Void) {
        call.initiateWebRTC(completionHandler: completionHandler);
    }
    
    fileprivate func callEnded(_ call: Call) {
        dispatcher.async {
            if let idx = self.activeCalls.firstIndex(of: call) {
                self.activeCalls.remove(at: idx);
            }
        }
    }
}

class Call: NSObject {
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

    fileprivate var webrtcSid: String?;
    
    private(set) var currentConnection: RTCPeerConnection?;
    
    fileprivate(set) weak var delegate: CallDelegate? {
        didSet {
            delegate?.callDidStart(self);
        }
    }
    fileprivate(set) var session: JingleManager.Session?;

    private var establishingSessions: [JingleManager.Session] = [];
    
    private var localCandidates: [RTCIceCandidate] = [];
    
    private(set) var localVideoSource: RTCVideoSource?;
    private(set) var localVideoTrack: RTCVideoTrack?;
    private(set) var localAudioTrack: RTCAudioTrack?;
    private(set) var localCapturer: RTCCameraVideoCapturer?;
    private(set) var localCameraDeviceID: String?;
    
    init(account: BareJID, with jid: BareJID, sid: String, direction: Direction, media: [Media]) {
        self.account = account;
        self.jid = jid;
        self.media = media;
        self.sid = sid;
        self.direction = direction;
    }
    
    func reset() {
        DispatchQueue.main.async {
            self.currentConnection?.close();
            self.currentConnection = nil;
            if self.localCapturer != nil {
                self.localCapturer?.stopCapture(completionHandler: {
                    self.localCapturer = nil;
                })
            }
            self.localVideoTrack = nil;
            self.localAudioTrack = nil;
            self.localVideoSource = nil;
            self.delegate?.callDidEnd(self);
            _ = self.session?.terminate();
            self.session = nil;
            self.delegate = nil;
            for session in self.establishingSessions {
                _ = session.terminate();
            }
            self.establishingSessions.removeAll();
        }
        CallManager.instance.callEnded(self);
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

    func initiateOutgoingCall(completionHandler: @escaping (Result<Void,Error>)->Void) {
        guard let client = XmppService.instance.getClient(for: account), let presences = client.presenceStore?.getPresences(for: jid)?.values, !presences.isEmpty else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        };
        var withJingle: [JID] = [];
        var withJMI: [JID] = [];
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
        guard !withJingle.isEmpty else {
            completionHandler(.failure(ErrorCondition.item_not_found));
            return;
        }
                
        self.changeState(.ringing);
        initiateWebRTC(completionHandler: { result in
            switch result {
            case .success(_):
                completionHandler(.success(Void()));
                if withJMI.count == withJingle.count {
                    let session = JingleManager.instance.open(for: client.sessionObject, with: JID(self.jid), sid: self.sid, role: .initiator, initiationType: .message);
                    session.delegate = self;
                    session.initiate(descriptions: self.media.map({ Jingle.MessageInitiationAction.Description(xmlns: "urn:xmpp:jingle:apps:rtp:1", media: $0.rawValue) }), completionHandler: nil);
                } else {
                    // we need to establish multiple 1-1 sessions...
                    self.generateLocalDescription(completionHandler: { result in
                        switch result {
                        case .failure(_):
                            self.reset();
                        case .success(let sdp):
                            DispatchQueue.main.async {
                                for jid in withJingle {
                                    let session = JingleManager.instance.open(for: client.sessionObject, with: jid, sid: self.sid, role: .initiator, initiationType: .message);
                                    session.delegate = self;
                                    self.establishingSessions.append(session);
                                    session.initiate(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil);
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
        
    fileprivate func acceptedOutgingCall(for jid: JID, completionHandler: @escaping (Result<Void,ErrorCondition>)->Void) {
        changeState(.connecting);
        self.session = JingleManager.instance.session(forCall: self);
        generateLocalDescription(completionHandler: { result in
            switch result {
            case .success(let sdp):
                guard let session = self.session else {
                    completionHandler(.failure(.item_not_found));
                    return
                }
                session.initiate(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil);
                completionHandler(.success(Void()));
            case .failure(let err):
                completionHandler(.failure(err));
            }
        });
    }
        
    private func generateLocalDescription(completionHandler: @escaping (Result<SDP,ErrorCondition>)->Void) {
        if let peerConnection = self.currentConnection {
            peerConnection.offer(for: VideoCallController.defaultCallConstraints, completionHandler: { (description, error) in
                guard let desc = description, let (sdp, sid) = SDP.parse(sdpString: desc.sdp, creator: .initiator) else {
                    completionHandler(.failure(.internal_server_error));
                    return;
                }
                peerConnection.setLocalDescription(RTCSessionDescription(type: desc.type, sdp: sdp.toString(withSid: self.webrtcSid!)), completionHandler: { error in
                    guard error == nil else {
                        completionHandler(.failure(.internal_server_error));
                        return;
                    }
                    completionHandler(.success(sdp));
                })
            })
        } else {
            completionHandler(.failure(.item_not_found));
        }
    }
    
    func initiateWebRTC(completionHandler: @escaping (Result<Void,Error>)->Void) {
        currentConnection = VideoCallController.initiatePeerConnection(withDelegate: self);
        if currentConnection != nil {
            self.localAudioTrack = VideoCallController.peerConnectionFactory.audioTrack(withTrackId: "audio-" + UUID().uuidString);
            if let localAudioTrack = self.localAudioTrack {
                currentConnection?.add(localAudioTrack, streamIds: ["RTCmS"]);
            }
            if media.contains(.video) && AVCaptureDevice.authorizationStatus(for: .video) == .authorized {
                let videoSource = VideoCallController.peerConnectionFactory.videoSource();
                self.localVideoSource = videoSource;
                let localVideoTrack = VideoCallController.peerConnectionFactory.videoTrack(with: videoSource, trackId: "video-" + UUID().uuidString);
                self.localVideoTrack = localVideoTrack;
                let localVideoCapturer = RTCCameraVideoCapturer(delegate: videoSource);
                self.localCapturer = localVideoCapturer;
                currentConnection?.add(localVideoTrack, streamIds: ["RTCmS"]);
                if let device = RTCCameraVideoCapturer.captureDevices().first, let format = RTCCameraVideoCapturer.format(for: device, preferredOutputPixelFormat: localVideoCapturer.preferredOutputPixelFormat()) {
                    print("starting video capture on:", device, " with:", format, " fps:", RTCCameraVideoCapturer.fps(for: format));
                    self.localCameraDeviceID = device.uniqueID;
                    DispatchQueue.main.async {
                        localVideoCapturer.startCapture(with: device, format: format, fps: RTCCameraVideoCapturer.fps(for:  format), completionHandler: { error in
                            print("video capturer started!");
                            DispatchQueue.main.async {
                                completionHandler(.success(Void()));
                            }
                        });
                        self.delegate?.call(self, didReceiveLocalVideoTrack: localVideoTrack);
                    }
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

    func accept() {
        guard let session = self.session else {
            reset();
            return;
        }
        changeState(.connecting);
        initiateWebRTC(completionHandler: { result in
            switch result {
            case .success(_):
                guard let peerConnection = self.currentConnection else {
                    self.reject();
                    return;
                }
                session.delegate = self;
                session.accept();
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
    
    fileprivate func setRemoteDescription(_ remoteDescription: SDP, peerConnection: RTCPeerConnection, session: JingleManager.Session, completionHandler: @escaping (Result<Void,Error>)->Void) {
        print("setting remote description");
        peerConnection.setRemoteDescription(RTCSessionDescription(type: self.direction == .incoming ? .offer : .answer, sdp: remoteDescription.toString(withSid: self.webrtcSid!)), completionHandler: { error in
            if let err = error {
                print("failed to set remote description!", err);
                completionHandler(.failure(err));
            } else if self.direction == .incoming {
                //DispatchQueue.main.async {
                print("retrieving current connection");
    //                peerConnection.transceivers.forEach({ transceiver in
    //                    if (!call.media.contains(.audio)) && transceiver.mediaType == .audio {
    //                        transceiver.stop();
    //                    }
    //                    if (!call.media.contains(.video)) && transceiver.mediaType == .video {
    //                        transceiver.stop();
    //                    }
    //                });
                print("generating answer");
                peerConnection.answer(for: VideoCallController.defaultCallConstraints, completionHandler: { (sdpAnswer, error) in
                    if let err = error {
                        print("answer generation failed:", err);
                        completionHandler(.failure(err));
                    } else {
                        print("setting local description:", sdpAnswer!.sdp);
                        peerConnection.setLocalDescription(sdpAnswer!, completionHandler: { error in
                            if let err = error {
                                print("answer generation failed:", err);
                                completionHandler(.failure(err));
                            } else {
                                print("sending answer to remote client");
                                let (sdp, sid) = SDP.parse(sdpString: sdpAnswer!.sdp, creator: .responder)!;
                                _ = session.accept(contents: sdp.contents, bundle: sdp.bundle, completionHandler: nil)
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: {
                                    self.sendLocalCandidates();
                                })
                                completionHandler(.success(Void()));
                            }
                        });
                    }
                })
                //}
            } else {
            completionHandler(.success(Void()));
            }
        })
    }
    
    func changeState(_ state: State) {
        self.state = state;
        self.delegate?.callStateChanged(self);
    }

    func muted(value: Bool) {
        self.localAudioTrack?.isEnabled = !value;
    }
    
}

protocol CallDelegate: class {
    
    func callDidStart(_ sender: Call);
    func callDidEnd(_ sender: Call);
    
    func callStateChanged(_ sender: Call);
    
    func call(_ sender: Call, didReceiveLocalVideoTrack localTrack: RTCVideoTrack);
    func call(_ sender: Call, didReceiveRemoteVideoTrack remoteTrack: RTCVideoTrack);

    
}


extension Call: RTCPeerConnectionDelegate {
    
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        print("signaling state:", stateChanged.rawValue);
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
    }
        
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .disconnected:
            self.reset();
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
        guard let session = self.session, let peerConnection = self.currentConnection else {
            return;
        }
        for candidate in localCandidates {
            session.sendLocalCandidate(candidate, peerConnection: peerConnection);
        }
        self.localCandidates = [];
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
            
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
            
    }
        
    func peerConnection(_ peerConnection: RTCPeerConnection, didStartReceivingOn transceiver: RTCRtpTransceiver) {
        if transceiver.direction == .recvOnly || transceiver.direction == .sendRecv {
            if transceiver.mediaType == .video {
                print("got video transceiver");
                guard let track = transceiver.receiver.track as? RTCVideoTrack else {
                    return;
                }
                self.delegate?.call(self, didReceiveRemoteVideoTrack: track)
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

extension Call: JingleSessionDelegate {
    
    func session(_ session: JingleManager.Session, setRemoteDescription sdp: SDP) {
        DispatchQueue.main.async {
            guard let peerConnection = self.currentConnection else {
                return;
            }
            
            for sess in self.establishingSessions {
                if sess.account == session.account && sess.jid == session.jid && sess.sid == session.sid {
                    self.session = sess;
                    self.sendLocalCandidates();
                } else {
                    _ = sess.terminate();
                }
            }
            self.establishingSessions.removeAll();
            
            self.changeState(.connecting);
            
            self.setRemoteDescription(sdp, peerConnection: peerConnection, session: session, completionHandler: { result in
                switch result {
                case .success(_):
                    break;
                case .failure(let err):
                    print("error setting remote description:", err)
                    self.reset();
                }
            })
        }
    }
    
    func sessionTerminated(session: JingleManager.Session) {
        DispatchQueue.main.async {
            if self.direction == .outgoing {
                if let idx = self.establishingSessions.firstIndex(where: { $0.account == session.account && $0.jid == session.jid && $0.sid == session.sid }) {
                    self.establishingSessions.remove(at: idx);
                }
                if self.establishingSessions.isEmpty {
                    self.reset();
                }
            } else {
                self.reset();
            }
        }
    }
    
    func session(_ session: JingleManager.Session, didReceive candidate: RTCIceCandidate) {
        guard let peerConnection = self.currentConnection else {
            return;
        }
        peerConnection.add(candidate);
    }
    
    
}
