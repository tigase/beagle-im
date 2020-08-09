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
    
    class Session: JingleSession, CustomStringConvertible {
                
        fileprivate(set) var state: JingleSessionState = .created {
            didSet {
                os_log(OSLogType.debug, log: .jingle, "RTPSession: %s state: %d", self.description, state.rawValue);
            }
        }
        
        fileprivate weak var jingleModule: JingleModule?;
        
        var description: String {
            return "Session(sid: \(sid), jid: \(jid), account: \(account))";
        }

        let account: BareJID;
        private(set) var jid: JID;
        weak var delegate: JingleSessionDelegate?;
        fileprivate(set) var sid: String;
        let role: Jingle.Content.Creator;
        
        var remoteCandidates: [[String]] = [];
        var remoteDescription: SDP?;
        
        private(set) var initiationType: JingleSessionInitiationType;
        
        required init(sessionObject: SessionObject, jid: JID, sid: String, role: Jingle.Content.Creator, initiationType: JingleSessionInitiationType) {
            self.account = sessionObject.userBareJid!;
            self.jingleModule = sessionObject.context.modulesManager.getModule(JingleModule.ID);
            self.jid = jid;
            self.sid = sid;
            self.role = role;
            self.initiationType = initiationType;
        }
        
        func initiate(contents: [Jingle.Content], bundle: [String]?, completionHandler: ((Result<Void,ErrorCondition>)->Void)?) {
            guard let jingleModule = self.jingleModule else {
                self.terminate(reason: .failedApplication);
                completionHandler?(.failure(.unexpected_request));
                return;
            }

            jingleModule.initiateSession(to: jid, sid: sid, contents: contents, bundle: bundle, completionHandler: { result in
                switch result {
                case .success(_):
                    break;
                case .failure(_):
                    self.terminate();
                }
                completionHandler?(result);
            });
        }
        
        func initiate(descriptions: [Jingle.MessageInitiationAction.Description], completionHandler: ((Result<Void,ErrorCondition>)->Void)?) {
            guard let jingleModule = self.jingleModule else {
                self.terminate(reason: .failedApplication);
                completionHandler?(.failure(.unexpected_request));
                return;
            }
            jingleModule.sendMessageInitiation(action: .propose(id: self.sid, descriptions: descriptions), to: self.jid);
            completionHandler?(.success(Void()));
        }
        
        func initiated(remoteDescription: SDP) {
            self.state = .initiating;
            self.remoteDescription = remoteDescription;
        }
        
        func accept() {
            state = .accepted;
            if let remoteDescription = self.remoteDescription {
                delegate?.session(self, setRemoteDescription: remoteDescription);
            } else {
                if let jingleModule = self.jingleModule {
                    jingleModule.sendMessageInitiation(action: .proceed(id: self.sid), to: self.jid);
                }
            }
        }
                
        func accept(contents: [Jingle.Content], bundle: [String]?, completionHandler: ((Result<Void,ErrorCondition>)->Void)?) {
            guard let jingleModule = self.jingleModule else {
                self.terminate(reason: .failedApplication);
                completionHandler?(.failure(.unexpected_request));
                return;
            }

            jingleModule.acceptSession(with: jid, sid: sid, contents: contents, bundle: bundle) { (result) in
                switch result {
                case .success(_):
                    self.state = .accepted;
                case .failure(_):
                    self.terminate();
                    break;

                }
                completionHandler?(result);
            }
        }
        
        func accepted(by jid: JID) {
            self.state = .accepted;
            self.jid = jid;
        }
        
        func accepted(sdpAnswer: SDP) {
            self.state = .accepted;
            self.remoteDescription = sdpAnswer;
            delegate?.session(self, setRemoteDescription: sdpAnswer);
        }
        
        func decline() {
            self.terminate(reason: .decline);
        }
        
        func transportInfo(contentName: String, creator: Jingle.Content.Creator, transport: JingleTransport) -> Bool {
            guard let jingleModule = self.jingleModule else {
                return false;
            }
            
            jingleModule.transportInfo(with: jid, sid: sid, contents: [Jingle.Content(name: contentName, creator: creator, description: nil, transports: [transport])]);
            return true;
        }
        
        func terminate(reason: JingleSessionTerminateReason) {
            let oldState = self.state;
            guard state != .terminated else {
                return;
            }
            self.state = .terminated;
            if let jingleModule: JingleModule = self.jingleModule {
                if initiationType == .iq || oldState == .accepted {
                    jingleModule.terminateSession(with: jid, sid: sid, reason: reason);
                } else {
                    jingleModule.sendMessageInitiation(action: .reject(id: sid), to: jid);
                }
            }
            
            terminateSession();
        }
        
        func terminated() {
            guard state != .terminated else {
                return;
            }
            self.state = .terminated;
            self.terminateSession();
        }
        
        private func terminateSession() {
            os_log(OSLogType.debug, log: .jingle, "terminating session sid: %s", sid);
            self.delegate?.sessionTerminated(session: self);
            self.delegate = nil;
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
    }
    
}

protocol JingleSessionDelegate: class {
    
    func session(_ session: JingleManager.Session, setRemoteDescription sdp: SDP);
    func sessionTerminated(session: JingleManager.Session);
    func session(_ session: JingleManager.Session, didReceive: RTCIceCandidate);
}

extension JingleSessionState {
    var rawValue: String {
        switch self {
        case .accepted:
            return "accepted";
        case .created:
            return "created";
        case .initiating:
            return "initiating";
        case .terminated:
            return "terminated";
        }
    }
}
