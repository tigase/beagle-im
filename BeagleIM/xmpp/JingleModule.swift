//
// JingleModule.swift
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

class JingleModule: XmppModule, ContextAware {
    
    static let XMLNS = "urn:xmpp:jingle:1";
    
    static let ID = XMLNS;
    
    let id = XMLNS;
    
    let criteria = Criteria.name("iq").add(Criteria.name("jingle", xmlns: XMLNS));
    
    var context: Context!;
    
    var features: [String] {
        get {
            var result = [JingleModule.XMLNS];
            result.append(contentsOf: supportedTransports.flatMap({ (type, features) in
                return features;
            }));
            result.append(contentsOf: supportedDescriptions.flatMap({ (type, features) in
                return features;
            }));
            return Array(Set(result));
        }
    }
//    var features: [String] = [XMLuNS, "urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"];
    
    fileprivate var supportedDescriptions: [(JingleDescription.Type, [String])] = [];
    fileprivate var supportedTransports: [(JingleTransport.Type, [String])] = [];

    func register(description: JingleDescription.Type, features: [String]) {
        supportedDescriptions.append((description, features));
    }
    
    func unregister(description: JingleDescription.Type) {
        guard let idx = supportedTransports.firstIndex(where: { (desc, features) -> Bool in
            return desc == description;
        }) else {
            return;
        }
        supportedDescriptions.remove(at: idx);

    }
    
    func register(transport: JingleTransport.Type, features: [String]) {
        supportedTransports.append((transport, features));
    }
    
    func unregister(transport: JingleTransport.Type) {
        guard let idx = supportedTransports.firstIndex(where: { (trans, features) -> Bool in
            return trans == transport;
        }) else {
            return;
        }
        supportedTransports.remove(at: idx);
    }
 
    func process(stanza: Stanza) throws {
        guard stanza.type ?? StanzaType.get == .set else {
            throw ErrorCondition.feature_not_implemented;
        }
        
        let jingle = stanza.findChild(name: "jingle", xmlns: JingleModule.XMLNS)!;
        
        guard let action = Jingle.Action(rawValue: jingle.getAttribute("action") ?? ""), let sid = jingle.getAttribute("sid"), let initiator = JID(jingle.getAttribute("initiator")) ?? stanza.from else {
            throw ErrorCondition.bad_request;
        }
        
        let contents = jingle.getChildren(name: "content").map({ contentEl in
            return Jingle.Content(from: contentEl, knownDescriptions: self.supportedDescriptions.map({ (desc, features) in
                return desc;
            }), knownTransports: self.supportedTransports.map({ (trans, features) in
                return trans;
            }));
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
        
        context.eventBus.fire(JingleEvent(sessionObject: context.sessionObject, jid: stanza.from!, action: action, initiator: initiator, sid: sid, contents: contents, bundle: bundle));//, session: session));
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

