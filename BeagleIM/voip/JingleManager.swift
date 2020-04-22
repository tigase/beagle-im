//
// JingleManager
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

import AppKit
import TigaseSwift
import WebRTC

class JingleManager: JingleSessionManager, XmppServiceEventHandler {

    static let instance = JingleManager();
    
    let events: [Event] = [JingleModule.JingleEvent.TYPE, JingleModule.JingleMessageInitiationEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE];
    
    fileprivate var connections: [Session] = [];
    
    let dispatcher = QueueDispatcher(label: "jingleEventHandler");
    
    init() {
        if !RTCInitializeSSL() {
            let alert = NSAlert();
            alert.messageText = "Failed to initialize RTC SSL!";
            alert.runModal();
        }
        
        let path = FileManager.default.temporaryDirectory.path;
        if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
            files.filter({ $0.starts(with: "webrtc_log_") }).forEach { (file) in
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(file, isDirectory: false));
            }
        }
    }
    
    func activeSessionSid(for account: BareJID, with jid: JID) -> String? {
        return session(for: account, with: jid, sid: nil)?.sid;
    }

    func session(for account: BareJID, with jid: JID, sid: String?) -> Session? {
        return dispatcher.sync {
            return connections.first(where: {(sess) -> Bool in
                return (sid == nil || sess.sid == sid) && sess.account == account && sess.jid == jid;
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

    func open(for account: BareJID, with jid: JID, sid: String?, role: Jingle.Content.Creator, peerConnectionFactory: RTCPeerConnectionFactory? = nil) -> Session {
        return dispatcher.sync {
            let session = Session(account: account, jid: jid, sid: sid, role: role, peerConnectionFactory: peerConnectionFactory ??  RTCPeerConnectionFactory(encoderFactory: RTCDefaultVideoEncoderFactory(), decoderFactory: RTCDefaultVideoDecoderFactory()));
            self.connections.append(session);
            return session;
        }
    }
    
    func close(for account: BareJID, with jid: JID, sid: String) -> Session? {
        return dispatcher.sync {
            guard let idx = self.connections.firstIndex(where: { sess -> Bool in
                return sess.sid == sid && sess.account == account && sess.jid == jid;
            }) else {
                return nil;
            }
            let session =  self.connections.remove(at: idx);
            _ = session.terminate();
            return session;
        }
    }
    
    func close(session: Session) {
        dispatcher.async {
            guard let idx = self.connections.firstIndex(of: session) else {
                return;
            }
            let session = self.connections.remove(at: idx);
            _ = session.terminate();
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
            case let e as PresenceModule.ContactPresenceChanged:
                if e.availabilityChanged && (e.presence.type ?? .available) == .unavailable, let account = e.sessionObject.userBareJid, let from = e.presence.from {
                    let toClose = self.connections.filter({ (session) in
                        return session.jid == from && session.account == account;
                    });
                    toClose.forEach({ (session) in
                        _ = session.terminate();
                    })
                }
            case let e as JingleModule.JingleMessageInitiationEvent:
                switch e.action! {
                case .propose(let id, let descriptions):
                    let session = self.open(for: e.sessionObject.userBareJid!, with: e.jid, sid: nil, role: .responder);
                    session.initiate(sid: id);
                        
                    let media = descriptions.map({ VideoCallController.Media.from(string: $0.media) }).filter({ $0 != nil }).map({ $0! });
                    if (media.contains(.video) || media.contains(.audio)) && VideoCallController.hasAudioSupport {
                        VideoCallController.open(completionHandler: { controller in
                            controller.accept(session: session, media: media, completionHandler: { result in
                                switch result {
                                case .success(_):
                                    if let jingleModule: JingleModule = session.client?.modulesManager.getModule(JingleModule.ID) {
                                        jingleModule.sendMessageInitiation(action: .proceed(id: id), to: e.jid);
                                    } else {
                                        _ = session.decline();
                                    }
                                case .failure(_):
                                    _ = session.decline();
                                    if let jingleModule: JingleModule = session.client?.modulesManager.getModule(JingleModule.ID) {
                                        jingleModule.sendMessageInitiation(action: .reject(id: id), to: e.jid);
                                    }
                                }
                            })
                        })
                    } else {
                        _ = session.terminate();
                    }
                case .retract(let id):
                    self.sessionTerminated(account: e.sessionObject.userBareJid!, with: e.jid, sid: id);
                case .accept(let id):
                    self.sessionTerminated(account: e.sessionObject.userBareJid!, with: e.jid, sid: id);
                case .reject(let id):
                    self.sessionTerminated(account: e.sessionObject.userBareJid!, with: e.jid, sid: id);
                case .proceed(let id):
                    // TODO: not implemented yet!
                    self.sessionTerminated(account: e.sessionObject.userBareJid!, with: e.jid, sid: id);
                default:
                    break;
                }
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
        guard let client = XmppService.instance.getClient(for: account), let _ = client.presenceStore else {
            return [];
        }
        
        var features: [String] = [];
        
        if jid.resource == nil {
            client.presenceStore?.getPresences(for: jid.bareJid)?.values.filter({ (p) -> Bool in
                return (p.type ?? .available) == .available;
            }).forEach({ (p) in
                guard let node = p.capsNode, let f = DBCapabilitiesCache.instance.getFeatures(for: node) else {
                    return;
                }
                features.append(contentsOf: f);
            })
        } else {
            guard let p = client.presenceStore?.getPresence(for: jid), (p.type ?? .available) == .available, let node = p.capsNode, let f = DBCapabilitiesCache.instance.getFeatures(for: node) else {
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
    
    fileprivate func sessionInitiated(event e: JingleModule.JingleEvent) {
        
        guard let content = e.contents.first, let _ = content.description as? Jingle.RTP.Description else {
            if let session = session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) {
                _ = session.terminate();
            }
            return;
        }
      
        let sdp = SDP(sid: e.sid!, contents: e.contents, bundle: e.bundle);

        guard let session = session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            let session = open(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid, role: .responder);
                
            let media = sdp.contents.map({ c -> VideoCallController.Media? in VideoCallController.Media.from(string: c.description?.media) }).filter({ $0 != nil }).map({ $0! });
            if (media.contains(.video) || media.contains(.audio)) && VideoCallController.hasAudioSupport {
                VideoCallController.open(completionHandler: { controller in
                    controller.accept(session: session, media: media, completionHandler: { result in
                        switch result {
                        case .success(_):
                            session.initiated();
                            if !controller.accepted(session: session, sdpOffer: sdp) {
                                _ = session.decline();
                            }
                        case .failure(_):
                            _ = session.decline();
                        }
                    })
                })
            } else {
                _ = session.terminate();
            }
            return;
        }
        
        if let controller = session.delegate, controller.accepted(session: session, sdpOffer: sdp) {
        } else {
            _ = session.terminate();
        }
    }
    
    fileprivate func sessionAccepted(event e: JingleModule.JingleEvent) {
        guard let session = session(for: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid) else {
            return;
        }
        
        session.accepted(sdpAnswer: SDP(sid: e.sid!, contents: e.contents, bundle: e.bundle));
    }
    
    fileprivate func sessionTerminated(event e: JingleModule.JingleEvent) {
        sessionTerminated(account: e.sessionObject.userBareJid!, with: e.jid, sid: e.sid);
    }
    
    fileprivate func sessionTerminated(account: BareJID, with: JID, sid: String) {
        guard let session = session(for: account, with: with, sid: sid) else {
            return;
        }
        _ = session.terminate();
    }
    
    fileprivate func transportInfo(event e: JingleModule.JingleEvent) {
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
    
}

extension String {
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        return String((0...length-1).map{ _ in letters.randomElement()! });
    }
}
