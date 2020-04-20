//
// JingleManager_Session.swift
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

import Foundation
import TigaseSwift
import WebRTC
import os

extension JingleManager {
    
    class Session: NSObject, RTCPeerConnectionDelegate, JingleSession {
        
        required convenience init(account: BareJID, jid: JID, sid: String?, role: Jingle.Content.Creator) {
            self.init(account: account, jid: jid, sid: sid, role: role, peerConnectionFactory: RTCPeerConnectionFactory());
        }
        
        fileprivate(set) weak var client: XMPPClient?;
        fileprivate(set) var state: State = .created {
            didSet {
                os_log(OSLogType.debug, log: .jingle, "RTPSession: %s state: %d", self.description, state.rawValue);
                delegate?.state = state;
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
        let peerConnectionFactory: RTCPeerConnectionFactory;
        fileprivate(set) var peerConnection: RTCPeerConnection?;
        weak var delegate: VideoCallController?;
        fileprivate(set) var sid: String;
        let role: Jingle.Content.Creator;
        
        var remoteCandidates: [[String]]? = [];
        var localCandidates: [RTCIceCandidate]? = [];
        
        required init(account: BareJID, jid: JID, sid: String? = nil, role: Jingle.Content.Creator, peerConnectionFactory: RTCPeerConnectionFactory) {
            self.account = account;
            self.client = XmppService.instance.getClient(for: account);
            self.jid = jid;
            self.sid = sid ?? "";
            self.role = role;
            self.state = sid == nil ? .created : .negotiating;
            self.peerConnectionFactory = peerConnectionFactory;
        }
        
        deinit {
            self.peerConnection?.close();
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
        
        func initiatePeerConnection(with configuration: RTCConfiguration, constraints: RTCMediaConstraints) -> RTCPeerConnection? {
            self.peerConnection = peerConnectionFactory.peerConnection(with: configuration, constraints: constraints, delegate: self);
            return peerConnection;
        }
        
        func accept(contents: [Jingle.Content], bundle: [String]?) -> Bool {
            guard state != .disconnected else {
                return false;
            }

            guard let client = self.client, let accountJid = ResourceBinderModule.getBindedJid(client.sessionObject), let jingleModule: JingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.acceptSession(with: jid, sid: sid, initiator: role == .initiator ? accountJid : jid, contents: contents, bundle: bundle) { (error) in
                if (error != nil) {
                    self.onError(error!);
                } else {
                    //                    self.state = .connecting;
                }
            }
            
            return true;
        }
        
        func accepted(sdpAnswer: SDP) {
            self.state = .connecting;
            delegate?.sessionAccepted(session: self, sdpAnswer: sdpAnswer);
        }
        
        func decline() -> Bool {
            guard state != .disconnected else {
                return false;
            }

            state = .disconnected;
            
            if let jingleModule = self.jingleModule {
                jingleModule.declineSession(with: jid, sid: sid);
            }
            
            terminateSession();
            return true;
        }
        
        func transportInfo(contentName: String, creator: Jingle.Content.Creator, transport: JingleTransport) -> Bool {
            guard state != .disconnected else {
                return false;
            }
            
            guard let jingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.transportInfo(with: jid, sid: sid, contents: [Jingle.Content(name: contentName, creator: creator, description: nil, transports: [transport])]);
            return true;
        }
        
        func terminate() -> Bool {
            guard state != .disconnected else {
                return false;
            }

            state = .disconnected;

            if let jingleModule: JingleModule = self.jingleModule {
                jingleModule.terminateSession(with: jid, sid: sid);
            }
            
            terminateSession();
            return true;
        }
        
        private func terminateSession() {
            os_log(OSLogType.debug, log: .jingle, "terminating session sid: %s", sid);
            self.delegate?.sessionTerminated(session: self);
            if let peerConnection = self.peerConnection {
                self.peerConnection = nil;
                os_log(OSLogType.debug, log: .jingle, "closing connection");
                peerConnection.close();
                os_log(OSLogType.debug, log: .jingle, "connection freed!");
            }
            
            JingleManager.instance.close(session: self);
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
                
                os_log(OSLogType.debug, log: .jingle, "adding candidate for: %d name: %s sdp: %s", idx, contentName, sdp)
                self.peerConnection?.add(RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: contentName));
            }
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
            os_log(OSLogType.debug, log: .jingle, "signaling state: %d", stateChanged.rawValue);
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
                    os_log(OSLogType.debug, log: .jingle, "got video transceiver");
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
            os_log(OSLogType.debug, log: .jingle, "ice connection state: %d", newState.rawValue);
            
            switch newState {
            case .new, .checking:
                self.state = .connecting
            case .connected, .completed:
                self.state = .connected;
            case .disconnected, .failed, .closed:
                _ = self.terminate();
            case .count:
                break;
            default:
                break;
            }
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            os_log(OSLogType.debug, log: .jingle, "generated candidate for: %s, index: %d, full SDP: %s", candidate.sdpMid ?? "nil", candidate.sdpMLineIndex, (peerConnection.localDescription?.sdp ?? ""));
            
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
            os_log(OSLogType.debug, log: .jingle, "sending candidate for: %s, index: %d, full SDP: %s", candidate.sdpMid ?? "", candidate.sdpMLineIndex, (self.peerConnection?.localDescription?.sdp ?? ""));
            
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
        
        enum State: Int {
            case created
            case negotiating
            case connecting
            case connected
            case disconnected
        }
    }
    
}
