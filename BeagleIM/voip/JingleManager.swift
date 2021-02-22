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
import Combine

class JingleManager: JingleSessionManager, XmppServiceEventHandler {

    static let instance = JingleManager();
    
    let events: [Event] = [JingleModule.JingleMessageInitiationEvent.TYPE, PresenceModule.ContactPresenceChanged.TYPE];
    
    fileprivate var connections: [Session] = [];
    
    private var cancellables: Set<AnyCancellable> = [];
    
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

    func session(for context: Context, with jid: JID, sid: String?) -> Session? {
        return session(for: context.userBareJid, with: jid, sid: sid);
    }
    
    func session(for account: BareJID, with jid: JID, sid: String?) -> Session? {
        return dispatcher.sync {
            return connections.first(where: {(sess) -> Bool in
                return sess.account == account && (sid == nil || sess.sid == sid) && (sess.jid == jid || (sess.jid.resource == nil && sess.jid.bareJid == jid.bareJid));
            });
        }
    }
    
    func open(for context: Context, with jid: JID, sid: String, role: Jingle.Content.Creator, initiationType: JingleSessionInitiationType) -> Session {
        return dispatcher.sync {
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
        return dispatcher.sync {
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
    
    func handle(event: Event) {
        dispatcher.async {
            switch event {
            case let e as PresenceModule.ContactPresenceChanged:
                if e.availabilityChanged && (e.presence.type ?? .available) == .unavailable, let account = e.sessionObject.userBareJid, let from = e.presence.from {
                    let toClose = self.connections.filter({ (session) in
                        return session.jid == from && session.account == account;
                    });
                    toClose.forEach({ (session) in
                        session.terminate();
                    })
                }
            case let e as JingleModule.JingleMessageInitiationEvent:
                switch e.action! {
                case .propose(let id, let descriptions):
                    guard self.session(for: e.sessionObject.userBareJid!, with: e.jid, sid: id) == nil else {
                        return;
                    }
                    let session = self.open(for: e.context, with: e.jid, sid: id, role: .responder, initiationType: .message);
                    let media = descriptions.map({ Call.Media.from(string: $0.media) }).filter({ $0 != nil }).map({ $0! });
                    let call = Call(account: e.sessionObject.userBareJid!, with: e.jid.bareJid, sid: id, direction: .incoming, media: media);
                    CallManager.instance.reportIncomingCall(call, completionHandler: { result in
                        switch result {
                        case .success(_):
                            // nothing to do as manager will call us back..
                            break;
                        case .failure(_):
                            session.decline();
                        }
                    });
                case .retract(let id):
                    self.sessionTerminated(account: e.sessionObject.userBareJid!, with: e.jid, sid: id);
                case .accept(let id):
                    let account = e.sessionObject.userBareJid!;
                    self.sessionTerminated(account: account, sid: id);
                case .reject(let id):
                    let account = e.sessionObject.userBareJid!;
                    self.sessionTerminated(account: account, sid: id);
                case .proceed(let id):
                    guard let session = self.session(for: e.sessionObject.userBareJid!, with: e.jid, sid: id) else {
                        return;
                    }
                    session.accepted(by: e.jid);
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
        guard let client = XmppService.instance.getClient(for: account) else {
            return [];
        }
        
        var features: [String] = [];
        
        if jid.resource == nil {
            PresenceStore.instance.presences(for: jid.bareJid, context: client).filter({ (p) -> Bool in
                return (p.type ?? .available) == .available;
            }).forEach({ (p) in
                guard let node = p.capsNode, let f = DBCapabilitiesCache.instance.getFeatures(for: node) else {
                    return;
                }
                features.append(contentsOf: f);
            })
        } else {
            guard let p = PresenceStore.instance.presence(for: jid, context: client), (p.type ?? .available) == .available, let node = p.capsNode, let f = DBCapabilitiesCache.instance.getFeatures(for: node) else {
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
    
    func sessionInitiated(for context: Context, with jid: JID, sid: String, contents: [Jingle.Content], bundle: [String]?) throws {
        guard let content = contents.first, let _ = content.description as? Jingle.RTP.Description else {
            throw XMPPError.bad_request("Unsupported content type");
        }
      
        let sdp = SDP(contents: contents, bundle: bundle);

        let media = sdp.contents.compactMap({ c -> Call.Media? in Call.Media.from(string: c.description?.media) });
        let call = Call(account: context.userBareJid, with: jid.bareJid, sid: sid, direction: .incoming, media: media);

        if let session = session(for: context, with: jid, sid: sid) {
            session.initiated(contents: contents, bundle: bundle);
        } else {
            let session = open(for: context, with: jid, sid: sid, role: .responder, initiationType: .iq);
            session.initiated(contents: contents, bundle: bundle);
            
            CallManager.instance.reportIncomingCall(call, completionHandler: { result in
                switch result {
                case .success(_):
                    break;
                case .failure(_):
                    session.terminate();
                }
            })
        }
    }
    
    func sessionAccepted(for context: Context, with jid: JID, sid: String, contents: [Jingle.Content], bundle: [String]?) throws {
        guard let session = session(for: context, with: jid, sid: sid) else {
            throw XMPPError.item_not_found;
        }
        
        session.accepted(contents: contents, bundle: bundle);
    }
    
    func sessionTerminated(for context: Context, with jid: JID, sid: String) throws {
        sessionTerminated(account: context.userBareJid, with: jid, sid: sid);
    }
    
    private func sessionTerminated(account: BareJID, sid: String) {
        let toTerminate = dispatcher.sync(execute: {
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
            throw XMPPError.item_not_found;
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
    
}

extension JingleManager {

    func session(forCall call: Call) -> Session? {
        return dispatcher.sync {
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
