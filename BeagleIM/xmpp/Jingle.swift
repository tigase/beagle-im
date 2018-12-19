//
//  Jingle.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 19/12/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

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
        
        enum Creator: String {
            case initiator
            case responder
        }
        
    }
}

protocol JingleDescription {
    
    var media: String { get };
    
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
                let tcpType: String?;
                
                convenience init?(from el: Element) {
                    guard el.name == "candidate", let foundation = UInt(el.getAttribute("foundation") ?? ""), let component = UInt8(el.getAttribute("component") ?? ""), let generation = UInt8(el.getAttribute("generation") ?? ""), let id = el.getAttribute("id"), let ip = el.getAttribute("ip"), let port = UInt16(el.getAttribute("port") ?? ""), let priority = UInt(el.getAttribute("priority") ?? "0"), let proto = ProtocolType(rawValue: el.getAttribute("protocol") ?? "") else {
                        return nil;
                    }
                    
                    let type = CandidateType(rawValue: el.getAttribute("type") ?? "");
                    self.init(component: component, foundation: foundation, generation: generation, id: id, ip: ip, network: 0, port: port, priority: priority, protocolType: proto, type: type, tcpType: el.getAttribute("tcptype"));
                }
                
                init(component: UInt8, foundation: UInt, generation: UInt8, id: String, ip: String, network: UInt8 = 0, port: UInt16, priority: UInt, protocolType: ProtocolType, relAddr: String? = nil, relPort: UInt16? = nil, type: CandidateType?, tcpType: String?) {
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
                    self.tcpType = tcpType;
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
                    el.setAttribute("tcptype", value: tcpType);
                    return el;
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
            let ssrcs: [SSRC];
            let ssrcGroups: [SSRCGroup];
            
            required convenience init?(from el: Element) {
                guard el.name == "description" && el.xmlns == "urn:xmpp:jingle:apps:rtp:1" else {
                    return nil;
                }
                guard let media = el.getAttribute("media") else {
                    return nil;
                }
                
                let payloads = el.mapChildren(transform: { e1 in return Payload(from: e1) });
                let encryption: [Encryption] = el.findChild(name: "encryption")?.mapChildren(transform: { e1 in return Encryption(from: e1) }) ?? [];
                
                let ssrcs = el.mapChildren(transform: { (source) -> SSRC? in
                    return SSRC(from: source);
                });
                let ssrcGroups = el.mapChildren(transform: { (group) -> SSRCGroup? in
                    return SSRCGroup(from: group);
                });
                
                self.init(media: media, ssrc: el.getAttribute("ssrc"), payloads: payloads, bandwidth: el.findChild(name: "bandwidth")?.getAttribute("type"), encryption: encryption, rtcpMux: el.findChild(name: "rtcp-mux") != nil, ssrcs: ssrcs, ssrcGroups: ssrcGroups);
            }
            
            init(media: String, ssrc: String? = nil, payloads: [Payload], bandwidth: String? = nil, encryption: [Encryption] = [], rtcpMux: Bool = false, ssrcs: [SSRC], ssrcGroups: [SSRCGroup]) {
                self.media = media;
                self.ssrc = ssrc;
                self.payloads = payloads;
                self.bandwidth = bandwidth;
                self.encryption = encryption;
                self.rtcpMux = rtcpMux;
                self.ssrcs = ssrcs;
                self.ssrcGroups = ssrcGroups;
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
                ssrcGroups.forEach { (group) in
                    el.addChild(group.toElement());
                }
                ssrcs.forEach({ (ssrc) in
                    el.addChild(ssrc.toElement());
                })
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
                let rtcpFeedbacks: [RtcpFeedback]?;
                
                convenience init?(from el: Element) {
                    guard el.name == "payload-type", let idStr = el.getAttribute("id"), let id = UInt8(idStr) else {
                        return nil;
                    }
                    let parameters = el.mapChildren(transform: { (el) -> Parameter? in
                        return Parameter(from: el);
                    });
                    let rtcpFb = el.mapChildren(transform: { (el) -> RtcpFeedback? in
                        return RtcpFeedback(from: el);
                    });
                    let channels = Int(el.getAttribute("channels") ?? "") ?? 1;
                    self.init(id: id, name: el.getAttribute("name"), clockrate: UInt(el.getAttribute("clockrate") ?? ""), channels: channels, ptime: UInt(el.getAttribute("ptime") ?? ""), maxptime: UInt(el.getAttribute("maxptime") ?? ""), parameters: parameters, rtcpFeedbacks: rtcpFb);
                }
                
                init(id: UInt8, name: String? = nil, clockrate: UInt? = nil, channels: Int = 1, ptime: UInt? = nil, maxptime: UInt? = nil, parameters: [Parameter]?, rtcpFeedbacks: [RtcpFeedback]?) {
                    self.id = id;
                    self.name = name;
                    self.clockrate = clockrate;
                    self.channels = channels;
                    self.ptime = ptime;
                    self.maxptime = maxptime;
                    self.parameters = parameters;
                    self.rtcpFeedbacks = rtcpFeedbacks;
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
                    rtcpFeedbacks?.forEach({ (rtcpFb) in
                        el.addChild(rtcpFb.toElement());
                    })
                    
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
                
                class RtcpFeedback {
                    
                    let type: String;
                    let subtype: String?;
                    
                    convenience init?(from el: Element) {
                        guard el.name == "rtcp-fb" && el.xmlns == "urn:xmpp:jingle:apps:rtp:rtcp-fb:0", let type = el.getAttribute("type") else {
                            return nil;
                        }
                        self.init(type: type, subtype: el.getAttribute("subtype"));
                    }
                    
                    init(type: String, subtype: String? = nil) {
                        self.type = type;
                        self.subtype = subtype;
                    }
                    
                    func toElement() -> Element {
                        let el = Element(name: "rtcp-fb", xmlns: "urn:xmpp:jingle:apps:rtp:rtcp-fb:0");
                        el.setAttribute("type", value: type);
                        el.setAttribute("subtype", value: subtype);
                        return el;
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
            
            class SSRCGroup {
                let semantics: String;
                let sources: [String];
                
                convenience init?(from el: Element) {
                    guard el.name == "ssrc-group", el.xmlns == "urn:xmpp:jingle:apps:rtp:ssma:0", let semantics = el.getAttribute("semantics") else {
                        return nil;
                    }
                    
                    let sources = el.mapChildren(transform: { (s) -> String? in
                        return s.name == "source" ? s.getAttribute("ssrc") : nil;
                    });
                    guard !sources.isEmpty else {
                        return nil;
                    }
                    self.init(semantics: semantics, sources: sources);
                }
                
                init(semantics: String, sources: [String]) {
                    self.semantics = semantics;
                    self.sources = sources;
                }
                
                func toElement() -> Element {
                    let el = Element(name: "ssrc-group", xmlns: "urn:xmpp:jingle:apps:rtp:ssma:0");
                    el.setAttribute("semantics", value: semantics);
                    sources.forEach { (source) in
                        let sel = Element(name: "source");
                        sel.setAttribute("ssrc", value: source);
                        el.addChild(sel);
                    }
                    return el;
                }
            }
            
            class SSRC {
                
                let ssrc: String;
                let parameters: [Parameter];
                
                init?(from el: Element) {
                    guard el.name == "source" && el.xmlns == "urn:xmpp:jingle:apps:rtp:ssma:0", let ssrc = el.getAttribute("ssrc") else {
                        return nil;
                    }
                    self.ssrc = ssrc;
                    self.parameters = el.mapChildren(transform: { (p) -> Parameter? in
                        guard p.name == "parameter", let key = p.getAttribute("name") else {
                            return nil;
                        }
                        return Parameter(key: key, value: p.getAttribute("value"));
                    });
                }
                
                init(ssrc: String, parameters: [Parameter]) {
                    self.ssrc = ssrc;
                    self.parameters = parameters;
                }
                
                func toElement() -> Element {
                    let el = Element(name: "source", xmlns: "urn:xmpp:jingle:apps:rtp:ssma:0");
                    el.setAttribute("ssrc", value: ssrc);
                    parameters.forEach { (param) in
                        let p = Element(name: "parameter");
                        p.setAttribute("name", value: param.key);
                        if param.value != nil {
                            p.setAttribute("value", value: param.value);
                        }
                        el.addChild(p);
                    }
                    return el;
                }
                
                class Parameter {
                    
                    let key: String;
                    let value: String?;
                    
                    init(key: String, value: String?) {
                        self.key = key;
                        self.value = value;
                    }
                    
                }
            }
            
        }
    }
}
