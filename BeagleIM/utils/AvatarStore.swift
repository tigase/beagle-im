//
// AvatarStore.swift
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

class AvatarStore {
    
    //open static let instance = AvatarStore();
    
    fileprivate let findAvatarHashStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT type, hash FROM avatars_cache WHERE account = :account AND jid = :jid");
    fileprivate let deleteAvatarHashStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM avatars_cache WHERE jid = :jid AND account = :account AND (:type IS NULL OR type = :type)");
    fileprivate let insertAvatarHashStmt: DBStatement = try! DBConnection.main.prepareStatement("INSERT INTO avatars_cache (jid, account, hash, type) VALUES (:jid,:account,:hash,:type)");
    
    fileprivate let dispatcher = QueueDispatcher(label: "avatar_store", attributes: .concurrent);
    fileprivate let cacheDirectory: URL;
    
    private let cache = NSCache<NSString,NSImage>();
    
    init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("avatars");
        print("found cache directory:", cacheDirectory.path);
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil);
        }
    }
    
    func hasAvatarFor(hash: String) -> Bool {
        return dispatcher.sync {
            return FileManager.default.fileExists(atPath: self.cacheDirectory.appendingPathComponent(hash).path);
        }
    }
    
    func avatarHash(for jid: BareJID, on account: BareJID) -> [AvatarType: String] {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account, "jid": jid];
            var hashes: [AvatarType: String] = [:];
            try! findAvatarHashStmt.query(params, forEach: { cursor in
            guard let type = AvatarType(rawValue: cursor["type"]!), let hash: String = cursor["hash"] else {
                    return;
                }
                hashes[type] = hash;
            });
            return hashes;
        }
    }
    
    func avatar(for hash: String) -> NSImage? {
        return dispatcher.sync {
            if let image = cache.object(forKey: hash as NSString) {
                return image;
            }
            if let image = NSImage(contentsOf: self.cacheDirectory.appendingPathComponent(hash)) {
                cache.setObject(image, forKey: hash as NSString);
                return image;
            }
            return nil;
        }
    }
    
    func removeAvatar(for hash: String) {
        dispatcher.sync(flags: .barrier) {
            try? FileManager.default.removeItem(at: self.cacheDirectory.appendingPathComponent(hash));
            cache.removeObject(forKey: hash as NSString);
        }
    }
    
    func storeAvatar(data: Data, for hash: String) {
        dispatcher.async(flags: .barrier) {
            if !FileManager.default.createFile(atPath: self.cacheDirectory.appendingPathComponent(hash).path, contents: data, attributes: nil) {
                os_log(OSLogType.error, log: .avatar, "Could not save avatar to local cache for hash: %{public}s", hash);
            }
            if let image = NSImage(data: data) {
                self.cache.setObject(image, forKey: hash as NSString);
            }
        }
    }
    
    func updateAvatarHash(for jid: BareJID, on account: BareJID, type: AvatarType, hash: String?, completionHandler: @escaping ()->Void ) {
        dispatcher.async(flags: .barrier) {
            if let oldHash = self.avatarHash(for: jid, on: account)[type] {
                guard hash == nil || (hash! != oldHash) else {
                    return;
                }
                // removal of cached avatar was removed as it caused issues, when a few users (or members of rooms) had the same avatar
                // it is better to keep it in the cache and clean it up later at some point
//                DispatchQueue.global().async {
//                    self.removeAvatar(for: oldHash)
//                }
                let params: [String: Any?] = ["account": account, "jid": jid, "type": type.rawValue];
                _ = try! self.deleteAvatarHashStmt.update(params);
            }
            
            guard hash != nil else {
                return;
            }
            
            let params: [String: Any?] = ["account": account, "jid": jid, "type": type.rawValue, "hash": hash!];
            _ = try! self.insertAvatarHashStmt.insert(params);
            
            DispatchQueue.global(qos: .background).async {
                completionHandler();
            }
        }
    }
    
}

public enum AvatarType: String {
    case vcardTemp
    case pepUserAvatar
    
    public static let ALL: [AvatarType] = [.pepUserAvatar, .vcardTemp];
}
