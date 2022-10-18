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
import Martin
import WebRTC
import Combine

class JingleManager: JingleSessionManager {
    
    static let instance = JingleManager();
    
//    let events: [Event] = [PresenceModule.ContactPresenceChanged.TYPE];
    
    fileprivate var connections: [Session] = [];
    
    private var cancellables: Set<AnyCancellable> = [];
    
    let queue = DispatchQueue(label: "jingleEventHandler");
    
    init() {
        if !RTCInitializeSSL() {
            let alert = NSAlert();
            alert.messageText = NSLocalizedString("Failed to initialize RTC SSL for WebRTC!", comment: "jingle manager");
            alert.runModal();
        }
        
        let path = FileManager.default.temporaryDirectory.path;
        if let files = try? FileManager.default.contentsOfDirectory(atPath: path) {
            files.filter({ $0.starts(with: "webrtc_log_") }).forEach { (file) in
                try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent(file, isDirectory: false));
            }
        }
    }
    
    func session(for context: Context, with jid: JID, sid: String?) -> Session? {
        return session(for: context.userBareJid, with: jid, sid: sid);
    }
    
    func session(for account: BareJID, with jid: JID, sid: String?) -> Session? {
        return queue.sync {
            return connections.first(where: {(sess) -> Bool in
                return sess.account == account && (sid == nil || sess.sid == sid) && (sess.jid == jid || (sess.jid.resource == nil && sess.jid.bareJid == jid.bareJid));
            });
        }
    }
    
    func open(for context: Context, with jid: JID, sid: String, role: Jingle.Content.Creator, initiationType: JingleSessionInitiationType) -> Session {
        return queue.sync {
            let session = Session(context: context, jid: jid, sid: sid, role: role, initiationType: initiationType);
            self.connections.append(session);
            session.$state.removeDuplicates().sink(receiveValue: { [weak self, weak session] state in
                guard state == .terminated, let session = session else {
                    return;
                }
                self?.close(session: session);
            }).store(in: &cancellables);
            return session;
        }
    }
    
    func close(for account: BareJID, with jid: JID, sid: String) -> Session? {
        return queue.sync {
            guard let idx = self.connections.firstIndex(where: { sess -> Bool in
                return sess.sid == sid && sess.account == account && sess.jid == jid;
            }) else {
                return nil;
            }
            let session =  self.connections.remove(at: idx);
            return session;
        }
    }
    
    func close(session: Session) {
        _ = self.close(for: session.account, with: session.jid, sid: session.sid);
    }
    
    enum ContentType {
        case audio
        case video
        case filetransfer
    }
    
    func support(for jid: JID, on account: BareJID) -> Set<ContentType> {
        guard let client = XmppService.instance.getClient(for: account) else {
            return [];
        }
        
        var features: [String] = [];
        
        if jid.resource == nil {
            PresenceStore.instance.presences(for: jid.bareJid, context: client).filter({ (p) -> Bool in
                return (p.type ?? .available) == .available;
            }).forEach({ (p) in
                guard let node = p.capsNode, let f = DBCapabilitiesCache.instance.features(for: node) else {
                    return;
                }
                features.append(contentsOf: f);
            })
        } else {
            guard let p = PresenceStore.instance.presence(for: jid, context: client), (p.type ?? .available) == .available, let node = p.capsNode, let f = DBCapabilitiesCache.instance.features(for: node) else {
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
    
    func messageInitiation(for context: Context, from jid: JID, action: Jingle.MessageInitiationAction) throws {
        switch action {
        case .propose(let id, let descriptions):
            guard self.session(for: context.userBareJid, with: jid, sid: id) == nil else {
                return;
            }
            let session = self.open(for: context, with: jid, sid: id, role: .responder, initiationType: .message);
            let media = descriptions.map({ Call.Media.from(string: $0.media) }).filter({ $0 != nil }).map({ $0! });

            let call = Call(client: context as! XMPPClient, with: jid.bareJid, sid: id, direction: .incoming, media: media);
            
            Task {
                do {
                    try await CallManager.instance.reportIncomingCall(call);
                } catch {
                    try await session.decline();
                }
            }
        case .retract(let id):
            self.sessionTerminated(account: context.userBareJid, with: jid, sid: id);
        case .accept(let id):
            self.sessionTerminated(account: context.userBareJid, sid: id);
        case .reject(let id):
            self.sessionTerminated(account: context.userBareJid, sid: id);
        case .proceed(let id):
            guard let session = self.session(for: context, with: jid, sid: id) else {
                return;
            }
            session.accepted(by: jid);
        }
    }
    
    func sessionInitiated(for context: Context, with jid: JID, sid: String, contents: [Jingle.Content], bundle: Jingle.Bundle?) throws {
        guard let content = contents.first, let _ = content.description as? Jingle.RTP.Description else {
            return;
        }

        let sdp = SDP(contents: contents, bundle: bundle);

        let media = sdp.contents.compactMap({ c -> Call.Media? in Call.Media.from(string: c.description?.media) });
        let call = Call(client: context as! XMPPClient, with: jid.bareJid, sid: sid, direction: .incoming, media: media);
        
        
        if let session = session(for: context, with: jid, sid: sid) {
            session.initiated(contents: contents, bundle: bundle);
        } else {
            let session = open(for: context, with: jid, sid: sid, role: .responder, initiationType: .iq);
            session.initiated(contents: contents, bundle: bundle);
            
            Task {
                do {
                    try await CallManager.instance.reportIncomingCall(call);
                } catch {
                    try await session.terminate();
                }
            }
        }
    }
    
    func sessionAccepted(for context: Context, with jid: JID, sid: String, contents: [Jingle.Content], bundle: Jingle.Bundle?) throws {
        guard let session = session(for: context, with: jid, sid: sid) else {
            throw XMPPError(condition: .item_not_found);
        }
               
        session.accepted(contents: contents, bundle: bundle);
    }
    
    func sessionTerminated(for context: Context, with jid: JID, sid: String) throws {
        sessionTerminated(account: context.userBareJid, with: jid, sid: sid);
    }
    
    private func sessionTerminated(account: BareJID, sid: String) {
        let toTerminate = queue.sync(execute: {
            return connections.filter({(sess) -> Bool in
                return sess.account == account && sess.sid == sid;
            });
        });
        for session in toTerminate {
            session.terminated();
        }
    }

    fileprivate func sessionTerminated(account: BareJID, with: JID, sid: String) {
        guard let session = session(for: account, with: with, sid: sid) else {
            return;
        }
        session.terminated();
    }
    

    func transportInfo(for context: Context, with jid: JID, sid: String, contents: [Jingle.Content]) throws {
        guard let session = self.session(for: context, with: jid, sid: sid) else {
            throw XMPPError(condition: .item_not_found);
        }
        
        contents.forEach { (content) in
            content.transports.forEach({ (trans) in
                if let transport = trans as? Jingle.Transport.ICEUDPTransport {
                    transport.candidates.forEach({ (candidate) in
                        session.addCandidate(candidate, for: content.name);
                    })
                }
            })
        }
    }
    
    func contentModified(for context: Context, with jid: JID, sid: String, action: Jingle.ContentAction, contents: [Jingle.Content], bundle: Jingle.Bundle?) throws {
        guard let session = self.session(for: context, with: jid, sid: sid) else {
            throw XMPPError(condition: .item_not_found);
        }
        
        session.contentModified(action: action, contents: contents, bundle: bundle);
    }
    
    func sessionInfo(for context: Context, with jid: JID, sid: String, info: [Jingle.SessionInfo]) throws {
        guard let session = self.session(for: context, with: jid, sid: sid) else {
            throw XMPPError(condition: .item_not_found);
        }
        
        session.sessionInfoReceived(info: info);
    }
}

extension JingleManager {

    func session(forCall call: Call) -> Session? {
        return queue.sync {
            return self.connections.first(where: { $0.account == call.account && $0.jid.bareJid == call.jid && $0.sid == call.sid });
        }
    }
        
}

extension String {
    static func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
        return String((0...length-1).map{ _ in letters.randomElement()! });
    }
}
