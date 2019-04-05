//
// JingleManager_Session.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation
import TigaseSwift
import WebRTC

extension JingleManager {
    
    class Session: NSObject, RTCPeerConnectionDelegate, JingleSession {
        
        fileprivate(set) weak var client: XMPPClient?;
        fileprivate(set) var state: State = .created {
            didSet {
                print("RTPSession:", self, "state:", state);
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
        var peerConnection: RTCPeerConnection?;
        weak var delegate: VideoCallController?;
        fileprivate(set) var sid: String;
        let role: Jingle.Content.Creator;
        
        var remoteCandidates: [[String]]? = [];
        var localCandidates: [RTCIceCandidate]? = [];
        
        required init(account: BareJID, jid: JID, sid: String? = nil, role: Jingle.Content.Creator) {
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
            if let peerConnection = self.peerConnection {
                self.peerConnection = nil;
                peerConnection.close();
            }
            
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
            if newState == .connected || newState == .completed {
                self.state = .connected;
            } else if (state == .connected && (newState == .disconnected || newState == .failed || newState == .closed)) {
                self.state = .disconnected;
                DispatchQueue.main.async {
                    _ = self.terminate();
                }
            } else {
                self.state = .connecting;
            }
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        }
        
        func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
            print("generated candidate for:", candidate.sdpMid as Any, ", index:", candidate.sdpMLineIndex, "full SDP:", (peerConnection.localDescription?.sdp ?? ""));
            
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
            print("sending candidate for:", candidate.sdpMid as Any, ", index:", candidate.sdpMLineIndex, "full SDP:", (self.peerConnection?.localDescription?.sdp ?? ""));
            
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
