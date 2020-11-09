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

class AvatarManager {

    public static let AVATAR_CHANGED = Notification.Name("avatarChanged");
    public static let AVATAR_FOR_HASH_CHANGED = Notification.Name("avatarForHashChanged");
    public static let instance = AvatarManager();

    fileprivate let store = AvatarStore();
    public var defaultAvatar: NSImage {
        return NSImage(named: NSImage.userName)!;
    }

    fileprivate var dispatcher = QueueDispatcher(label: "avatar_manager", attributes: .concurrent);
    private var cache: [BareJID: AccountAvatarHashes] = [:];

    public init() {
        NotificationCenter.default.addObserver(self, selector: #selector(vcardUpdated), name: DBVCardStore.VCARD_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: AccountManager.ACCOUNT_CHANGED, object: nil);
    }

    open func avatar(for jid: BareJID, on account: BareJID) -> NSImage? {
        return dispatcher.sync(flags: .barrier) {
            if let hash = self.avatars(on: account).avatarHash(for: jid) {
                return store.avatar(for: hash);
            }
            return nil;
        }
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
        dispatcher.async(flags: .barrier) {
            let oldHash = self.store.avatarHash(for: jid, on: account)[type];
            if oldHash == nil || oldHash! != hash {
                self.store.updateAvatarHash(for: jid, on: account, type: type, hash: hash, completionHandler: {
                    self.dispatcher.async(flags: .barrier) {
                        self.avatars(on: account).invalidateAvatarHash(for: jid);
                    }
                });
            }
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

        dispatcher.async(flags: .barrier) {
            self.cache.removeValue(forKey: account.name);
        }
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
    
    private func avatars(on account: BareJID) -> AvatarManager.AccountAvatarHashes {
        if let avatars = self.cache[account] {
            return avatars;
        }
        let avatars = AccountAvatarHashes(store: store, account: account);
        self.cache[account] = avatars;
        return avatars;
    }

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

    private class AccountAvatarHashes {

        private static let AVATAR_TYPES_ORDER: [AvatarType] = [.pepUserAvatar, .vcardTemp];
        
        private var avatarHashes: [BareJID: Optional<String>] = [:];

        private let store: AvatarStore;
        let account: BareJID;
        
        init(store: AvatarStore, account: BareJID) {
            self.store = store;
            self.account = account;
        }
        
        func avatarHash(for jid: BareJID) -> String? {
            if let hash = avatarHashes[jid] {
                return hash;
            }
            
            let hashes: [AvatarType:String] = store.avatarHash(for: jid, on: account);
        
            for type in AccountAvatarHashes.AVATAR_TYPES_ORDER {
                if let hash = hashes[type] {
                    if store.hasAvatarFor(hash: hash) {
                        avatarHashes[jid] = .some(hash);
                        return hash;
                    }
                }
            }
            avatarHashes[jid] = .none;
            return nil;
        }
        
        func invalidateAvatarHash(for jid: BareJID) {
            avatarHashes.removeValue(forKey: jid);
            NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: self, userInfo: ["account": account, "jid": jid]);
        }
        
    }
}

enum AvatarResult {
    case some(AvatarType, String)
    case none
}
