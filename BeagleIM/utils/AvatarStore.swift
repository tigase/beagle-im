//
//  AvatarStore.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 06.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class AvatarStore {
    
    //open static let instance = AvatarStore();
    
    fileprivate let findAvatarHashStmt: DBStatement = try! DBConnection.main.prepareStatement("SELECT type, hash FROM avatars_cache WHERE account = :account AND jid = :jid");
    fileprivate let deleteAvatarHashStmt: DBStatement = try! DBConnection.main.prepareStatement("DELETE FROM avatars_cache WHERE jid = :jid AND account = :account AND (:type IS NULL OR type = :type)");
    fileprivate let insertAvatarHashStmt: DBStatement = try! DBConnection.main.prepareStatement("INSERT INTO avatars_cache (jid, account, hash, type) VALUES (:jid,:account,:hash,:type)");
    
    fileprivate let dispatcher = QueueDispatcher(label: "avatar_store", attributes: .concurrent);
    fileprivate let cacheDirectory: URL;
    
    init() {
        cacheDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("avatars");
        print("found cache directory:", cacheDirectory.path);
        if !FileManager.default.fileExists(atPath: cacheDirectory.path) {
            try! FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true, attributes: nil);
        }
    }
    
    func hasAvatarFor(hash: String, completionHandler: @escaping (Bool)->Void) {
        DispatchQueue.global().async {
            let result = FileManager.default.fileExists(atPath: self.cacheDirectory.appendingPathComponent(hash).path);
            completionHandler(result);
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
            return NSImage(contentsOf: self.cacheDirectory.appendingPathComponent(hash));
        }
    }
    
    func removeAvatar(for hash: String) {
        dispatcher.sync(flags: .barrier) {
            try! FileManager.default.removeItem(at: self.cacheDirectory.appendingPathComponent(hash));
        }
    }
    
    func storeAvatar(data: Data, for hash: String) {
        dispatcher.async(flags: .barrier) {
            _ = FileManager.default.createFile(atPath: self.cacheDirectory.appendingPathComponent(hash).path, contents: data, attributes: nil);
        }
    }
    
    func updateAvatarHash(for jid: BareJID, on account: BareJID, type: AvatarType, hash: String?, completionHandler: @escaping ()->Void ) {
        dispatcher.async(flags: .barrier) {
            if let oldHash = self.avatarHash(for: jid, on: account)[type] {
                guard hash == nil || (hash! != oldHash) else {
                    return;
                }
                DispatchQueue.global().async {
                    self.removeAvatar(for: oldHash)
                }
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
