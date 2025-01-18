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
    
    public actor VCardDownloadQueue {
        
        static let LIMIT = 30;
        
        struct Request: Equatable, Hashable {
            let jid: JID;
            let photoId: String;
        }
        
        struct MissingPhoto: Equatable {
            let request: Request
            let timestamp = Date()
        }
        
        class Counter {
            var requestTimes: [Date] = [];
            var waitingRequests: Set<Request> = [];
            var missingPhotos: [MissingPhoto] = [];
            func requestsLastSecond() -> Int {
                requestTimes.removeAll(where: { $0.timeIntervalSinceNow < -1 });
                return requestTimes.count;
            }
        }
        
        private var counters: [BareJID:Counter] = [:];
        
        func fetchVCard(client: XMPPClient, from: JID, forPhoto photoId: String) async throws -> VCard {
            let counter = counters[client.userBareJid] ?? Counter();
            counters[client.userBareJid] = counter;

            let request = Request(jid: from, photoId: photoId);
            counter.missingPhotos.removeAll(where: { $0.timestamp.timeIntervalSinceNow < 3600 });
            if (counter.missingPhotos.contains(where: { $0.request == request })) {
                return VCard();
            }

            let (added, _) = counter.waitingRequests.insert(request);
            guard added else {
                return VCard();
            }
            while (counter.requestsLastSecond() >= VCardDownloadQueue.LIMIT) {
                try await Task.sleep(nanoseconds: 1000000000);
            }
            counter.waitingRequests.remove(request);
            counter.requestTimes.append(Date());
            let vcard = try await client.module(.vcardTemp).retrieveVCard(from: from);
            if (vcard.photos.isEmpty) {
                counter.missingPhotos.append(.init(request: request));
            }
            return vcard;
        }
    }
    
    private let vcardFetchQueue = VCardDownloadQueue();
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.module(.presence).presencePublisher.filter({ $0.presence.type != .error }).sink(receiveValue: { [weak client] e in
            guard let client = client else {
                return;
            }
            guard let photoId = e.presence.vcardTempPhoto, let to = e.presence.to?.bareJid, let from = e.presence.from else {
                return;
            }
            let jid = e.jid;
            Task {
                if !e.presence.hasChild(name: "x", xmlns: "http://jabber.org/protocol/muc#user") {
                    AvatarManager.instance.avatarHashChanged(for: e.jid.bareJid, on: to, type: .vcardTemp, hash: photoId);
                } else {
                    os_log(OSLogType.debug, log: .avatar, "received presence from %s with avaar hash: %{public}s", e.presence.from!.description, photoId);
                    if !AvatarManager.instance.hasAvatar(withHash: photoId) {
                        os_log(OSLogType.debug, log: .avatar, "querying %s for VCard for avaar hash: %{public}s", e.presence.from!.description, photoId);
                        do {
                            let vcard = try await self.vcardFetchQueue.fetchVCard(client: client, from: e.jid, forPhoto: photoId);
                            await withTaskGroup(of: Void.self, body: { group in
                                for photo in vcard.photos {
                                    group.addTask {
                                        os_log(OSLogType.debug, log: .avatar, "got photo from %s VCard for avaar hash: %{public}s", from.description, photoId);
                                        guard let data = try? await VCardManager.fetchPhoto(photo: photo) else {
                                            return;
                                        }
                                        _ = AvatarManager.instance.storeAvatar(data: data);
                                        AvatarManager.instance.avatarUpdated(hash: photoId, for: jid.bareJid, on: to, withNickname: jid.resource);
                                    }
                                }
                                await group.waitForAll();
                            })
                        } catch {
                            os_log(OSLogType.debug, log: .avatar, "got error %{public}s from %s VCard for avaar hash: %{public}s", error.localizedDescription, e.presence.from!.description, photoId);
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
            Task {
                AvatarManager.instance.avatarHashChanged(for: e.jid.bareJid, on: account, type: .pepUserAvatar, hash: item.id);
            }
        }).store(in: &cancellables);
    }
        
}
