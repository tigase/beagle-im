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
import Martin
import TigaseLogging

class MeetManager {
    
    public static let instance = MeetManager();
    
    fileprivate let queue = DispatchQueue(label: "MeetManager");
    private var meets: [Key:Meet] = [:]
    
    public func registerMeet(at jid: JID, using client: XMPPClient) -> Meet? {
        return queue.sync {
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
        _ = queue.sync {
            meets.removeValue(forKey: Key(account: meet.client.userBareJid, jid: meet.jid.bareJid));
        }
    }
    
    public func reportIncoming(call: Call) -> Bool {
        return queue.sync {
            guard let meet = meets[Key(account: call.account, jid: call.jid)] else {
                return false;
            }
            meet.setIncomingCall(call);
            Task {
                try await call.accept(offerMedia: call.media);
            }
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
    
    @Published
    fileprivate(set) var publishers: [MeetModule.Publisher] = [];
    
    private var presenceSent = false;
    private var cancellables: Set<AnyCancellable> = [];
    
    public func join() async throws {
        let call = Call(client: client, with: jid.bareJid, sid: UUID().uuidString, direction: .outgoing, media: [.audio, .video]);
        call.webrtcSid = String(UInt64.random(in: UInt64.min...UInt64.max));
        call.changeState(.ringing);

        if !PresenceStore.instance.isAvailable(for: jid.bareJid, context: client) {
            Task {
                let presence = Presence(to: jid)
                client.writer.write(stanza: presence);
                presenceSent = true;
            }
        }
        
        client.module(.meet).eventsPublisher.receive(on: MeetManager.instance.queue).filter({ $0.meetJid == self.jid.bareJid }).sink(receiveValue: { [weak self] event in
            self?.handle(event: event);
        }).store(in: &cancellables);
        
        PresenceStore.instance.bestPresenceEvents.filter({ $0.jid == self.jid.bareJid && ($0.presence == nil || $0.presence?.type == .unavailable) }).sink(receiveValue: { _ in
            call.reset();
        }).store(in: &cancellables);
        
        await MeetController.open(meet: self);
        self.outgoingCall = call;

        do {
            try await call.initiateOutgoingCall(with: jid);
            self.logger.info("initiated outgoing call of a meet \(self.jid)")
        } catch {
            self.logger.info("initiation of outgoing call of a meet \(self.jid) failed with \(error)")
            call.reset();
            self.cancellables.removeAll();
            throw error;
        }
    }
    
    public func allow(jids: [BareJID]) async throws {
        try await client.module(.meet).allow(jids: jids, in: jid);
    }
    
    public func deny(jids: [BareJID]) async throws {
        try await client.module(.meet).deny(jids: jids, in: jid);
    }
    
    public func leave() {
        cancellables.removeAll();

        MeetManager.instance.unregister(meet: self);
        outgoingCall?.reset();
        incomingCall?.reset();

        if presenceSent {
            let presence = Presence();
            presence.type = .unavailable;
            presence.to = jid;
            client.writer.write(stanza: presence);
        }
    }
    
    public func muted(value: Bool) {
        outgoingCall?.mute(value: value);
    }
    
    fileprivate func setIncomingCall(_ call: Call) {
        incomingCall = call;
        call.accept(offerMedia: []);
    }
    
    private func handle(event: MeetModule.MeetEvent) {
        switch event {
        case .publisherJoined(_, let publisher):
            publishers.append(publisher);
        case .publisherLeft(_, let publisher):
            publishers = publishers.filter({ $0.jid != publisher.jid })
        case .inivitation(_, _):
            break;
        }
    }
}
