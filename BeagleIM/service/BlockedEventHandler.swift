//
// BlockedEventHandler.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift
import Combine

class BlockedEventHandler: XmppServiceExtension {
    
    static let instance = BlockedEventHandler();

    static func isBlocked(_ jid: JID, on client: Context) -> Bool {
        return client.module(.blockingCommand).blockedJids?.contains(jid) ?? false;
    }
    
    static func isBlocked(_ jid: JID, on account: BareJID) -> Bool {
        guard let client = XmppService.instance.getClient(for: account) else {
            return false;
        }
        return isBlocked(jid, on: client);
    }
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        var prev: [JID] = [];
        client.module(.blockingCommand).$blockedJids.map({ $0 ?? []}).sink(receiveValue: { [weak client] blockedJids in
            guard let client = client else {
                return;
            }

            let prevSet = Set(prev);
            let blockedSet = Set(blockedJids);
            
            let changes = blockedJids.filter({ !prevSet.contains($0) }) + prev.filter({ !blockedSet.contains($0) });
            
            prev = blockedJids;
            
            for jid in changes {
                var p = PresenceStore.instance.bestPresence(for: jid.bareJid, context: client);
                if p == nil {
                    p = Presence();
                    p?.type = .unavailable;
                    p?.from = jid;
                }
                ContactManager.instance.update(presence: p!, for: .init(account: client.userBareJid, jid: jid.bareJid, type: .buddy))
            }
        }).store(in: &cancellables);
    }
    
}
