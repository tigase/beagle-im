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

class BlockedEventHandler: XmppServiceEventHandler {
    
    static let instance = BlockedEventHandler();

    let events: [Event] = [BlockingCommandModule.BlockedChangedEvent.TYPE];
    
    static func isBlocked(_ jid: JID, on client: XMPPClient) -> Bool {
        guard let blockingModule: BlockingCommandModule = client.modulesManager.getModule(BlockingCommandModule.ID) else {
            return false;
        }
        return blockingModule.blockedJids?.contains(jid) ?? false;
    }
    
    static func isBlocked(_ jid: JID, on account: BareJID) -> Bool {
        guard let client = XmppService.instance.getClient(for: account) else {
            return false;
        }
        return isBlocked(jid, on: client);
    }
    
    func handle(event: Event) {
        switch event {
        case let e as BlockingCommandModule.BlockedChangedEvent:
            (e.added + e.removed).forEach { jid in
                var p = PresenceStore.instance.bestPresence(for: jid.bareJid, context: e.context);
                if p == nil {
                    p = Presence();
                    p?.type = .unavailable;
                    p?.from = jid;
                }
                let cpc = PresenceModule.ContactPresenceChanged(context: e.context, presence: p!, availabilityChanged: true);
                ContactManager.instance.update(presence: p!, for: .init(account: e.context.userBareJid, jid: jid.bareJid, type: .buddy))
                NotificationCenter.default.post(name: XmppService.CONTACT_PRESENCE_CHANGED, object: cpc);
            }
        default:
            break;
        }
    }

}
