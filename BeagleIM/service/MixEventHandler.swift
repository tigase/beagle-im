//
// MixEventHandler.swift
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
import TigaseSwift

class MixEventHandler: XmppServiceEventHandler {
    
    static let PARTICIPANTS_CHANGED = Notification.Name(rawValue: "mixParticipantsChanged");
    static let PERMISSIONS_CHANGED = Notification.Name(rawValue: "mixPermissionsChanged");
    
    static let instance = MixEventHandler();
    
    let events: [Event] = [MixModule.MessageReceivedEvent.TYPE, MixModule.ParticipantsChangedEvent.TYPE, MixModule.ChannelStateChangedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as MixModule.MessageReceivedEvent:
            // only mix message (with `mix` element) are processed here...
            guard e.message.mix != nil && e.message.from != nil, let account = e.sessionObject.userBareJid else {
                return;
            }
            
            DBChatHistoryStore.instance.append(for: e.channel as! Channel, message: e.message, source: .stream);
        case let e as MixModule.ParticipantsChangedEvent:
            NotificationCenter.default.post(name: MixEventHandler.PARTICIPANTS_CHANGED, object: e);
            for participant in e.joined {
                let jid = participant.jid ?? BareJID(localPart: participant.id + "#" + e.channel.jid.localPart!, domain: e.channel.jid.domain);
                DBVCardStore.instance.vcard(for: jid, completionHandler: { vcard in
                    guard vcard == nil else {
                        return;
                    }
                    VCardManager.instance.refreshVCard(for: jid, on: e.sessionObject.userBareJid!, completionHandler: nil);
                })
            }
        case let e as MixModule.ChannelStateChangedEvent:
            NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: e.channel);
        case let e as MixModule.ChannelPermissionsChangedEvent:
            NotificationCenter.default.post(name: MixEventHandler.PERMISSIONS_CHANGED, object: e.channel);
        default:
            break;
        }
    }

}
