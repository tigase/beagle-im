//
// MeetManager.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import Combine
import TigaseSwift
import TigaseLogging

class MeetManager {
    
    public static let instance = MeetManager();
    
    private let dispatcher = QueueDispatcher(label: "MeetManager");
    private var meets: [Key:Meet] = [:]
    
    public func registerMeet(at jid: JID, using client: XMPPClient) -> Meet? {
        return dispatcher.sync {
            let key = Key(account: client.userBareJid, jid: jid.bareJid);
            
            guard let meet = meets[key] else {
                let meet = Meet(client: client, jid: jid);
                meets[key] = meet;
                return meet;
            }
            
            return meet;
        }
    }
    
    public func registerMeet(at jid: JID, using account: BareJID) -> Meet? {
        guard let client = XmppService.instance.getClient(for: account) else {
            return nil;
        }
        
        return registerMeet(at: jid, using: client);
    }
    
    public func unregister(meet: Meet) {
        dispatcher.sync {
            meets.removeValue(forKey: Key(account: meet.client.userBareJid, jid: meet.jid.bareJid));
        }
    }
    
    public func reportIncoming(call: Call) -> Bool {
        return dispatcher.sync {
            guard let meet = meets[Key(account: call.account, jid: call.jid)] else {
                return false;
            }
            meet.setIncomingCall(call);
            call.accept();
            return true;
        }
    }
    
    private struct Key: Hashable {
        let account: BareJID;
        let jid: BareJID;
    }
}

class Meet {
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "meet")
    
    let client: XMPPClient;
    let jid: JID;
    
    init(client: XMPPClient, jid: JID) {
        self.client = client;
        self.jid = jid;
    }
    
    @Published
    fileprivate(set) var outgoingCall: Call?;
    @Published
    fileprivate(set) var incomingCall: Call?;
    
    public func join() {
        let call = Call(account: client.userBareJid, with: jid.bareJid, sid: UUID().uuidString, direction: .outgoing, media: [.audio, .video]);
        call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        call.changeState(.ringing);

        MeetController.open(meet: self);
        self.outgoingCall = call;

        call.initiateOutgoingCall(with: jid, completionHandler: { result in
            switch result {
            case .success(_):
                self.logger.info("initiated outgoing call of a meet \(self.jid)")
                break;
            case .failure(let error):
                self.logger.info("initiation of outgoing call of a meet \(self.jid) failed with \(error)")
                call.reset();
            }
        })
    }
    
    public func leave() {
        MeetManager.instance.unregister(meet: self);
        outgoingCall?.reset();
        incomingCall?.reset();
    }
    
    public func muted(value: Bool) {
        outgoingCall?.muted(value: value);
    }
    
    fileprivate func setIncomingCall(_ call: Call) {
        incomingCall = call;
    }
}
