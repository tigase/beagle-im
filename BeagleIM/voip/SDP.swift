//
// SDP.swift
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


extension Jingle.Content {
    
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
            prefix = "a=rtcp-fb:\(id) ";
            let rtcpFb = sdp.filter({ (s) -> Bool in
                return s.starts(with: prefix);
            }).map({ s -> Substring in
                return s.dropFirst(prefix.count);
            }).map({ (s) -> Jingle.RTP.Description.Payload.RtcpFeedback in
                let parts = s.components(separatedBy: " ");
                return Jingle.RTP.Description.Payload.RtcpFeedback(type: parts[0], subtype: parts.count > 1 ? parts[1] : nil);
            });
            let clockrate = l?[1];
            let channels = ((l?.count ?? 0) > 2) ? l![2] : nil;
            return Jingle.RTP.Description.Payload(id: UInt8(id)!, name: l?[0], clockrate: clockrate != nil ? UInt(clockrate!) : nil, channels: (channels != nil ? Int(channels!) : nil) ?? 1, parameters: params, rtcpFeedbacks: rtcpFb);
        }
        
        let encryptions = sdp.filter { (l) -> Bool in
            return l.starts(with: "a=crypto:");
            }.map { (l) -> Jingle.RTP.Description.Encryption in
                let parts = l.dropFirst("a=crypto:".count).components(separatedBy: " ");
                return Jingle.RTP.Description.Encryption(cryptoSuite: parts[0], keyParams: parts[1], tag: parts[2], sessionParams: parts.count > 3 ? parts[3] : nil);
        }
        
        let ssrcs: [Jingle.RTP.Description.SSRC] = Jingle.RTP.Description.SSRC.parse(sdpLines: sdp);
        let ssrcGroups: [Jingle.RTP.Description.SSRCGroup] = Jingle.RTP.Description.SSRCGroup.parse(sdpLines: sdp);
        let description = Jingle.RTP.Description(media: mediaName, ssrc: nil, payloads: payloads, bandwidth: nil, encryption: encryptions, rtcpMux: sdp.firstIndex(of: "a=rtcp-mux") != nil, ssrcs: ssrcs, ssrcGroups: ssrcGroups);
        
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

    func toSDP() -> String {
        var sdp: [String] = [];
        let transport = transports.first { (t) -> Bool in
            return (t as? Jingle.Transport.ICEUDPTransport) != nil;
            } as? Jingle.Transport.ICEUDPTransport;
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
        
        if description?.media == "audio" || description?.media == "video" {
            sdp.append("a=rtcp:1 IN IP4 0.0.0.0");
        }
        
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
        
        if let desc = self.description as? Jingle.RTP.Description, description?.media == "audio" || description?.media == "video" {
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
                payload.rtcpFeedbacks?.forEach({ (rtcpFb) in
                    if rtcpFb.subtype == nil {
                        sdp.append("a=rtcp-fb:\(payload.id) \(rtcpFb.type)");
                    } else {
                        sdp.append("a=rtcp-fb:\(payload.id) \(rtcpFb.type) \(rtcpFb.subtype!)");
                    }
                })
                // add support for payload parameters..
                // add support for payload feedback..
            }
            
            desc.ssrcGroups.forEach { (group) in
                sdp.append(group.toSDP());
            }
            desc.ssrcs.forEach { (ssrc) in
                sdp.append(contentsOf: ssrc.toSDP());
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
}

extension Jingle.Transport.ICEUDPTransport.Candidate {
    
    convenience init?(fromSDP l: String) {
        let parts = l.dropFirst("a=candidate:".count).components(separatedBy: " ");
        guard parts.count >= 10 else {
            return nil;
        }
        guard let foundation = UInt(parts[0]), let component = UInt8(parts[1]), let protoType = Jingle.Transport.ICEUDPTransport.Candidate.ProtocolType(rawValue: parts[2].lowercased()), let priority = UInt(parts[3]), let port = UInt16(parts[5]), let type = Jingle.Transport.ICEUDPTransport.Candidate.CandidateType(rawValue: parts[7]) else {
            return nil
        }
        let ip = parts[4];
        
        var relAddr: String?;
        var relPort: String?;
        var generation: UInt8?;
        var tcptype: String?;
        var networkId: String?;
        var networkCost: String?;
        
        var i = 8;
        while parts.count >= i + 2 {
            let key = parts[i];
            let val = parts[i + 1];
            switch key {
            case "tcptype":
                tcptype = val;
            case "generation":
                generation = UInt8(val);
            case "network-id":
                networkId = val;
            case "network-cost":
                networkCost = val;
            case "raddr":
                relAddr = val;
            case "rport":
                relPort = val;
            default:
                i = i + 1;
                continue;
            }
            i = i + 2;
        }
        
        guard generation != nil else {
            return nil;
        }
        
        self.init(component: component, foundation: foundation, generation: generation!, id: UUID().uuidString, ip: ip, network: 0, port: port, priority: priority, protocolType: protoType, relAddr: relAddr, relPort: relPort == nil ? nil : UInt16(relPort!), type: type, tcpType: tcptype);
    }

    func toSDP() -> String {
        var sdp = "a=candidate:\(foundation) \(component) \(protocolType.rawValue.uppercased()) \(priority) \(ip) \(port) typ \((type ?? .host).rawValue)";
        if (type ?? .host) != .host {
            if relAddr != nil && relPort != nil {
                sdp.append(" raddr \(relAddr!) rport \(relPort!)");
            }
        }
        
        if protocolType == .tcp && tcpType != nil {
            sdp.append(" tcptype \(tcpType!)");
        }
        
        sdp.append(" generation \(generation)");
        return sdp;
    }
}

extension Jingle.RTP.Description.SSRCGroup {
    
    func toSDP() -> String {
        return "a=ssrc-group:\(semantics) \(sources.joined(separator: " "))";
    }
    
    static func parse(sdpLines: [String.SubSequence]) -> [Jingle.RTP.Description.SSRCGroup] {
        let ssrcGroupLines = sdpLines.filter { (line) -> Bool in
            return line.starts(with: "a=ssrc-group:");
            }.map { (s) -> Substring in
                return s.dropFirst("a=ssrc-group:".count);
        };
        return ssrcGroupLines.map { (line) -> [Substring] in
            return line.split(separator: " ");
            }.filter { (parts) -> Bool in
                return parts.count >= 2;
            }.map { (parts) -> Jingle.RTP.Description.SSRCGroup in
                return Jingle.RTP.Description.SSRCGroup(semantics: String(parts.first!), sources: parts.dropFirst().map({ (source) -> String in
                    return String(source);
                }));
        }
    }

}

extension Jingle.RTP.Description.SSRC {
    
    func toSDP() -> [String] {
        return parameters.map({ (param) -> String in
            return "a=ssrc:\(ssrc) \(param.toSDP())";
        })
    }
    
    static func parse(sdpLines: [String.SubSequence]) -> [Jingle.RTP.Description.SSRC] {
        let ssrcLines = sdpLines.filter { (line) -> Bool in
            return line.starts(with: "a=ssrc:");
        }
        return Set(ssrcLines.map({ (line) -> String in
            String(line.dropFirst("a=ssrc:".count).split(separator: " ").first!)
        })).map { (ssrc) in
            let prefix = "a=ssrc:\(ssrc) ";
            let params = ssrcLines.filter({ (line) -> Bool in
                return line.starts(with: prefix);
            }).map({ line -> Parameter? in
                let parts = line.dropFirst(prefix.count).split(separator: ":");
                if let key = parts.first, !key.isEmpty {
                    return Jingle.RTP.Description.SSRC.Parameter(key: String(key), value: parts.count == 1 ? nil : String(parts.dropFirst().joined(separator: ":")));
                } else {
                    return nil;
                }
            }).filter({ param -> Bool in
                return param != nil;
            }).map({ param -> Parameter in
                return param!;
            })
            return Jingle.RTP.Description.SSRC(ssrc: ssrc, parameters: params);
        }
    }

}

extension Jingle.RTP.Description.SSRC.Parameter {
    
    func toSDP() -> String {
        guard value != nil else {
            return key;
        }
        return "\(key):\(value!)";
    }

}
