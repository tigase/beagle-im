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
import Martin
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
                    os_log(OSLogType.debug, log: .avatar, "received presence from %s with avaar hash: %{public}s", e.presence.from!.description, photoId);
                    guard let client = client else {
                        return;
                    }
                    if !AvatarManager.instance.hasAvatar(withHash: photoId) {
                        os_log(OSLogType.debug, log: .avatar, "querying %s for VCard for avaar hash: %{public}s", e.presence.from!.description, photoId);
                        let jid = e.jid;
                        Task {
                            do {
                                let vcard = try await client.module(.vcardTemp).retrieveVCard(from: e.jid);
                                vcard.photos.forEach({ photo in
                                    os_log(OSLogType.debug, log: .avatar, "got photo from %s VCard for avaar hash: %{public}s", e.presence.from!.description, photoId);
                                    self.queue.async {
                                        AvatarManager.fetchData(photo: photo, completionHandler: { result in
                                            if let data = result {
                                                _ = AvatarManager.instance.storeAvatar(data: data);
                                                AvatarManager.instance.avatarUpdated(hash: photoId, for: jid.bareJid, on: to, withNickname: jid.resource);
                                            }
                                        })
                                    }
                                })
                            } catch {
                                os_log(OSLogType.debug, log: .avatar, "got error %{public}s from %s VCard for avaar hash: %{public}s", error.localizedDescription, e.presence.from!.description, photoId);
                            }
                        }
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
