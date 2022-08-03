//
// PresenceStore.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import Martin
import Combine

class PresenceStore: Martin.PresenceStore {
    
    public static let instance = PresenceStore.init();
    
    struct Key: Hashable {
        let account: BareJID;
        let jid: BareJID;
    }
    
    typealias PresenceHolder = Martin.DefaultPresenceStore.PresenceHolder;
    
    private let dispatcher = QueueDispatcher(label: "presence_store_queue", attributes: DispatchQueue.Attributes.concurrent);
    
    @Published
    public private(set) var bestPresences: [Key: Presence] = [:];
    public var bestPresencesPublisher: Published<[Key: Presence]>.Publisher {
        return $bestPresences;
    }
    
    public let bestPresenceEvents = PassthroughSubject<BestPresenceEvent, Never>();

    private var presencesByBareJID: [Key: PresenceHolder] = [:];

    public init() {
        
    }
    
    public func reset(scopes: Set<ResetableScope>, for context: Context) {
        if scopes.contains(.session) {
            dispatcher.sync(flags: .barrier) {
                let keysToRemove = Set(presencesByBareJID.keys.filter({ $0.account == context.userBareJid }));
                presencesByBareJID = presencesByBareJID.filter({ !keysToRemove.contains($0.key) });
                let events = keysToRemove.map({ BestPresenceEvent(account: $0.account, jid: $0.jid, presence: nil)});
                bestPresences = bestPresences.filter({ !keysToRemove.contains($0.key) });
                for event in events {
                    bestPresenceEvents.send(event);
                }
            }
        }
    }
    
    open func isAvailable(for jid: BareJID, context: Context) -> Bool {
        return bestPresence(for: jid, context: context)?.show != nil;
    }
    
    open func presence(for jid: JID, context: Context) -> Presence? {
        return dispatcher.sync {
            return self.presencesByBareJID[.init(account: context.userBareJid, jid: jid.bareJid)]?.presence(for: jid);
        }
    }
    
    open func presences(for jid: BareJID, context: Context) -> [Presence] {
        return dispatcher.sync {
            return self.presencesByBareJID[.init(account: context.userBareJid, jid: jid)]?.presences;
        } ?? [];
    }

    public func bestPresence(for jid: BareJID, context: Context) -> Presence? {
        return bestPresences[.init(account: context.userBareJid, jid: jid)];
    }

    public func bestPresence(for jid: BareJID, on account: BareJID) -> Presence? {
        return bestPresences[.init(account: account, jid: jid)];
    }
    
    open func update(presence: Presence, for context: Context) -> Presence? {
        guard let jid = presence.from else {
            return nil;
        }
        
        let key = Key(account: context.userBareJid, jid: jid.bareJid);
        return dispatcher.sync(flags: .barrier) {
            let holder = self.holder(for: key);
            holder.update(presence: presence);
            if let best = holder.bestPresence, self.bestPresences[key] !== best {
                self.bestPresences[key] = best;
                self.bestPresenceEvents.send(.init(account: context.userBareJid, jid: jid.bareJid, presence: best));
            }
            return nil;
        }
    }
    
    open func removePresence(for jid: JID, context: Context) -> Bool {
        let key = Key(account: context.userBareJid, jid: jid.bareJid);
        return dispatcher.sync(flags: .barrier) {
            guard let holder = self.presencesByBareJID[key] else {
                return false;
            }
            holder.remove(for: jid);
            if let best = holder.bestPresence {
                self.bestPresences[key] = best;
                self.bestPresenceEvents.send(.init(account: context.userBareJid, jid: jid.bareJid, presence: best));
                return false;
            } else {
                self.presencesByBareJID.removeValue(forKey: key);
                self.bestPresences.removeValue(forKey: key);
                self.bestPresenceEvents.send(.init(account: context.userBareJid, jid: jid.bareJid, presence: nil));
                return true;
            }
        }
    }
    
    private func holder(for key: Key) -> PresenceHolder {
        guard let holder = self.presencesByBareJID[key] else {
            let holder = PresenceHolder();
            self.presencesByBareJID[key] = holder;
            return holder;
        }
        return holder;
    }

    
}
