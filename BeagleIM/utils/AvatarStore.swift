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
import Martin
import TigaseSQLite3
import OSLog

extension Query {
    static let avatarFindHash = Query("SELECT type, hash FROM avatars_cache WHERE account = :account AND jid = :jid");
    static let avatarDeleteHash = Query("DELETE FROM avatars_cache WHERE jid = :jid AND account = :account AND (:type IS NULL OR type = :type)");
    static let avatarInsertHash = Query("INSERT INTO avatars_cache (jid, account, hash, type) VALUES (:jid,:account,:hash,:type)");
}

class AvatarStore {
    
    fileprivate let dispatcher = QueueDispatcher(label: "avatar_store", attributes: .concurrent);
    fileprivate let cacheDirectory: URL;
    
    private let cache = NSCache<NSString,NSImage>();
    
    init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("avatars");
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil);
        }
    }
    
    func hasAvatarFor(hash: String) -> Bool {
        return dispatcher.sync {
            return FileManager.default.fileExists(atPath: self.cacheDirectory.appendingPathComponent(hash).path);
        }
    }
    
    func avatarHash(for jid: BareJID, on account: BareJID) -> [AvatarHash] {
        return dispatcher.sync {
            return try! Database.main.reader({ database in
                try database.select(query: .avatarFindHash, params: ["account": account, "jid": jid]).mapAll({ cursor -> AvatarHash? in
                    guard let type = AvatarType(rawValue: cursor["type"]!), let hash: String = cursor["hash"] else {
                        return nil;
                    }
                    return AvatarHash(type: type, hash: hash);
                });
            });
        }
    }
    
    func avatar(for hash: String) -> NSImage? {
        return dispatcher.sync {
            if let image = cache.object(forKey: hash as NSString) {
                return image;
            }
            if let data = try? Data(contentsOf: self.cacheDirectory.appendingPathComponent(hash)), let image = NSImage(data: data) {
                if let rep = image.bestRepresentation(for: .zero, context: nil, hints: nil) {
                    let tmpImage = NSImage(size: image.size);
                    tmpImage.addRepresentation(rep)
                    cache.setObject(tmpImage, forKey: hash as NSString);
                    return tmpImage;
                }
//                var rect = CGRect(origin: .zero, size: image.size);
//                if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
//                    let tmpImage = NSImage(cgImage: cgImage, size: image.size);
//                    cache.setObject(tmpImage, forKey: hash as NSString);
//                    return tmpImage;
//                }
//                cache.setObject(image, forKey: hash as NSString);
//                return image;
            }
            return nil;
        }
    }
    
    func avatar(for hash: String, completionHandler: @escaping (Result<NSImage,ErrorCondition>)->Void) {
        dispatcher.async {
            if let image = self.cache.object(forKey: hash as NSString) {
                completionHandler(.success(image));
                return;
            }
            if let data = try? Data(contentsOf: self.cacheDirectory.appendingPathComponent(hash)), let image = NSImage(data: data)? .scaled(maxWidthOrHeight: 48) {//.decoded() {
                self.cache.setObject(image, forKey: hash as NSString);
                completionHandler(.success(image));
                return;
            }
            completionHandler(.failure(.conflict))
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
    
    enum AvatarUpdateResult {
        case newAvatar(String)
        case notChanged
        case noAvatar
    }
    
    func removeAvatarHash(for jid: BareJID, on account: BareJID, type: AvatarType, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.delete(query: .avatarDeleteHash, params: ["account": account, "jid": jid, "type": type.rawValue]);
            });
            completionHandler();
        }
    }
    
    func updateAvatarHash(for jid: BareJID, on account: BareJID, hash: AvatarHash, completionHandler: @escaping (AvatarUpdateResult)->Void ) {
        dispatcher.async(flags: .barrier) {
            let oldHashes = self.avatarHash(for: jid, on: account);
            guard !oldHashes.contains(hash) else {
                completionHandler(.notChanged);
                return;
            }
            
            try! Database.main.writer({ database in
                try database.delete(query: .avatarDeleteHash, params: ["account": account, "jid": jid, "type": hash.type.rawValue]);
                try database.insert(query: .avatarInsertHash, params: ["account": account, "jid": jid, "type": hash.type.rawValue, "hash": hash.hash]);
            })

            if oldHashes.isEmpty {
                completionHandler(.newAvatar(hash.hash));
            } else if let first = oldHashes.first, first >= hash {
                completionHandler(.newAvatar(hash.hash));
            } else {
                completionHandler(.notChanged);
            }
        }
    }
 
    public class AvatarData {
        @Published
        var image: NSImage?;
    }
}

public struct AvatarHash: Comparable, Equatable {
    
    public static func < (lhs: AvatarHash, rhs: AvatarHash) -> Bool {
        return lhs.type < rhs.type;
    }
    
    
    let type: AvatarType;
    let hash: String;
    
}

public enum AvatarType: String, Comparable {
    public static func < (lhs: AvatarType, rhs: AvatarType) -> Bool {
        return lhs.value < rhs.value;
    }
    
    case vcardTemp
    case pepUserAvatar
    
    private var value: Int {
        switch self {
        case .vcardTemp:
            return 2;
        case .pepUserAvatar:
            return 1;
        }
    }
    
    public static let ALL: [AvatarType] = [.pepUserAvatar, .vcardTemp];
}
