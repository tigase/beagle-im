//
// PresenceRosterEventHandler.swift
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

class PresenceRosterEventHandler: XmppServiceEventHandler {
    
    let events: [Event] = [RosterModule.ItemUpdatedEvent.TYPE,PresenceModule.BeforePresenceSendEvent.TYPE, PresenceModule.SubscribeRequestEvent.TYPE];
    
    var status: XmppService.Status {
        return XmppService.instance.expectedStatus.value;
    }
    
    func handle(event: Event) {
        switch event {
        case let e as RosterModule.ItemUpdatedEvent:
            ContactManager.instance.update(name: e.rosterItem.name, for: .init(account: e.context.userBareJid, jid: e.rosterItem.jid.bareJid, type: .buddy))
            NotificationCenter.default.post(name: DBRosterStore.ITEM_UPDATED, object: e);
        case let e as PresenceModule.BeforePresenceSendEvent:
            e.presence.show = status.show;
            e.presence.status = status.message;
        case let e as PresenceModule.SubscribeRequestEvent:
            guard let jid = e.presence.from else {
                return;
            }
            
            InvitationManager.instance.addPresenceSubscribe(for: e.sessionObject.userBareJid!,from: jid);
            
        default:
            break;
        }
    }
    
}
