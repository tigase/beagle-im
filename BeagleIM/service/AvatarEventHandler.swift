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
import Combine

class AvatarEventHandler: XmppServiceExtension {

    static let instance = AvatarEventHandler();
    
    private let queue = DispatchQueue(label: "AvatarEventHandler");

    private init() {
    }
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.module(.presence).presencePublisher.filter({ $0.presence.type != .error }).sink(receiveValue: { [weak client] e in
            guard let photoId = e.presence.vcardTempPhoto, let to = e.presence.to?.bareJid else {
                return;
            }
            self.queue.async {
                if e.presence.findChild(name: "x", xmlns: "http://jabber.org/protocol/muc#user") == nil {
                    AvatarManager.instance.avatarHashChanged(for: e.jid.bareJid, on: to, type: .vcardTemp, hash: photoId);
                } else {
                    os_log(OSLogType.debug, log: .avatar, "received presence from %s with avaar hash: %{public}s", e.presence.from!.stringValue, photoId);
                    guard let client = client else {
                        return;
                    }
                    if !AvatarManager.instance.hasAvatar(withHash: photoId) {
                        os_log(OSLogType.debug, log: .avatar, "querying %s for VCard for avaar hash: %{public}s", e.presence.from!.stringValue, photoId);
                        client.module(.vcardTemp).retrieveVCard(from: e.jid, completionHandler: { result in
                            switch result {
                            case .success(let vcard):
                                os_log(OSLogType.debug, log: .avatar, "got result %s with %d photos from %s VCard for avaar hash: %{public}s",
                                       String(describing: type(of: vcard).self), vcard.photos.count, e.presence.from!.stringValue, photoId);
                                vcard.photos.forEach({ photo in
                                    os_log(OSLogType.debug, log: .avatar, "got photo from %s VCard for avaar hash: %{public}s", e.presence.from!.stringValue, photoId);
                                    self.queue.async {
                                        AvatarManager.fetchData(photo: photo, completionHandler: { result in
                                            if let data = result {
                                                _ = AvatarManager.instance.storeAvatar(data: data);
                                                AvatarManager.instance.avatarUpdated(hash: photoId, for: e.jid.bareJid, on: to, withNickname: e.jid.resource);
                                            }
                                        })
                                    }
                                })
                            case .failure(let error):
                                os_log(OSLogType.debug, log: .avatar, "got error %{public}s from %s VCard for avaar hash: %{public}s", error.description, e.presence.from!.stringValue, photoId);
                                break;
                            }
                        })
                    } else {
                        AvatarManager.instance.avatarUpdated(hash: photoId, for: e.jid.bareJid, on: to, withNickname: e.jid.resource);
                    }
                }
            }
        }).store(in: &cancellables);
        client.module(.pepUserAvatar).avatarChangePublisher.sink(receiveValue: { [weak client] e in
            guard let account = client?.userBareJid else {
                return;
            }
            guard let item = e.info.first(where: { info -> Bool in
                return info.url == nil;
            }) else {
                return;
            }
            self.queue.async {
                AvatarManager.instance.avatarHashChanged(for: e.jid.bareJid, on: account, type: .pepUserAvatar, hash: item.id);
            }
        }).store(in: &cancellables);
    }
        
}
