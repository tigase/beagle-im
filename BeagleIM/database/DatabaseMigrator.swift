//
// DatabaseMigrator.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import Martin
import TigaseSQLite3
import TigaseLogging
import CoreLocation

public class DatabaseMigrator: DatabaseSchemaMigrator {
    
    public let expectedVersion: Int = 20;
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "DatabaseMigrator");
    
    public func upgrade(database: DatabaseWriter, newVersion version: Int) throws {
        try loadSchema(to: database, fromFile: "/db-schema-\(version).sql");
        
        if version == 11 {
            try cleanupDuplicatedEntries(database: database);
        }
        
        switch version {
        case 12:
            try database.execute("ALTER TABLE roster_items ADD COLUMN data TEXT");
            let groupMapping = try database.select("SELECT rig.item_id as item_id, rg.name as name FROM roster_items ri INNER JOIN roster_items_groups rig ON ri.id = rig.item_id INNER JOIN roster_groups rg ON rig.group_id = rg.id", cached: false).mapAll({ cursor -> (Int, String)? in
                return (cursor.int(for: "item_id")!, cursor.string(for: "name")!);
            });
            try Set(groupMapping.map { $0.0 }).forEach({ itemId in
                let groups = groupMapping.filter({ $0.0 == itemId }).map({ $0.1 });
                let annnotations: [RosterItemAnnotation] = try database.select("SELECT annotations FROM roster_items ri WHERE ri.id = :id", cached: false, params: ["id": itemId]).mapFirst({ $0.object(at: 0) }) ?? [];
                let data = DBRosterData(groups: groups, annotations: annnotations);
                try database.update("UPDATE roster_items SET data = :data WHERE id = :id", cached: false, params: ["data": data, "id": itemId]);
            })
            
            let roomsToUpdate: [(Int,RoomOptions)] = try database.select("SELECT c.id, c.name, c.nickname, c.password FROM chats c WHERE c.type = 1 AND c.nickname IS NOT NULL", cached: false).mapAll({ c -> (Int,RoomOptions)? in
                guard let id = c.int(at: 0), let nickname = c.string(at: 2) else {
                    return nil;
                }
                
                let password = c.string(at: 3);
                let name = c.string(at: 1);

                var options: RoomOptions = c.object(for: "options") ?? RoomOptions();
                if options.nickname.isEmpty {
                    let notifications = options.notifications;
                    options = RoomOptions(nickname: nickname, password: password);
                    options.notifications = notifications;
                    options.name = name;
                }
                
                return (id, options);
            })
            for (id, options) in roomsToUpdate {
                try database.update("update chats set name = null, nickname = null, password = null, options = :options where id = :id", cached: false, params: ["id": id, "options": options])
            }
        case 13:
            try database.execute("ALTER TABLE chat_history ADD COLUMN markable INTEGER NOT NULL DEFAULT 0");
            try database.executeQueries("""
ALTER TABLE chat_history_sync RENAME TO chat_history_sync_old;
CREATE TABLE IF NOT EXISTS chat_history_sync (
    id TEXT NOT NULL COLLATE NOCASE,
    account TEXT NOT NULL COLLATE NOCASE,
    component TEXT COLLATE NOCASE,
    from_timestamp INTEGER NOT NULL,
    from_id TEXT,
    to_timestamp INTEGER
);
INSERT INTO chat_history_sync (id, account, component, from_timestamp, from_id, to_timestamp)
SELECT id, account, component, from_timestamp, from_id, to_timestamp
FROM chat_history_sync_old;
DROP TABLE chat_history_sync_old;
""");
        case 14:
            let itemsToUpdate = try database.select("select id, data from chat_history where item_type = \(ItemType.message.rawValue) and data like 'geo:%,%' ", cached: false, params: [:]).mapAll({ ($0.int(for: "id"), $0.string(for: "data")) }).compactMap({ item -> Int? in
                guard let data = item.1, CLLocationCoordinate2D(geoUri: data) != nil else {
                    return nil;
                }
                return item.0;
            });
            
            for id in itemsToUpdate {
                try database.update("update chat_history set item_type = \(ItemType.location.rawValue) where id = :id", cached: false, params: ["id": id]);
            }
        case 15:
            let idsToRemove = try database.select("select c1.id from chats c1 join (select account, jid, max(timestamp) as timestamp, count(id) from chats group by account, jid having count(id) > 1) c2 on c1.account = c2.account and c1.jid = c2.jid and c1.timestamp < c2.timestamp", cached: false).mapAll({ $0.int(for: "id") });
            for id in idsToRemove {
                try database.delete("delete from chats where id = :id", cached: false, params: ["id": id]);
            }
        case 16:
            try database.executeQueries("""
CREATE INDEX chat_history_account_jid_stanza_id on chat_history (account, jid, stanza_id);
CREATE INDEX chat_history_account_jid_correction_stanza_id on chat_history (account, jid, correction_stanza_id);
""");
        case 19:
            try database.update("update chat_history set item_type = \(ItemType.retraction.rawValue) where item_type = 5");
        default:
            break;
        }
    }
    
    private func loadSchema(to database: DatabaseWriter, fromFile fileName: String) throws {
        let resourcePath = Bundle.main.resourcePath! + fileName;
        logger.debug("trying to load SQL from file \(resourcePath)");
        if let dbSchema = try? String(contentsOfFile: resourcePath, encoding: String.Encoding.utf8) {
            logger.debug("read schema: \(dbSchema)");
            try database.executeQueries(dbSchema);
            logger.debug("loaded schema from file \(fileName)");
        } else {
            logger.debug("skipped loading schema from file");
        }
    }

    // Method used to cleanup schema before version no. 12
    private func cleanupDuplicatedEntries(database: DatabaseWriter) throws {
        // removing duplicaed chats
        let duplicatedChats = try database.select("select account, jid, count(id) from chats group by account, jid", cached: false).mapAll({ cursor -> (BareJID, BareJID)? in
            guard cursor.int(at: 2)! > 1 else {
                return nil;
            }
            return (cursor.bareJid(at: 0)!, cursor.bareJid(at: 2)!);
        })
        
        for pair in duplicatedChats {
            try database.delete("delete from chats where account = :account and jid = :jid", cached: false, params: ["account": pair.0, "jid": pair.1]);
        }

        // remove omemo session without identities
        let omemoSessionsWithoutIdentity = try database.select("SELECT sess.account as account, sess.name as name, sess.device_id as deviceId FROM omemo_sessions sess WHERE NOT EXISTS (select 1 FROM omemo_identities i WHERE i.account = sess.account and i.name = sess.name and i.device_id = sess.device_id)", cached: false).mapAll({ cursor -> (BareJID, BareJID, Int32)? in
            return (cursor.bareJid(for: "account")!, cursor.bareJid(for: "name")!, cursor["deviceId"]!);
        })
        
        for triple in omemoSessionsWithoutIdentity {
            try database.delete("DELETE FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId", cached: false, params: ["account": triple.0, "name": triple.1, "deviceId": triple.2]);
        }

        // convert chat encryption from separate field to options
        let chatsToConvertEncryption = try database.select("SELECT account, jid, encryption FROM chats WHERE encryption IS NOT NULL AND options IS NULL", cached: false).mapAll({ cursor -> (BareJID, BareJID, ChatEncryption)? in
            guard let encryptionStr: String = cursor["encryption"] else {
                return nil;
            }
            guard let encryption = ChatEncryption(rawValue: encryptionStr) else {
                return nil;
            }
            return (cursor["account"]!, cursor["jid"]!, encryption);
        });
        
        for triple in chatsToConvertEncryption {
            var options = ChatOptions();
            options.encryption = triple.2;
            try database.update("UPDATE chats SET options = ?, encryption = null WHERE account = ? AND jid = ?", cached: false, params: [options, triple.0, triple.1]);
        }
    }
}
