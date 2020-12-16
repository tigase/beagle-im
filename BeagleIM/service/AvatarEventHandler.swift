//
// AvatarEventHandler.swift
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
import OSLog

class AvatarEventHandler: XmppServiceEventHandler {
    
    let events: [Event] = [PresenceModule.ContactPresenceChanged.TYPE, PEPUserAvatarModule.AvatarChangedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as PresenceModule.ContactPresenceChanged:
            NotificationCenter.default.post(name: XmppService.CONTACT_PRESENCE_CHANGED, object: e);
            guard e.presence.type != StanzaType.error, let photoId = e.presence.vcardTempPhoto, let from = e.presence.from?.bareJid, let to = e.presence.to?.bareJid else {
                return;
            }
            if e.presence.findChild(name: "x", xmlns: "http://jabber.org/protocol/muc#user") == nil {
                AvatarManager.instance.avatarHashChanged(for: from, on: to, type: .vcardTemp, hash: photoId);
            } else {
                os_log(OSLogType.debug, log: .avatar, "received presence from %s with avaar hash: %{public}s", e.presence.from!.stringValue, photoId);
                if !AvatarManager.instance.hasAvatar(withHash: photoId), let vcardTempModule: VCardTempModule = XmppService.instance.getClient(for: to)?.modulesManager.getModule(VCardTempModule.ID) {
                    os_log(OSLogType.debug, log: .avatar, "querying %s for VCard for avaar hash: %{public}s", e.presence.from!.stringValue, photoId);
                    let occupantJid = e.presence.from!;
                    vcardTempModule.retrieveVCard(from: occupantJid, completionHandler: { result in
                        switch result {
                        case .success(let vcard):
                            os_log(OSLogType.debug, log: .avatar, "got result %s with %d photos from %s VCard for avaar hash: %{public}s",
                                   String(describing: type(of: vcard).self), vcard.photos.count, e.presence.from!.stringValue, photoId);
                            vcard.photos.forEach({ photo in
                                os_log(OSLogType.debug, log: .avatar, "got photo from %s VCard for avaar hash: %{public}s", e.presence.from!.stringValue, photoId);
                                AvatarManager.fetchData(photo: photo, completionHandler: { result in
                                    if let data = result {
                                        _ = AvatarManager.instance.storeAvatar(data: data);
                                        if let nickname = occupantJid.resource {
                                            DBChatStore.instance.room(for: e.context, with: from)?.occupant(nickname: nickname)?.set(presence: e.presence);
                                        }
                                    }
                                })
                            })
                        case .failure(let error):
                            os_log(OSLogType.debug, log: .avatar, "got error %{public}s from %s VCard for avaar hash: %{public}s", error.description, e.presence.from!.stringValue, photoId);
                            break;
                        }
                    })
                }
            }
        case let e as PEPUserAvatarModule.AvatarChangedEvent:
            guard let item = e.info.first(where: { info -> Bool in
                return info.url == nil;
            }) else {
                return;
            }
            AvatarManager.instance.avatarHashChanged(for: e.jid.bareJid, on: e.sessionObject.userBareJid!, type: .pepUserAvatar, hash: item.id);
        default:
            break;
        }
    }
    
}
