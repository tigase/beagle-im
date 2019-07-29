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
    public static let instance = AvatarManager();
    
    public let store = AvatarStore();
    public var defaultAvatar: NSImage {
        return NSImage(named: NSImage.userName)!;
    }

    fileprivate var dispatcher = QueueDispatcher(label: "avatar_manager", attributes: .concurrent);
    fileprivate var cache: [BareJID: AccountAvatars] = [:];
    
    public init() {
        NotificationCenter.default.addObserver(self, selector: #selector(vcardUpdated), name: DBVCardStore.VCARD_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: AccountManager.ACCOUNT_CHANGED, object: nil);
    }
    
    open func avatar(for jid: BareJID, on account: BareJID) -> NSImage? {
        return dispatcher.sync(flags: .barrier) {
            return self.avatars(on: account).avatar(for: jid, on: account);
        }
    }
    
    open func avatarHashChanged(for jid: BareJID, on account: BareJID, type: AvatarType, hash: String) {
        let oldHash = self.store.avatarHash(for: jid, on: account)[type];
        guard oldHash == nil || oldHash! != hash else {
            self.store.hasAvatarFor(hash: hash, completionHandler: { (result) in
                guard !result else {
                    return;
                }
                switch type {
                case .vcardTemp:
                    VCardManager.instance.refreshVCard(for: jid, on: account, completionHandler: nil);
                case .pepUserAvatar:
                    self.retrievePepUserAvatar(for: jid, on: account, hash: hash);
                }
            });
            return;
        }
        self.store.hasAvatarFor(hash: hash, completionHandler: { (result) in
            if result {
                self.store.updateAvatarHash(for: jid, on: account, type: type, hash: hash) {
                    self.dispatcher.async(flags: .barrier) {
                        let avatars = self.avatars(on: account);
                        avatars.invalidateAvatar(for: jid, on: account);
                    }
                    DispatchQueue.global().async {
                        NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: self, userInfo: ["account": account, "jid": jid]);
                    }
                }
            } else {
                switch type {
                case .vcardTemp:
                    VCardManager.instance.refreshVCard(for: jid, on: account, completionHandler: nil);
                case .pepUserAvatar:
                    self.retrievePepUserAvatar(for: jid, on: account, hash: hash);
                }
            }
        });
    }
    
    @objc func vcardUpdated(_ notification: Notification) {
        guard let vcardItem = notification.object as? DBVCardStore.VCardItem else {
            return;
        }
        
        DispatchQueue.global().async {
            guard let photo = vcardItem.vcard.photos.first else {
                return;
            }
            
            self.fetchData(photo: photo) { data in
                guard data != nil else {
                    return;
                }
                
                let hash = Digest.sha1.digest(toHex: data)!;

                self.store.storeAvatar(data: data!, for: hash);
                self.store.updateAvatarHash(for: vcardItem.jid, on: vcardItem.account, type: .vcardTemp, hash: hash, completionHandler: {
                    self.dispatcher.async(flags: .barrier) {
                        let avatars = self.avatars(on: vcardItem.account);
                        avatars.invalidateAvatar(for: vcardItem.jid, on: vcardItem.account);
                    }
                })
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
        
        pepModule.retrieveAvatar(from: jid, itemId: hash, onSuccess: { (jid, hash, photoData) in
            guard let data = photoData else {
                return;
            }
            self.store.storeAvatar(data: data, for: hash);
            self.store.updateAvatarHash(for: jid, on: account, type: .pepUserAvatar, hash: hash, completionHandler: {
                self.dispatcher.async(flags: .barrier) {
                    let avatars = self.avatars(on: account);
                    avatars.invalidateAvatar(for: jid, on: account);
                }
            })
        }, onError: nil);
    }
    
    fileprivate func avatars(on account: BareJID) -> AvatarManager.AccountAvatars {
        if let avatars = self.cache[account] {
            return avatars;
        }
        let avatars = AccountAvatars();
        self.cache[account] = avatars;
        return avatars;
    }
    
    fileprivate func fetchData(photo: VCard.Photo, completionHandler: @escaping (Data?)->Void) {
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
    
    fileprivate func loadAvatar(for jid: BareJID, on account: BareJID) -> NSImage? {
        let hashes = store.avatarHash(for: jid, on: account);
        if let hash = hashes[.pepUserAvatar] {
            if let image = store.avatar(for: hash) {
                return image;
            }
            retrievePepUserAvatar(for: jid, on: account, hash: hash);
        }
        if let hash = hashes[.vcardTemp] {
            if let image = store.avatar(for: hash) {
                return image;
            }
            VCardManager.instance.refreshVCard(for: jid, on: account, completionHandler: nil);
        }
        return nil
    }
    
    class AccountAvatars {
        
        fileprivate var avatars: [BareJID: NSImage] = [:];
        
        func avatar(for jid: BareJID, on account: BareJID) -> NSImage? {
            if let image = AvatarManager.instance.dispatcher.sync(execute: { self.avatars[jid] }) {
                return image === AvatarManager.instance.defaultAvatar ? nil : image;
            }
            
            let image = AvatarManager.instance.loadAvatar(for: jid, on: account) ?? AvatarManager.instance.defaultAvatar;
            AvatarManager.instance.dispatcher.sync(flags: .barrier) {
                self.avatars[jid] = image;
            }
            
            return image === AvatarManager.instance.defaultAvatar ? nil : image;
        }
        
        fileprivate func invalidateAvatar(for jid: BareJID, on account: BareJID) {
            AvatarManager.instance.dispatcher.async(flags: .barrier) {
                self.avatars.removeValue(forKey: jid);
                DispatchQueue.global().async {
                    NotificationCenter.default.post(name: AvatarManager.AVATAR_CHANGED, object: self, userInfo: ["account": account, "jid": jid]);
                }
            }
        }
        
    }
}

