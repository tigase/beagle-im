//
// DBRosterStore.swift
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
import TigaseSQLite3

extension Query {
    static let rosterInsertItem = Query("INSERT INTO roster_items (account, jid, name, subscription, timestamp, ask, data) VALUES (:account, :jid, :name, :subscription, :timestamp, :ask, :data)");
    static let rosterUpdateItem = Query("UPDATE roster_items SET name = :name, subscription = :subscription, timestamp = :timestamp, ask = :ask, data = :data WHERE id = :id");
    static let rosterDeleteItem = Query("DELETE FROM roster_items WHERE id = :id");
    static let rosterFindItemsForAccount = Query("SELECT id, jid, name, subscription, ask, data FROM roster_items WHERE account = :account");
}

open class DBRosterStore {
    
    static let ITEM_UPDATED = Notification.Name("rosterItemUpdated");
    static let instance: DBRosterStore = DBRosterStore.init();
    
    public let dispatcher: QueueDispatcher;
        
    public init() {
        self.dispatcher = QueueDispatcher(label: "db_roster_store");
    }
    
    func getAll(for account: BareJID) -> [DBRosterItem] {
        return dispatcher.sync {
            try! Database.main.reader({ database in
                try database.select(query: .rosterFindItemsForAccount, params: ["account": account]).mapAll(DBRosterItem.from(cursor:))
            })
        }
    }
    
    func remove(for account: BareJID, item: DBRosterItem) {
        dispatcher.sync {
            try! Database.main.writer({ database in
                try database.delete(query: .rosterDeleteItem, params: ["id": item.id]);
            })
        }
    }
    
    func removeAll(for account: BareJID) {
        dispatcher.sync {
            getAll(for: account).forEach { item in
                self.remove(for: account, item: item);
            }
        }
    }
    
    func set(for account: BareJID, item: RosterItem) -> DBRosterItem {
        return dispatcher.sync {
            let data = DBRosterData(groups: item.groups, annotations: item.annotations);
            guard let i = item as? DBRosterItem else {
                let params: [String: Any?] = ["account": account, "jid": item.jid, "name": item.name, "subscription": item.subscription.rawValue, "timestamp": Date(), "ask": item.ask, "data": data];
                
                let id = try! Database.main.writer({ database -> Int? in
                    try database.insert(query: .rosterInsertItem, params: params);
                    return database.lastInsertedRowId
                })!;
                return DBRosterItem(id: id, item: item);
            }

            let params: [String: Any?] = ["id": i.id, "name": i.name, "subscription": item.subscription.rawValue, "timestamp": Date(), "ask": item.ask, "data": data];
            try! Database.main.writer({ database in
                try database.update(query: .rosterUpdateItem, params: params);
            })
            
            return i;
        }
    }
    
    class RosterItemUpdated {
        
    }
}

struct DBRosterData: Codable, DatabaseConvertibleStringValue {
    
    let groups: [String];
    let annotations: [RosterItemAnnotation];
        
}

class DBRosterItem: RosterItem, Identifiable {
    
    static func from(cursor: Cursor) -> DBRosterItem? {
        let itemId: Int = cursor.int(for: "id")!;
        let jid: JID = cursor.jid(for: "jid")!;
        let name: String? = cursor.string(for: "name");
        let subscription = RosterItem.Subscription(rawValue: cursor.string(for: "subscription")!)!;
        let ask: Bool = cursor.bool(for: "ask");
        let data: DBRosterData = cursor.object(for: "data") ?? DBRosterData(groups: [], annotations: []);
        
        return DBRosterItem(id: itemId, jid: jid, name: name, subscription: subscription, groups: data.groups, ask: ask, annotations: data.annotations);
    }
    
    let id: Int;
    
    init(id: Int, jid: JID, name: String?, subscription: RosterItem.Subscription, groups: [String], ask: Bool, annotations: [RosterItemAnnotation]) {
        self.id = id;
        super.init(jid: jid, name: name, subscription: subscription, groups: groups, ask: ask, annotations: annotations);
    }
    
    convenience init(id: Int, item: RosterItem) {
        self.init(id: id, jid: item.jid, name: item.name, subscription: item.subscription, groups: item.groups, ask: item.ask, annotations: item.annotations);
    }
    
    override func update(name: String?, subscription: RosterItem.Subscription, groups: [String], ask: Bool, annotations: [RosterItemAnnotation]) -> RosterItem {
        return DBRosterItem(id: id, jid: jid, name: name, subscription: subscription, groups: groups, ask: ask, annotations: annotations);
    }
}
