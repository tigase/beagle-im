//
// AvatarManager.swift
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
import Combine

struct AvatarWeakRef {
    weak var avatar: Avatar?;
}

public class Avatar {
    
    private let key: Key;

    public var hash: String? {
        didSet {
            if let hash = hash {
                // TODO: Could we load it using async?
                DispatchQueue.global(qos: .userInteractive).async {
                    let avatar = AvatarManager.instance.avatar(withHash: hash);
                    DispatchQueue.main.async {
                        self.avatar = avatar;
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.avatar = nil;
                }
            }
        }
    }
    
    @Published
    public var avatar: NSImage?;
    
    init(key: Key) {
        self.key = key;
    }

    deinit {
        AvatarManager.instance.releasePublisher(for: key);
    }
    
    struct Key: Hashable {
        let account: BareJID;
        let jid: BareJID;
        let mucNickname: String?;
    }

}
//
//: Publisher {
//
//    public typealias Output = NSImage?
//    public typealias Failure = Never
//
//    fileprivate let subject: CurrentValueSubject<NSImage?,Never>;
//
//    private let key: Contact.Key;
//
//    public var value: NSImage? {
//        return subject.value;
//    }
//
//    init(key: Contact.Key) {
//        self.key = key;
//        // FIXME: !! FOR MUC OCCUPANTS !!
//        self.subject = CurrentValueSubject(AvatarManager.instance.avatar(for: key.jid, on: key.account));
//    }
//
//    deinit {
//        AvatarManager.instance.releasePublisher(for: key);
//    }
//
//    public func receive<S>(subscriber: S) where S : Subscriber, Failure == S.Failure, Output == S.Input {
//        subject.receive(subscriber: Inner(avatar: self, downstream: subscriber));
//    }
//
//    private class Inner<Downstream: Subscriber>: Subscriber where Downstream.Failure == Never, Downstream.Input == NSImage? {
//
//        public typealias Input = NSImage?
//        public typealias Failure = Never;
//
//        private let avatar: Avatar;
//        private let downstream: Downstream;
//
//        init(avatar: Avatar, downstream: Downstream) {
//            self.avatar = avatar
//            self.downstream = downstream;
//        }
//
//        func receive(subscription: Subscription) {
//            downstream.receive(subscription: subscription);
//        }
//
//        func receive(_ input: NSImage?) -> Subscribers.Demand {
//            downstream.receive(input);
//        }
//
//        func receive(completion: Subscribers.Completion<Never>) {
//            downstream.receive(completion: completion);
//        }
//
//    }
//
//}

class AvatarManager {

    public static let AVATAR_CHANGED = Notification.Name("avatarChanged");
    public static let AVATAR_FOR_HASH_CHANGED = Notification.Name("avatarForHashChanged");
    public static let instance = AvatarManager();

    fileprivate let store = AvatarStore();
    public var defaultAvatar: NSImage {
        return NSImage(named: NSImage.userName)!;
    }
    public var defaultGroupchatAvatar: NSImage {
        return NSImage(named: NSImage.userGroupName)!;
    }

    // IDEA 1:
    //
    // Keep in memory all avatar hashes for all contacts
    // This way we do not need to query the database
    // With 1000 entries in 4 accounts it would give us up to 8000 hashes.
    // Each entry is 40 bytes
    // That gives us 312KB in RAM (not a lot) as iOS can have up to 1.3GB of RAM
    // Each stored entry needs to contain a contact JID, up to 2KB, so we have usage of up to 8MB of RAM

    // How about MUC? Each entry may need a corresponding entry
    // We can be in 20-100 rooms with up to 100 people, what gives us 10000 entres.
    // Each entry needs to have hash, room JID, nickname so up to 3KB, that gives us 30MB of RAM.
    //
    // In total that is up to 40MB of RAM from 1.3GB available to the app on iPhone.
    
    // IDEA 2:
    //
    // Maybe we should store avatar hashesh in the database for MUC as well? However, that would create
    // rather big penalty.
    //
    
    // IDEA 3:
    //
    // Do we need hash storage if we have publishers?
    // Maybe just the best hash and image if it was loaded?
    // Having a separate storage for images is good as it caches loaded images without the impact on the app.
    // However I wonder how ofter the app will load images as it would use cached version in avatar manager..
    
    fileprivate var dispatcher = QueueDispatcher(label: "avatar_manager", attributes: .concurrent);
    // TODO: Caching is disabled as with Avatar and Combine there may not give usa lot
//    private var cache: [BareJID: AccountAvatarHashes] = [:];

    public init() {
        NotificationCenter.default.addObserver(self, selector: #selector(vcardUpdated), name: DBVCardStore.VCARD_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: AccountManager.ACCOUNT_CHANGED, object: nil);
    }

    private var avatars: [Avatar.Key: AvatarWeakRef] = [:];
    open func avatarPublisher(for key: Avatar.Key) -> Avatar {
        return dispatcher.sync(flags: .barrier) {
            guard let avatar = avatars[key]?.avatar else {
                let avatar = Avatar(key: key);
                self.dispatcher.async {
                    avatar.hash = self.avatarHash(for: key.jid, on: key.account, withNickname: key.mucNickname);
                }
                avatars[key] = AvatarWeakRef(avatar: avatar);
                return avatar;
            }
            return avatar;
        }
    }
    
    open func existingAvatarPublisher(for key: Avatar.Key) -> Avatar? {
        return dispatcher.sync {
            return avatars[key]?.avatar;
        }
    }
    
    open func releasePublisher(for key: Avatar.Key) {
        dispatcher.async(flags: .barrier) {
            self.avatars.removeValue(forKey: key);
        }
    }
    
    private func avatarHash(for jid: BareJID, on account: BareJID, withNickname nickname: String?) -> String? {
        if let nickname = nickname {
             guard let room = DBChatStore.instance.conversation(for: account, with: jid) as? Room else {
                return nil;
            }
            return room.occupant(nickname: nickname)?.presence.vcardTempPhoto;
        } else {
            return store.avatarHash(for: jid, on: account).first?.hash;//avatars(on: account).avatarHash(for: jid);
        }
    }
    
    open func avatar(for jid: BareJID, on account: BareJID) -> NSImage? {
        guard let hash = store.avatarHash(for: jid, on: account).first?.hash else {
            return nil;
        }
        return store.avatar(for: hash);
//        return dispatcher.sync(flags: .barrier) {
//            if let hash = self.avatars(on: account).avatarHash(for: jid) {
//                return store.avatar(for: hash);
//            }
//            return nil;
//        }
    }
    
    open func hasAvatar(withHash hash: String) -> Bool {
        return store.hasAvatarFor(hash: hash);
    }
    
    open func avatar(withHash hash: String) -> NSImage? {
        return store.avatar(for: hash);
    }
    
    open func storeAvatar(data: Data) -> String {
        let hash = Digest.sha1.digest(toHex: data)!;
        self.store.storeAvatar(data: data, for: hash);
        NotificationCenter.default.post(name: AvatarManager.AVATAR_FOR_HASH_CHANGED, object: hash);
        return hash;
    }
    
    open func updateAvatar(hash: String, forType type: AvatarType, forJid jid: BareJID, on account: BareJID) {
        self.store.updateAvatarHash(for: jid, on: account, hash: .init(type: type, hash: hash), completionHandler: { result in
            switch result {
            case .notChanged:
                break;
            case .noAvatar:
                self.avatarUpdated(hash: nil, for: jid, on: account, withNickname: nil);
            case .newAvatar(let hash):
                self.avatarUpdated(hash: hash, for: jid, on: account, withNickname: nil);
            }
        })
    }
    
    public func avatarUpdated(hash: String?, for jid: BareJID, on account: BareJID, withNickname nickname: String?) {
        if let avatar = self.existingAvatarPublisher(for: .init(account: account, jid: jid, mucNickname: nickname)) {
            avatar.hash = hash;
        }
    }
    
    open func avatarHashChanged(for jid: BareJID, on account: BareJID, type: AvatarType, hash: String) {
        if hasAvatar(withHash: hash) {
            updateAvatar(hash: hash, forType: type, forJid: jid, on: account);
        } else {
            switch type {
            case .vcardTemp:
                VCardManager.instance.refreshVCard(for: jid, on: account, completionHandler: nil);
            case .pepUserAvatar:
                self.retrievePepUserAvatar(for: jid, on: account, hash: hash);
            }
        }
    }

    
    @objc func vcardUpdated(_ notification: Notification) {
        guard let vcardItem = notification.object as? DBVCardStore.VCardItem else {
            return;
        }

        DispatchQueue.global().async {
            guard let photo = vcardItem.vcard.photos.first else {
                return;
            }

            AvatarManager.fetchData(photo: photo) { data in
                guard data != nil else {
                    return;
                }

                let hash = self.storeAvatar(data: data!);
                self.updateAvatar(hash: hash, forType: .vcardTemp, forJid: vcardItem.jid, on: vcardItem.account);
            }
        }
    }

    @objc func accountChanged(_ notification: Notification) {
        guard let account = notification.object as? AccountManager.Account else {
            return;
        }

        guard AccountManager.getAccount(for: account.name) == nil else {
            return;
        }

//        dispatcher.async(flags: .barrier) {
//            self.cache.removeValue(forKey: account.name);
//        }
    }

    func retrievePepUserAvatar(for jid: BareJID, on account: BareJID, hash: String) {
        guard let pepModule: PEPUserAvatarModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PEPUserAvatarModule.ID) else {
            return;
        }

        pepModule.retrieveAvatar(from: jid, itemId: hash, completionHandler: { result in
            switch result {
            case .success((let hash, let data)):
                self.store.storeAvatar(data: data, for: hash);
                self.updateAvatar(hash: hash, forType: .pepUserAvatar, forJid: jid, on: account);
            case .failure(let error):
                print("could not retrieve avatar, got error: \(error)");
            }
        });
    }
    
//    private func avatars(on account: BareJID) -> AvatarManager.AccountAvatarHashes {
//        if let avatars = self.cache[account] {
//            return avatars;
//        }
//        let avatars = AccountAvatarHashes(store: store, account: account);
//        self.cache[account] = avatars;
//        return avatars;
//    }

    static func fetchData(photo: VCard.Photo, completionHandler: @escaping (Data?)->Void) {
        if let data = photo.binval {
            completionHandler(Data(base64Encoded: data, options: Data.Base64DecodingOptions.ignoreUnknownCharacters));
        } else if let uri = photo.uri {
            if uri.hasPrefix("data:image") && uri.contains(";base64,") {
                let idx = uri.index(uri.firstIndex(of: ",")!, offsetBy: 1);
                let data = String(uri[idx...]);
                print("got avatar:", data);
                completionHandler(Data(base64Encoded: data, options: Data.Base64DecodingOptions.ignoreUnknownCharacters));
            } else {
                let url = URL(string: uri)!;
                let task = URLSession.shared.dataTask(with: url) { (data, response, err) in
                    completionHandler(data);
                }
                task.resume();
            }
        } else {
            completionHandler(nil);
        }
    }

//    private class AccountAvatarHashes {
//
//        private static let AVATAR_TYPES_ORDER: [AvatarType] = [.pepUserAvatar, .vcardTemp];
//
//        private var avatarHashes: [BareJID: String?] = [:];
//
//        private let store: AvatarStore;
//        let account: BareJID;
//
//        init(store: AvatarStore, account: BareJID) {
//            self.store = store;
//            self.account = account;
//        }
//
//        func avatarHash(for jid: BareJID) -> String? {
//            if let hash = avatarHashes[jid] {
//                return hash;
//            }
//            let hashes: [AvatarType:String] = store.avatarHash(for: jid, on: account);
//
//            for type in AccountAvatarHashes.AVATAR_TYPES_ORDER {
//                if let hash = hashes[type] {
//                    if store.hasAvatarFor(hash: hash) {
//                        avatarHashes[jid] = .some(hash);
//                        return hash;
//                    }
//                }
//            }
//            avatarHashes[jid] = .none;
//            return nil;
//        }
//
//        func invalidateAvatarHash(for jid: BareJID) {
//            avatarHashes.removeValue(forKey: jid);
//            NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: self, userInfo: ["account": account, "jid": jid]);
//        }
//
//    }
}

enum AvatarResult {
    case some(AvatarType, String)
    case none
}
