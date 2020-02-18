//
// DatabaseSchemaManager.swift
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

import Foundation
import TigaseSwift

public class DBSchemaManager {
    
    static let CURRENT_VERSION = 8;
    
    fileprivate let dbConnection: DBConnection;
    
    init(dbConnection: DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    open func upgradeSchema() throws {
        var version = try! getSchemaVersion();
        while (version < DBSchemaManager.CURRENT_VERSION) {
            try loadSchemaFile(fileName: "/db-schema-\(version + 1).sql");
            version = try! getSchemaVersion();
        }
        
        let duplicatedStmt = try! dbConnection.prepareStatement("select account, jid, count(id) from chats group by account, jid");
        let to_remove: [[String: BareJID]] = try! duplicatedStmt.query { (cursor) -> [String: BareJID]? in
            let account: BareJID = cursor[0]!;
            let jid: BareJID = cursor[1]!;
            let count: Int = cursor[2];
            print("found account =", account, ", jid =", jid, ", count =", count);
            guard count > 1 else {
                return nil;
            }
            print("found account =", account, ", jid =", jid, "to remove!");
            return ["account": account, "jid": jid];
        }
        to_remove.forEach({ params in
            try! dbConnection.execute("delete from chats where account = '\(params["account"]!.stringValue)' and jid = '\(params["jid"]!.stringValue)'");
        })
        
        let toRemove: [(String,String,Int32)] = try dbConnection.prepareStatement("SELECT sess.account as account, sess.name as name, sess.device_id as deviceId FROM omemo_sessions sess WHERE NOT EXISTS (select 1 FROM omemo_identities i WHERE i.account = sess.account and i.name = sess.name and i.device_id = sess.device_id)").query([:] as [String: Any?], map: { (cursor:DBCursor) -> (String, String, Int32)? in
            return (cursor["account"]!, cursor["name"]!, cursor["deviceId"]!);
        });
        
        try toRemove.forEach { tuple in
            let (account, name, device) = tuple;
            _ = try dbConnection.prepareStatement("DELETE FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId").update(["account": account, "name": name, "deviceId": device] as [String: Any?]);
        }

        let queryStmt = try dbConnection.prepareStatement("SELECT account, jid, encryption FROM chats WHERE encryption IS NOT NULL AND options IS NULL");
        let toConvert = try queryStmt.query { (cursor) -> (BareJID, BareJID, ChatEncryption)? in
            let account: BareJID = cursor["account"]!;
            let jid: BareJID = cursor["jid"]!;
            guard let encryptionStr: String = cursor["encryption"] else {
                return nil;
            }
            guard let encryption = ChatEncryption(rawValue: encryptionStr) else {
                return nil;
            }
            
            return (account, jid, encryption);
        }
        if !toConvert.isEmpty {
            let updateStmt = try dbConnection.prepareStatement("UPDATE chats SET options = ?, encryption = null WHERE account = ? AND jid = ?");
            try toConvert.forEach { (arg0) in
                let (account, jid, encryption) = arg0
                var options = ChatOptions();
                options.encryption = encryption;
                let data = try? JSONEncoder().encode(options);
                let dataStr = data != nil ? String(data: data!, encoding: .utf8)! : nil;
                _ = try updateStmt.update(dataStr, account, jid);
            }
        }
    }
    
    open func getSchemaVersion() throws -> Int {
        return try self.dbConnection.prepareStatement("PRAGMA user_version").scalar() ?? 0;
    }
    
    fileprivate func loadSchemaFile(fileName: String) throws {
        let resourcePath = Bundle.main.resourcePath! + fileName;
        print("loading SQL from file", resourcePath);
        let dbSchema = try String(contentsOfFile: resourcePath, encoding: String.Encoding.utf8);
        print("read schema:", dbSchema);
        try dbConnection.execute(dbSchema);
        print("loaded schema from file", fileName);
    }
    
}
