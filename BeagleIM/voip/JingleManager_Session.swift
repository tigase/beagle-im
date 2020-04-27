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
    
    class Session: NSObject, JingleSession {
                
        fileprivate(set) weak var client: XMPPClient?;
        fileprivate(set) var state: State = .created {
            didSet {
                os_log(OSLogType.debug, log: .jingle, "RTPSession: %s state: %d", self.description, state.rawValue);
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
        weak var delegate: JingleSessionDelegate?;
        fileprivate(set) var sid: String;
        let role: Jingle.Content.Creator;
        
        var remoteCandidates: [[String]] = [];
        var remoteDescription: SDP?;
        
        required init(account: BareJID, jid: JID, sid: String? = nil, role: Jingle.Content.Creator) {
            self.account = account;
            self.client = XmppService.instance.getClient(for: account);
            self.jid = jid;
            self.sid = sid ?? "";
            self.role = role;
            self.state = sid == nil ? .created : .negotiating;
        }
                
        func initiate(sid: String) {
            if state == .created {
                self.sid = sid;
            }
        }
        
        func initiated(remoteDescription: SDP) {
            self.state = .negotiating;
            self.remoteDescription = remoteDescription;
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
            self.remoteDescription = sdpAnswer;
            delegate?.session(self, setRemoteDescription: sdpAnswer);
        }
        
        func decline() -> Bool {
            guard state != .disconnected else {
                return false;
            }

            let oldState = state;
            state = .disconnected;
            
            if oldState != .created, let jingleModule = self.jingleModule {
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

            let oldState = state;
            state = .disconnected;

            if oldState != .created, let jingleModule: JingleModule = self.jingleModule {
                jingleModule.terminateSession(with: jid, sid: sid);
            }
            
            terminateSession();
            return true;
        }
        
        private func terminateSession() {
            os_log(OSLogType.debug, log: .jingle, "terminating session sid: %s", sid);
            self.delegate?.sessionTerminated(session: self);
            JingleManager.instance.close(session: self);
        }
        
        func addCandidate(_ candidate: Jingle.Transport.ICEUDPTransport.Candidate, for contentName: String) {
            let sdp = candidate.toSDP();

            remoteCandidates.append([contentName, sdp]);
            receivedRemoteCandidates();
        }
        
        func receivedRemoteCandidates() {
            guard let delegate = self.delegate, self.remoteDescription != nil else {
                return;
            }

            for arr in remoteCandidates {
                let contentName = arr[0];
                let sdp = arr[1];
                guard let lines = self.remoteDescription?.toString(withSid: "0").split(separator: "\r\n").map({ (s) -> String in
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
                    delegate.session(self, didReceive: RTCIceCandidate(sdp: sdp, sdpMLineIndex: Int32(idx), sdpMid: contentName));
            }
            remoteCandidates.removeAll();
        }
        
        fileprivate func onError(_ errorCondition: ErrorCondition) {
            
        }
                
        func sendLocalCandidate(_ candidate: RTCIceCandidate, peerConnection: RTCPeerConnection) {
            os_log(OSLogType.debug, log: .jingle, "sending candidate for: %s, index: %d, full SDP: %s", candidate.sdpMid ?? "", candidate.sdpMLineIndex, (peerConnection.localDescription?.sdp ?? ""));
            
            guard let jingleCandidate = Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: candidate.sdp) else {
                return;
            }
            guard let mid = candidate.sdpMid else {
                return;
            }
            
            guard let desc = peerConnection.localDescription, let (sdp,sid) = SDP.parse(sdpString: desc.sdp, creator: role) else {
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
        
        enum State: Int {
            case created
            case negotiating
            case connecting
            case connected
            case disconnected
        }
    }
    
}

protocol JingleSessionDelegate: class {
    
    func session(_ session: JingleManager.Session, setRemoteDescription sdp: SDP);
    func sessionTerminated(session: JingleManager.Session);
    func session(_ session: JingleManager.Session, didReceive: RTCIceCandidate);
}
