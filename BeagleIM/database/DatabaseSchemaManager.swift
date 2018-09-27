//
//  DatabaseSchemaManager.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 14.04.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

public class DBSchemaManager {
    
    static let CURRENT_VERSION = 1;
    
    fileprivate let dbConnection: DBConnection;
    
    init(dbConnection: DBConnection) {
        self.dbConnection = dbConnection;
    }
    
    open func upgradeSchema() throws {
        var version = 0;//try! getSchemaVersion();
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
