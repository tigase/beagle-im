//
//  JingleModule.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 18/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

class JingleModule: XmppModule, ContextAware {
    
    static let XMLNS = "urn:xmpp:jingle:1";
    
    static let ID = XMLNS;
    
    let id = XMLNS;
    
    let criteria = Criteria.name("iq").add(Criteria.name("jingle", xmlns: XMLNS));
    
    var context: Context!;
    
    var features: [String] = [XMLNS, "urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"];
    
    var supportedDescriptions: [JingleDescription.Type] = [];
    var supportedTransports: [JingleTransport.Type] = [];
    
//    var sessionManager = Jingle.SessionManager.instance;
    
    func process(stanza: Stanza) throws {
        guard stanza.type ?? StanzaType.get == .set else {
            throw ErrorCondition.feature_not_implemented;
        }
        
        let jingle = stanza.findChild(name: "jingle", xmlns: JingleModule.XMLNS)!;
        
        guard let action = Jingle.Action(rawValue: jingle.getAttribute("action") ?? ""), let sid = jingle.getAttribute("sid"), let initiator = JID(jingle.getAttribute("initiator")) ?? stanza.from else {
            throw ErrorCondition.bad_request;
        }
        
        let contents = jingle.getChildren(name: "content").map({ contentEl in
            return Jingle.Content(from: contentEl, knownDescriptions: self.supportedDescriptions, knownTransports: self.supportedTransports);
        }).filter({ content -> Bool in
            return content != nil
        }).map({ content -> Jingle.Content in
            return content!;
        });
        
        let bundle = jingle.findChild(name: "group", xmlns: "urn:xmpp:jingle:apps:grouping:0")?.mapChildren(transform: { (el) -> String? in
            return el.getAttribute("name");
        }, filter: { (el) -> Bool in
            return el.name == "content" && el.getAttribute("name") != nil;
        });
        
//        guard let session = action == .sessionInitiate ? sessionManager.getOrCreate(account: context.sessionObject.userBareJid!, jid: stanza.from!, sid: sid, initiator: initiator) : sessionManager.get(account: context.sessionObject.userBareJid!, jid: stanza.from!, sid: sid) else {
//            throw ErrorCondition.item_not_found;
//        }
        
        do {
//            try session.handle(action: action, contents: contents);
            context.eventBus.fire(JingleEvent(sessionObject: context.sessionObject, jid: stanza.from!, action: action, initiator: initiator, sid: sid, contents: contents, bundle: bundle));//, session: session));
//        } catch let err as Jingle.JingleError {
//            let reason = Element(name: "reason", children: [Element(name: err.rawValue)]);
//            terminateSession(with: stanza.from!, sid: sid, reason: reason);
        } catch let error {
//            sessionManager.close(session: session);
            throw error;
        }
    }
    
    func initiateSession(to jid: JID, sid: String, initiator: JID, contents: [Jingle.Content], bundle: [String]?, callback: @escaping (ErrorCondition?)->Void) {
        let iq = Iq();
        iq.to = jid;
        iq.type = StanzaType.set;
        
        let jingle = Element(name: "jingle", xmlns: JingleModule.XMLNS);
        jingle.setAttribute("action", value: "session-initiate");
        jingle.setAttribute("sid", value: sid);
        jingle.setAttribute("initiator", value: initiator.stringValue);
    
        iq.addChild(jingle);
        
        contents.forEach { (content) in
            jingle.addChild(content.toElement());
        }
        
        if bundle != nil {
            let group = Element(name: "group", xmlns: "urn:xmpp:jingle:apps:grouping:0");
            group.setAttribute("semantics", value: "BUNDLE");
            bundle?.forEach({ (name) in
                group.addChild(Element(name: "content", attributes: ["name": name]));
            })
            jingle.addChild(group);
        }
        
        context.writer?.write(iq, callback: { (response) in
            let error = response == nil ? ErrorCondition.remote_server_timeout : response!.errorCondition;
//            if error != nil {
//                self.sessionManager.close(account: self.context.sessionObject.userBareJid!, jid: jid, sid: sid);
//            }
            callback(error);
        });
    }
    
    func acceptSession(with jid: JID, sid: String, initiator: JID, contents: [Jingle.Content], bundle: [String]?, callback: @escaping (ErrorCondition?)->Void) {
        let iq = Iq();
        iq.to = jid;
        iq.type = StanzaType.set;
        
        let jingle = Element(name: "jingle", xmlns: JingleModule.XMLNS);
        jingle.setAttribute("action", value: "session-accept");
        jingle.setAttribute("sid", value: sid);
        jingle.setAttribute("initiator", value: initiator.stringValue);
        
        iq.addChild(jingle);
        
        contents.forEach { (content) in
            jingle.addChild(content.toElement());
        }
        
        if bundle != nil {
            let group = Element(name: "group", xmlns: "urn:xmpp:jingle:apps:grouping:0");
            group.setAttribute("semantics", value: "BUNDLE");
            bundle?.forEach({ (name) in
                group.addChild(Element(name: "content", attributes: ["name": name]));
            })
            jingle.addChild(group);
        }
        
        context.writer?.write(iq, callback: { (response) in
            let error = response == nil ? ErrorCondition.remote_server_timeout : response!.errorCondition;
            callback(error);
        });
    }
    
    func declineSession(with jid: JID, sid: String) {
        terminateSession(with: jid, sid: sid, reason: Element(name: "reason", children: [Element(name: "decline")]));
    }
    
    func terminateSession(with jid: JID, sid: String, reason: Element = Element(name: "reason", children: [Element(name: "success")])) {
        let iq = Iq();
        iq.to = jid;
        iq.type = StanzaType.set;
        
        let jingle = Element(name: "jingle", xmlns: JingleModule.XMLNS);
        jingle.setAttribute("action", value: "session-terminate");
        jingle.setAttribute("sid", value: sid);
        
        iq.addChild(jingle);

        // TODO: improve that in the future!
        
        jingle.addChild(reason);
        
        context.writer?.write(iq);
//
//        sessionManager.close(account: context.sessionObject.userBareJid!, jid: jid, sid: sid);
    }
    
    func transportInfo(with jid: JID, sid: String, contents: [Jingle.Content]) {
        let iq = Iq();
        iq.to = jid;
        iq.type = StanzaType.set;
        
        let jingle = Element(name: "jingle", xmlns: JingleModule.XMLNS);
        jingle.setAttribute("action", value: "transport-info");
        jingle.setAttribute("sid", value: sid);
        
        contents.forEach { content in
            jingle.addChild(content.toElement());
        }
        
        iq.addChild(jingle);
        
        context.writer?.write(iq);
    }
    
    class JingleEvent: Event {
        
        public static let TYPE = JingleEvent();
        
        let type = "JingleEvent";
        
        let sessionObject: SessionObject!;
        let jid: JID!;
        let action: Jingle.Action!;
        let initiator: JID!;
        let sid: String!;
        let contents: [Jingle.Content];
        let bundle: [String]?;
//        let session: Jingle.Session!;
        
        init() {
            self.sessionObject = nil;
            self.jid = nil;
            self.action = nil;
            self.initiator = nil;
            self.sid = nil;
            self.contents = [];
            self.bundle = nil;
//            self.session = nil;
        }
        
        init(sessionObject: SessionObject, jid: JID, action: Jingle.Action, initiator: JID, sid: String, contents: [Jingle.Content], bundle: [String]?) {//}, session: Jingle.Session) {
            self.sessionObject = sessionObject;
            self.jid = jid;
            self.action = action;
            self.initiator = initiator;
            self.sid = sid;
            self.contents = contents;
            self.bundle = bundle;
//            self.session = session;
        }
        
    }
}

class Jingle {
    class Content {
        
        let creator: Creator;
        let name: String;
        
        let description: JingleDescription?;
        let transports: [JingleTransport];
        
        required convenience init?(from el: Element, knownDescriptions: [JingleDescription.Type], knownTransports: [JingleTransport.Type]) {
            guard el.name == "content", let name = el.getAttribute("name"), let creator = Creator(rawValue: el.getAttribute("creator") ?? "") else {
                return nil;
            }
            
            let descEl = el.findChild(name: "description");
            let description = descEl == nil ? nil : knownDescriptions.map({ (desc) -> JingleDescription? in
                return desc.init(from: descEl!);
            }).filter({ desc -> Bool in return desc != nil}).map({ desc -> JingleDescription in return desc! }).first;
            
            let foundTransports = el.mapChildren(transform: { (child) -> JingleTransport? in
                let transports = knownTransports.map({ (type) -> JingleTransport? in
                    let transport = type.init(from: child);
                    return transport;
                });
                return transports.filter({ transport -> Bool in return transport != nil }).map({ transport -> JingleTransport in return transport!}).first;
            });
            
            self.init(name: name, creator: creator, description: description, transports: foundTransports);
        }
        
        convenience init?(fromSDP media: String, creator: Creator) {
            let sdp = media.split(separator: "\r\n");
            
            var line = sdp[0].components(separatedBy: " ");
            
            let mediaName = String(line[0].dropFirst(2));
            var name = mediaName;
            
            if let tmp = sdp.first(where: { (l) -> Bool in
                    l.starts(with: "a=mid:");
                })?.dropFirst(6) {
                name = String(tmp);
            }
            
            let payloadIds = line[3..<line.count];
            let payloads = payloadIds.map { (id) -> Jingle.RTP.Description.Payload in
                var prefix = "a=rtpmap:\(id) ";
                let l = sdp.first(where: { (s) -> Bool in
                    return s.starts(with: prefix)
                })?.dropFirst(prefix.count).components(separatedBy: "/");
                prefix = "a=fmtp:\(id) ";
                let params = sdp.first(where: { (s) -> Bool in
                    return s.starts(with: prefix);
                })?.dropFirst(prefix.count).components(separatedBy: ";").map({ (s) -> Jingle.RTP.Description.Payload.Parameter in
                    let parts = s.components(separatedBy: "=");
                    return Jingle.RTP.Description.Payload.Parameter(name: parts[0], value: parts.count > 1 ? parts[1] : "");
                });
                let clockrate = l?[1];
                let channels = ((l?.count ?? 0) > 2) ? l![2] : nil;
                return Jingle.RTP.Description.Payload(id: UInt8(id)!, name: l?[0], clockrate: clockrate != nil ? UInt(clockrate!) : nil, channels: (channels != nil ? Int(channels!) : nil) ?? 1, parameters: params);
            }
            
            let encryptions = sdp.filter { (l) -> Bool in
                return l.starts(with: "a=crypto:");
                }.map { (l) -> Jingle.RTP.Description.Encryption in
                    let parts = l.dropFirst("a=crypto:".count).components(separatedBy: " ");
                    return Jingle.RTP.Description.Encryption(cryptoSuite: parts[0], keyParams: parts[1], tag: parts[2], sessionParams: parts.count > 3 ? parts[3] : nil);
            }
            
            let description = Jingle.RTP.Description(media: mediaName, ssrc: nil, payloads: payloads, bandwidth: nil, encryption: encryptions, rtcpMux: sdp.firstIndex(of: "a=rtcp-mux") != nil);

            guard let pwd = sdp.first(where: { (l) -> Bool in
                return l.starts(with: "a=ice-pwd:");
            })?.dropFirst("a=ice-pwd:".count), let ufrag = sdp.first(where: { (l) -> Bool in
                return l.starts(with: "a=ice-ufrag:");
            })?.dropFirst("a=ice-ufrag:".count) else {
                return nil;
            }
            
            let candidates = sdp.filter { (l) -> Bool in
                return l.starts(with: "a=candidate:");
                }.map { (l) -> Jingle.Transport.ICEUDPTransport.Candidate? in
                    return Jingle.Transport.ICEUDPTransport.Candidate(fromSDP: String(l));
                }.filter { (c) -> Bool in
                    return c != nil;
                }.map { (c) -> Jingle.Transport.ICEUDPTransport.Candidate in
                    return c!;
            };
            let fingerprint = sdp.filter { (l) -> Bool in
                return l.starts(with: "a=fingerprint:");
                }.map { (l) -> Jingle.Transport.ICEUDPTransport.Fingerprint? in
                    let parts = l.dropFirst("a=fingerprint:".count).components(separatedBy: " ");
                    guard parts.count >= 2, let setupStr = sdp.first(where: { (s) -> Bool in
                        return s.starts(with: "a=setup:");
                    })?.dropFirst("a=setup:".count), let setup = Jingle.Transport.ICEUDPTransport.Fingerprint.Setup(rawValue: String(setupStr)) else {
                        return nil;
                    }
                    return Jingle.Transport.ICEUDPTransport.Fingerprint(hash: parts[0], value: parts[1], setup: setup);
                }.filter { (f) -> Bool in
                    return f != nil;
                }.map { (f) -> Jingle.Transport.ICEUDPTransport.Fingerprint in
                    return f!;
                }.first;
            let transport = Jingle.Transport.ICEUDPTransport(pwd: String(pwd), ufrag: String(ufrag), candidates: candidates, fingerprint: fingerprint);
            
            self.init(name: name, creator: creator, description: description, transports: [transport]);
        }
        
        init(name: String, creator: Creator, description: JingleDescription?, transports: [JingleTransport]) {
            self.name = name;
            self.creator = creator;
            self.description = description;
            self.transports = transports;
        }
        
        func toElement() -> Element {
            let el = Element(name: "content");
            el.setAttribute("creator", value: creator.rawValue);
            el.setAttribute("name", value: name);
            
            // TODO: add description serialization here!!
            if description != nil {
                el.addChild(description!.toElement());
            }
            transports.forEach { (transport) in
                el.addChild(transport.toElement());
            }
            
            return el;
        }
        
        func toSDP() -> String {
            var sdp: [String] = [];
            let transport = transports.first { (t) -> Bool in
                return (t as? Transport.ICEUDPTransport) != nil;
                } as? Transport.ICEUDPTransport;
            if let desc = self.description as? Jingle.RTP.Description {
                var line = "m=";
                // add support for descType == "datachannel"
                line.append("\(desc.media) 1 ");
                if (!desc.encryption.isEmpty || transport?.fingerprint != nil) {
                    line.append("RTP/SAVPF");
                } else {
                    line.append("RTP/AVPF");
                }
                
                desc.payloads.forEach { (payload) in
                    line.append(" \(payload.id)");
                }
                sdp.append(line);
            }
            
            sdp.append("c=IN IP4 0.0.0.0");
            sdp.append("a=rtcp:1 IN IP4 0.0.0.0");
            
            if let t = transport {
                sdp.append("a=ice-ufrag:\(t.ufrag)");
                sdp.append("a=ice-pwd:\(t.pwd)");
             
                if t.fingerprint != nil {
                    sdp.append("a=fingerprint:\(t.fingerprint!.hash) \(t.fingerprint!.value)");
                    sdp.append("a=setup:\(t.fingerprint!.setup.rawValue)")
                }
                
                // support for SCTP?...
            }
            
            // RTP senders always both...
            sdp.append("a=sendrecv");
            sdp.append("a=mid:\(name)")
            
            if let desc = self.description as? Jingle.RTP.Description {
                if desc.rtcpMux {
                    sdp.append("a=rtcp-mux");
                }
                desc.encryption.forEach { (e) in
                    var line = "a=crypto:\(e.tag) \(e.cryptoSuite) \(e.keyParams)";
                    if e.sessionParams != nil {
                        line.append(" \(e.sessionParams!)");
                    }
                    sdp.append(line);
                }
                
                desc.payloads.forEach { (payload) in
                    var line = "a=rtpmap:\(payload.id) \(payload.name!)/\(payload.clockrate!)";
                    if (payload.channels > 1) {
                        line.append("/\(payload.channels)");
                    }
                    sdp.append(line);
                    
                    if !(payload.parameters?.isEmpty ?? true) {
                        let value = payload.parameters!.map({ (p) -> String in
                            return "\(p.name)=\(p.value)";
                        }).joined(separator: ";");
                        sdp.append("a=fmtp:\(payload.id) \(value)");
                    }
                    // add support for payload parameters..
                    // add support for payload feedback..
                }
                // add suppprt fpr desc feedback...
            }
            
            // add support for sources...
            // add support for sources groups...
            
            if let t = transport {
                t.candidates.forEach({ c in
                    sdp.append(c.toSDP());
                });
            }
            
            return sdp.joined(separator: "\r\n");
        }
        
        enum Creator: String {
            case initiator
            case responder
        }
        
    }
}

protocol JingleDescription {

    init?(from el: Element);
    
    func toElement() -> Element;
    
}

protocol JingleTransport {
    
    var xmlns: String { get }
    
    init?(from el: Element);
    
    func toElement() -> Element;
    
}

extension Jingle {
    
    enum Action: String {
        case contentAccept = "content-accept"
        case contentAdd = "content-add"
        case contentModify = "content-modify"
        case contentReject = "content-reject"
        case descriptionInfo = "description-info"
        case securityInfo = "security-info"
        case sessionAccept = "session-accept"
        case sessionInfo = "session-info"
        case sessionInitiate = "session-initiate"
        case sessionTerminate = "session-terminate"
        case transportAccept = "transport-accept"
        case transportInfo = "transport-info"
        case transportReject = "transport-reject"
        case transportReplace = "transport-replace"
    }
    
}

extension Jingle {
    class Transport {
        class ICEUDPTransport: JingleTransport {
            static let XMLNS = "urn:xmpp:jingle:transports:ice-udp:1";
         
            let xmlns = XMLNS;
            
            let pwd: String;
            let ufrag: String;
            let candidates: [Candidate];
            let fingerprint: Fingerprint?;
            
            required convenience init?(from el: Element) {
                guard el.name == "transport" && el.xmlns == ICEUDPTransport.XMLNS else {
                    return nil;
                }
                guard let pwd = el.getAttribute("pwd"), let ufrag = el.getAttribute("ufrag") else {
                    return nil;
                }
                self.init(pwd: pwd, ufrag: ufrag, candidates: el.mapChildren(transform: { (child) -> Candidate? in
                    return Candidate(from: child);
                }, filter: { el -> Bool in
                    return el.name == "candidate";
                }), fingerprint: Fingerprint(from: el.findChild(name: "fingerprint", xmlns: "urn:xmpp:jingle:apps:dtls:0")));
            }
            
            init(pwd: String, ufrag: String, candidates: [Candidate], fingerprint: Fingerprint? = nil) {
                self.pwd = pwd;
                self.ufrag = ufrag;
                self.candidates = candidates;
                self.fingerprint = fingerprint;
            }
            
//            General requirements for DTLS-SRTP:
//
//            1. The "offer" has to contain "a=setup:actpass".
//
//            2. The "answer" has to contain either "a=setup:active" (recommended) OR "a=setup:passive".
//
//            2.1. If a=setup:active in the "answer" SDP then start DTLS handshake(send client hello) since you are the active end of the DTLS connection
//
//            2.2 If a=setup:passive in the "answer" SDP then don't start DTLS handshake. Send the "answer" sdp and wait for DTLS connection from the other side.
//
//
//            3. The certificate presented in the handshake MUST match the fingerprint in the SDP for both "offer" and "answer". If it does not match endpoints MUST tear down the media session.
//
//            4 Early Media requirements:
//
//            If an endpoint wishes to provide "early media". It MUST take the "setup:active" role and immediately establish DTLS association.
//
//            5 Session Modification requirements:
//
//            5.1 Either endpoint may modify the session using INV/UPDATE. If the new SDP offer/answer contains the same "fingerprints and transports" peers can reuse the same DTLS association OR teardown the existing and establish a new one.[ You have to make a choice here or make it configurable ?]
//
//            5.2 If the active/passive status of the endpoints changes (i.e role changes) then a new connection MUST be established.
            
            func toElement() -> Element {
                let el = Element(name: "transport", xmlns: ICEUDPTransport.XMLNS);
                if fingerprint != nil {
                    el.addChild(fingerprint!.toElement());
                }
                self.candidates.forEach { (candidate) in
                    el.addChild(candidate.toElement());
                }
                el.setAttribute("ufrag", value: self.ufrag);
                el.setAttribute("pwd", value: self.pwd);
                return el;
            }

            class Fingerprint {
                let hash: String;
                let value: String;
                let setup: Setup;
                
                convenience init?(from elem: Element?) {
                    guard let el = elem else {
                        return nil;
                    }
                    guard let hash = el.getAttribute("hash"), let value = el.value, let setup = Setup(rawValue: el.getAttribute("setup") ?? "") else {
                        return nil;
                    }
                    self.init(hash: hash, value: value, setup: setup);
                }
                                
                init(hash: String, value: String, setup: Setup) {
                    self.hash = hash;
                    self.value = value;
                    self.setup = setup;
                }

                func toElement() -> Element {
                    let fingerprintEl = Element(name: "fingerprint", cdata: value, xmlns: "urn:xmpp:jingle:apps:dtls:0");
                    fingerprintEl.setAttribute("hash", value: hash);
                    fingerprintEl.setAttribute("setup", value: setup.rawValue);
                    return fingerprintEl;
                }
                
                enum Setup: String {
                    case actpass
                    case active
                    case passive
                }
            }
            
            class Candidate {
                let component: UInt8;
                let foundation: UInt;
                let generation: UInt8;
                let id: String;
                let ip: String;
                let network: UInt8;
                let port: UInt16;
                let priority: UInt;
                let protocolType: ProtocolType;
                let relAddr: String?;
                let relPort: UInt16?;
                let type: CandidateType?;
                
                convenience init?(from el: Element) {
                    guard el.name == "candidate", let foundation = UInt(el.getAttribute("foundation") ?? ""), let component = UInt8(el.getAttribute("component") ?? ""), let generation = UInt8(el.getAttribute("generation") ?? ""), let id = el.getAttribute("id"), let ip = el.getAttribute("ip"), let port = UInt16(el.getAttribute("port") ?? ""), let priority = UInt(el.getAttribute("priority") ?? "0"), let proto = ProtocolType(rawValue: el.getAttribute("protocol") ?? "") else {
                        return nil;
                    }
                    
                    let type = CandidateType(rawValue: el.getAttribute("type") ?? "");
                    self.init(component: component, foundation: foundation, generation: generation, id: id, ip: ip, network: 0, port: port, priority: priority, protocolType: proto, type: type);
                }
                
                convenience init?(fromSDP l: String) {
                    let parts = l.dropFirst("a=candidate:".count).components(separatedBy: " ");
                    guard parts.count >= 10 else {
                        return nil;
                    }
                    guard let foundation = UInt(parts[0]), let component = UInt8(parts[1]), let protoType = Jingle.Transport.ICEUDPTransport.Candidate.ProtocolType(rawValue: parts[2].lowercased()), let priority = UInt(parts[3]), let port = UInt16(parts[5]), let type = Jingle.Transport.ICEUDPTransport.Candidate.CandidateType(rawValue: parts[7]) else {
                        return nil
                    }
                    let ip = parts[4];
                    let relAddr = parts.count >= 14 ? parts[9] : nil;
                    let relPort = parts.count >= 14 ? parts[11] : nil;
                    guard let generation = UInt8(parts[parts.count >= 14 ? 13 : 9]) else {
                        return nil;
                    }
                    self.init(component: component, foundation: foundation, generation: generation, id: UUID().uuidString, ip: ip, network: 0, port: port, priority: priority, protocolType: protoType, relAddr: relAddr, relPort: relPort == nil ? nil : UInt16(relPort!), type: type);
                }
                
                init(component: UInt8, foundation: UInt, generation: UInt8, id: String, ip: String, network: UInt8 = 0, port: UInt16, priority: UInt, protocolType: ProtocolType, relAddr: String? = nil, relPort: UInt16? = nil, type: CandidateType?) {
                    self.component = component;
                    self.foundation = foundation;
                    self.generation = generation;
                    self.id = id;
                    self.ip = ip;
                    self.network = network;
                    self.port = port;
                    self.priority = priority;
                    self.protocolType = protocolType;
                    self.relAddr = relAddr;
                    self.relPort = relPort;
                    self.type = type;
                }
                
                func toElement() -> Element {
                    let el = Element(name: "candidate");
                    
                    el.setAttribute("component", value: String(component));
                    el.setAttribute("foundation", value: String(foundation));
                    el.setAttribute("generation", value: String(generation));
                    el.setAttribute("id", value: id);
                    el.setAttribute("ip", value: ip);
                    el.setAttribute("network", value: String(network));
                    el.setAttribute("port", value: String(port));
                    el.setAttribute("protocol", value: protocolType.rawValue);
                    el.setAttribute("priority", value: String(priority));
                    if relAddr != nil {
                        el.setAttribute("rel-addr", value: relAddr);
                    }
                    if relPort != nil {
                        el.setAttribute("rel-port", value: String(relPort!));
                    }
                    el.setAttribute("type", value: type?.rawValue);
                    
                    return el;
                }
                
                func toSDP() -> String {
                    var sdp = "a=candidate:\(foundation) \(component) \(protocolType.rawValue.uppercased()) \(priority) \(ip) \(port) typ \((type ?? .host).rawValue)";
                    if (type ?? .host) != .host {
                        if relAddr != nil && relPort != nil {
                            sdp.append(" raddr \(relAddr!) rport \(relPort!)");
                        }
                    }
                    
                    // support for TCP? (TCP??)
                    
                    sdp.append(" generation \(generation)");
                    return sdp;
                }
                
                enum ProtocolType: String {
                    case udp
                    case tcp
                }
                
                enum CandidateType: String {
                    case host
                    case prflx
                    case relay
                    case srflx
                }
            }

        }
        
        class RawUDPTransport: JingleTransport {
            
            static let XMLNS = "urn:xmpp:jingle:transports:raw-udp:1";
            
            let xmlns = XMLNS;
            
            let candidates: [Candidate];
            
            required convenience init?(from el: Element) {
                guard el.name == "transport" && el.xmlns == RawUDPTransport.XMLNS else {
                    return nil;
                }
                
                self.init(candidates: el.mapChildren(transform: { (child) -> Candidate? in
                    return Candidate(from: child);
                }));
            }
            
            init(candidates: [Candidate]) {
                self.candidates = candidates;
            }
            
            func toElement() -> Element {
                let el = Element(name: "transport", xmlns: RawUDPTransport.XMLNS);
                self.candidates.forEach { (candidate) in
                    el.addChild(candidate.toElement());
                }
                return el;
            }
            
            class Candidate {
                let component: UInt8;
                let generation: UInt8;
                let id: String;
                let ip: String;
                let port: UInt16;
                let type: CandidateType?;
                
                convenience init?(from el: Element) {
                    guard el.name == "candidate", let component = UInt8(el.getAttribute("component") ?? ""), let generation = UInt8(el.getAttribute("generation") ?? ""), let id = el.getAttribute("id"), let ip = el.getAttribute("ip"), let port = UInt16(el.getAttribute("port") ?? "") else {
                        return nil;
                    }
                    
                    let type = CandidateType(rawValue: el.getAttribute("type") ?? "");
                    self.init(component: component, generation: generation, id: id, ip: ip, port: port, type: type);
                }
                
                init(component: UInt8, generation: UInt8, id: String, ip: String, port: UInt16, type: CandidateType?) {
                    self.component = component;
                    self.generation = generation;
                    self.id = id;
                    self.ip = ip;
                    self.port = port;
                    self.type = type;
                }
                
                func toElement() -> Element {
                    let el = Element(name: "candidate");
                    
                    el.setAttribute("component", value: String(component));
                    el.setAttribute("generation", value: String(generation));
                    el.setAttribute("id", value: id);
                    el.setAttribute("ip", value: ip);
                    el.setAttribute("port", value: String(port));
                    el.setAttribute("type", value: type?.rawValue);
                    
                    return el;
                }
                
                enum CandidateType: String {
                    case host
                    case prflx
                    case relay
                    case srflx
                }
            }
            
        }
    }
}

extension Jingle {
    class RTP {
        class Description: JingleDescription {
            
            let media: String;
            let ssrc: String?;
            
            let payloads: [Payload];
            let bandwidth: String?;
            let rtcpMux: Bool;
            let encryption: [Encryption];
            
            required convenience init?(from el: Element) {
                guard el.name == "description" && el.xmlns == "urn:xmpp:jingle:apps:rtp:1" else {
                    return nil;
                }
                guard let media = el.getAttribute("media") else {
                    return nil;
                }
                
                let payloads = el.mapChildren(transform: { e1 in return Payload(from: e1) });
                let encryption: [Encryption] = el.findChild(name: "encryption")?.mapChildren(transform: { e1 in return Encryption(from: e1) }) ?? [];
                
                self.init(media: media, ssrc: el.getAttribute("ssrc"), payloads: payloads, bandwidth: el.findChild(name: "bandwidth")?.getAttribute("type"), encryption: encryption, rtcpMux: el.findChild(name: "rtcp-mux") != nil);
            }
            
            init(media: String, ssrc: String? = nil, payloads: [Payload], bandwidth: String? = nil, encryption: [Encryption] = [], rtcpMux: Bool = false) {
                self.media = media;
                self.ssrc = ssrc;
                self.payloads = payloads;
                self.bandwidth = bandwidth;
                self.encryption = encryption;
                self.rtcpMux = rtcpMux;
            }
            
            func toElement() -> Element {
                let el = Element(name: "description", xmlns: "urn:xmpp:jingle:apps:rtp:1");
                el.setAttribute("media", value: media);
                el.setAttribute("ssrc", value: ssrc);
                
                payloads.forEach { (payload) in
                    el.addChild(payload.toElement());
                }
                
                if !encryption.isEmpty {
                    let encEl = Element(name: "encryption")
                    encryption.forEach { enc in
                        encEl.addChild(enc.toElement());
                    }
                    el.addChild(encEl);
                }
                
                if bandwidth != nil {
                    el.addChild(Element(name: "bandwidth", attributes: ["type": bandwidth!]));
                }
                if rtcpMux {
                    el.addChild(Element(name: "rtcp-mux"));
                }
                return el;
            }
            
            class Payload {
                let id: UInt8;
                let channels: Int;
                let clockrate: UInt?;
                let maxptime: UInt?;
                let name: String?;
                let ptime: UInt?;
                
                let parameters: [Parameter]?;
                
                convenience init?(from el: Element) {
                    guard el.name == "payload-type", let idStr = el.getAttribute("id"), let id = UInt8(idStr) else {
                        return nil;
                    }
                    let parameters = el.mapChildren(transform: { (el) -> Parameter? in
                        return Parameter(from: el);
                    });
                    let channels = Int(el.getAttribute("channels") ?? "") ?? 1;
                    self.init(id: id, name: el.getAttribute("name"), clockrate: UInt(el.getAttribute("clockrate") ?? ""), channels: channels, ptime: UInt(el.getAttribute("ptime") ?? ""), maxptime: UInt(el.getAttribute("maxptime") ?? ""), parameters: parameters);
                }
                
                init(id: UInt8, name: String? = nil, clockrate: UInt? = nil, channels: Int = 1, ptime: UInt? = nil, maxptime: UInt? = nil, parameters: [Parameter]?) {
                    self.id = id;
                    self.name = name;
                    self.clockrate = clockrate;
                    self.channels = channels;
                    self.ptime = ptime;
                    self.maxptime = maxptime;
                    self.parameters = parameters;
                }
                
                func toElement() -> Element {
                    let el = Element(name: "payload-type");
                    
                    el.setAttribute("id", value: String(id));
                    if channels != 1 {
                        el.setAttribute("channels", value: String(channels));
                    }
                    
                    el.setAttribute("name", value: name);
                    
                    if let clockrate = self.clockrate {
                        el.setAttribute("clockrate", value: String(clockrate));
                    }
                    
                    if let ptime = self.ptime {
                        el.setAttribute("ptime", value: String(ptime));
                    }
                    if let maxptime = self.maxptime {
                        el.setAttribute("maxptime", value: String(maxptime));
                    }
                    
                    parameters?.forEach { param in
                        el.addChild(param.toElement());
                    }
                    
                    return el;
                }
                
                class Parameter {
                    
                    let name: String;
                    let value: String;
                    
                    convenience init?(from el: Element) {
                        guard el.name == "parameter" &&  (el.xmlns == "urn:xmpp:jingle:apps:rtp:1" || el.xmlns == nil), let name = el.getAttribute("name"), let value = el.getAttribute("value") else {
                            return nil;
                        }
                        self.init(name: name, value: value);
                    }
                    
                    init(name: String, value: String) {
                        self.name = name;
                        self.value = value;
                    }
                    
                    func toElement() -> Element {
                        return Element(name: "parameter", attributes: ["name": name, "value": value, "xmlns": "urn:xmpp:jingle:apps:rtp:1"]);
                    }
                }
            }
            
            class Encryption {
                
                let cryptoSuite: String;
                let keyParams: String;
                let sessionParams: String?;
                let tag: String;
                
                convenience init?(from el: Element) {
                    guard let cryptoSuite = el.getAttribute("crypto-suite"), let keyParams = el.getAttribute("key-params"), let tag = el.getAttribute("tag") else {
                        return nil;
                    }
                    
                    self.init(cryptoSuite: cryptoSuite, keyParams: keyParams, tag: tag, sessionParams: el.getAttribute("session-params"));
                }
                
                init(cryptoSuite: String, keyParams: String, tag: String, sessionParams: String? = nil) {
                    self.cryptoSuite = cryptoSuite;
                    self.keyParams = keyParams;
                    self.sessionParams = sessionParams;
                    self.tag = tag;
                }
                
                func toElement() -> Element {
                    let el = Element(name: "crypto");
                    el.setAttribute("crypto-suite", value: cryptoSuite);
                    el.setAttribute("key-params", value: keyParams);
                    el.setAttribute("session-params", value: sessionParams);
                    el.setAttribute("tag", value: tag);
                    return el;
                }
                
            }
        }
    }
}

protocol JingleClosableProtocol {
    
    func close();
    
}

extension Jingle {
//    class Session {
//        let sid: String;
//        let account: BareJID;
//        let jid: JID;
//        let initiator: JID;
//        let delegate: JingleSessionManagerDelegateProtocol?;
//    
//        fileprivate var closeables: [JingleClosableProtocol] = [];
//        
//        init(delegate: JingleSessionManagerDelegateProtocol?, account: BareJID, jid: JID, sid: String, initiator: JID) {
//            self.account = account;
//            self.jid = jid;
//            self.sid = sid;
//            self.initiator = initiator;
//            self.delegate = delegate;
//            
//            delegate?.created(session: self);
//        }
//        
//        func initiate(contents: [Jingle.Content]) -> Bool {
//            guard let jingleModule: JingleModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(JingleModule.ID) else {
//                return false;
//            }
//            
//            delegate?.initiate(session: self);
//            jingleModule.initiateSession(to: jid, sid: sid, initiator: initiator, contents: contents) { (error) in
//                if (error != nil) {
//                    self.onError(error!);
//                }
//            }
//            return true;
//        }
//    
//        func accept(contents: [Jingle.Content]) -> Bool {
//            guard let jingleModule: JingleModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(JingleModule.ID) else {
//                return false;
//            }
//            
//            delegate?.accept(session: self);
//            jingleModule.acceptSession(with: jid, sid: sid, initiator: initiator, contents: contents) { (error) in
//                if (error != nil) {
//                    self.onError(error!);
//                }
//            }
//            
//            return true;
//        }
//        
//        func decline() -> Bool {
//            guard let jingleModule: JingleModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(JingleModule.ID) else {
//                return false;
//            }
//            
//            jingleModule.declineSession(with: jid, sid: sid);
//            return true;
//        }
//        
//        func transportInfo(contentName: String, creator: Jingle.Content.Creator, transport: JingleTransport) -> Bool {
//            guard let jingleModule: JingleModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(JingleModule.ID) else {
//                return false;
//            }
//
//            jingleModule.transportInfo(with: jid, sid: sid, contents: [Jingle.Content(name: contentName, creator: creator, description: nil, transports: [transport])]);
//            return true;
//        }
//        
//        func handle(action: Jingle.Action, contents: [Content]) throws {
//            switch action {
//            case .sessionInitiate:
//                try self.delegate?.validate(contents: contents);
////                self.contents = contents;
//            case .sessionAccept:
//                // should do a better checks here!
//                try self.delegate?.validate(contents: contents);
////                self.contents = contents;
//            case .sessionTerminate:
//                self.onTerminate();
//            default:
//                // nothing to do...
//                break;
//            }
//        }
//        
//        func register(closeable: JingleClosableProtocol) {
//            self.closeables.append(closeable);
//        }
//        
//        fileprivate func onError(_ error: ErrorCondition) {
//            print("received an error:", error);
//        }
//        
//        fileprivate func onTerminate() {
//            self.closeables.forEach { (closeable) in
//                closeable.close();
//            }
//            delegate?.terminated(session: self);
//        }
//        
//    }
    
//    class SessionManager {
//        static let instance = SessionManager();
//
//        weak var sessionManagerDelegate: JingleSessionManagerDelegateProtocol?;
//
//        fileprivate let dispatcher = QueueDispatcher(label: "jingle.session_manager");
//        fileprivate var sessions: [Session] = [];
//
//        func create(account: BareJID, jid: JID, sid: String, initiator: JID) -> Session? {
//            return dispatcher.sync {
//                guard let session = self.sessions.filter({ (sess) -> Bool in
//                    return sess.sid == sid && sess.account == account && sess.jid == jid;
//                }).first else {
//                    let session = Session(delegate: sessionManagerDelegate, account: account, jid: jid, sid: sid, initiator: initiator);
//                    self.sessions.append(session);
//                    return session;
//                }
//                return nil;
//            }
//        }
//
//        func getOrCreate(account: BareJID, jid: JID, sid: String, initiator: JID) -> Session {
//            return dispatcher.sync {
//                guard let session = self.sessions.filter({ (sess) -> Bool in
//                    return sess.sid == sid && sess.account == account && sess.jid == jid;
//                }).first else {
//                    let session = Session(delegate: sessionManagerDelegate, account: account, jid: jid, sid: sid, initiator: initiator);
//                    self.sessions.append(session);
//                    return session;
//                }
//                return session;
//            }
//        }
//
//        func get(account: BareJID, jid: JID, sid: String) -> Session? {
//            return dispatcher.sync {
//                return self.sessions.filter({ (sess) -> Bool in
//                    return sess.sid == sid && sess.account == account && sess.jid == jid;
//                }).first;
//            }
//        }
//
//        @discardableResult func close(session: Session) -> Session? {
//            return dispatcher.sync {
//                guard let idx = self.sessions.firstIndex(where: { (sess) -> Bool in
//                    session === sess;
//                }) else {
//                    return nil;
//                }
//                self.sessions.remove(at: idx);
//                session.onTerminate();
//                return session;
//            }
//        }
//
//        @discardableResult func close(account: BareJID, jid: JID, sid: String) -> Session? {
//            return dispatcher.sync {
//                guard let idx = self.sessions.firstIndex(where: { (sess) -> Bool in
//                    return sess.sid == sid && sess.account == account && sess.jid == jid;
//                }) else {
//                    return nil;
//                }
//                let session = self.sessions.remove(at: idx);
//                session.onTerminate();
//                return session;
//            }
//        }
//    }
    
}

//protocol JingleSessionManagerDelegateProtocol: class {
//
//    func created(session: Jingle.Session);
//
//    func initiate(session: Jingle.Session);
//
//    func accept(session: Jingle.Session);
//
//    func terminated(session: Jingle.Session);
//
//    func validate(contents: [Jingle.Content]) throws;
//
//}

protocol JingleTransportImplProtocol {
    
    func prepareOffer(completionHandler: (Jingle.Transport?)->Void);
    
    func start(config: Jingle.Transport);
    
    func stop();
    
}

//extension Jingle {
//
//    class SessionManagerDelegate: JingleSessionManagerDelegateProtocol {
//
//        func created(session: Jingle.Session) {
//
//        }
//
//        func initiate(session: Jingle.Session) {
//
//        }
//
//        func accept(session: Jingle.Session) {
//
//        }
//
//        func terminated(session: Jingle.Session) {
//
//        }
//
//        func validate(contents: [Jingle.Content]) throws {
//            guard !contents.isEmpty else {
//                throw ErrorCondition.bad_request;
//            }
//
//            try contents.forEach { content in
//                guard let description = content.description as? Jingle.RTP.Description else {
//                    throw ErrorCondition.bad_request;
//                }
//                guard isMediaSupported(description.media) else {
//                    throw JingleError.failedApplication;
//                }
//                guard !content.transports.isEmpty else {
//                    throw JingleError.unsupportedTransports;
//                }
//            }
//        }
//
//        func isMediaSupported(_ media: String) -> Bool {
//            return "audio" == media;
//        }
//    }
//
//    enum JingleError: String, Error {
//        case busy = "busy";
//        case unsupportedTransports = "unsupported-transports";
//        case failedTransport = "failed-transport";
//        case failedApplication = "failed-application";
//        case incompatibleParameters = "incompatible-parameters";
//    }
//}


class SDP {
    
    let id: String;
    let sid: String;
    let contents: [Jingle.Content];
    let bundle: [String]?;
    
    init(sid: String, contents: [Jingle.Content], bundle: [String]?) {
        self.id = "\(Date().timeIntervalSince1970)";
        self.sid = sid;
        self.contents = contents;
        self.bundle = bundle;
    }
    
    init?(from sdp: String, creator: Jingle.Content.Creator) {
        var media = sdp.components(separatedBy: "\r\nm=");
        for i in 1..<media.count {
            media[i] = "m=" + media[i];
        }
        media[media.count-1] = String(media[media.count-1].dropLast(2));
        
        let sessionLines = media.remove(at: 0).components(separatedBy: "\r\n");
        
        guard let sessionLine = sessionLines.first(where: { (line) -> Bool in
            return line.starts(with: "o=");
        })?.components(separatedBy: " "), sessionLine.count > 3 else {
            return nil;
        }
        
        self.sid = sessionLine[1];
        self.id = sessionLine[2];
        let groupParts = sessionLines.first(where: { s -> Bool in
            return s.starts(with: "a=group:BUNDLE ");
        })?.split(separator: " ") ?? [ "" ];
        self.bundle = groupParts[0] == "a=group:BUNDLE" ? groupParts.dropFirst().map({ s -> String in return String(s); }) : nil;
        
        self.contents = media.map({ m -> Jingle.Content? in
            return Jingle.Content(fromSDP: m, creator: creator);
        }).filter({ (c) -> Bool in
            return c != nil;
        }).map({ (c) -> Jingle.Content in
            return c!;
        });
    }
    
    func toString() -> String {
        var sdp = [
            "v=0", "o=- \(sid) \(id) IN IP4 0.0.0.0", "s=-", "t=0 0"
        ];
        
        if bundle != nil {
            var t = [ "a=group:BUNDLE" ];
            t.append(contentsOf: self.bundle!);
            sdp.append(t.joined(separator: " "));
        }
        
        let contents: [String] = self.contents.map({ c -> String in
            return c.toSDP();
        });
        sdp.append(contentsOf: contents);
        
        return sdp.joined(separator: "\r\n") + "\r\n";
    }
}
