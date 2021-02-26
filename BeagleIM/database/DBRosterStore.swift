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

class AccountRoster {
    
    private var roster = [JID: RosterItem]();
    
    private let queue = DispatchQueue(label: "accountRoster", attributes: .concurrent);
    
    init(items: [RosterItem]) {
        for item in items {
            roster[item.jid] = item;
        }
    }
    
    public var items: [RosterItem] {
        return queue.sync {
            return Array(self.roster.values);
        }
    }
    
    public func item(for jid: JID) -> RosterItem? {
        return queue.sync {
            return roster[jid];
        }
    }
    
    public func update(item: RosterItem) {
        queue.async(flags: .barrier) {
            self.roster[item.jid] = item;
        }
    }
    
    public func remove(for jid: JID) {
        queue.async(flags: .barrier) {
            self.roster.removeValue(forKey: jid);
        }
    }
    
}

open class DBRosterStore: RosterStore {
    
    public typealias RosterItem = BeagleIM.RosterItem
    
    static let instance: DBRosterStore = DBRosterStore.init();
    
    public let dispatcher: QueueDispatcher;
    
    private var accountRosters = [BareJID: AccountRoster]();
  
    @Published
    public private(set) var items: Set<RosterItem> = [];
    
    public init() {
        self.dispatcher = QueueDispatcher(label: "db_roster_store");
    }
    
    public func clear(for account: BareJID) {
        dispatcher.sync {
            let items = Set(self.items(for: account));
            self.items = self.items.filter({ !items.contains($0) });
            for item in items {
                remove(for: account, jid: item.jid);
            }
        }
    }
    
    public func clear(for context: Context) {
        self.clear(for: context.userBareJid);
    }
    
    func items(for account: BareJID) -> [RosterItem] {
        return dispatcher.sync {
            return self.accountRosters[account];
        }?.items ?? [];
    }
    
    public func items(for context: Context) -> [RosterItem] {
        return items(for: context.userBareJid);
    }
    
    func item(for account: BareJID, jid: JID) -> RosterItem? {
        return dispatcher.sync {
            return self.accountRosters[account];
        }?.item(for: jid);
    }
    
    public func item(for context: Context, jid: JID) -> RosterItem? {
        return item(for: context.userBareJid, jid: jid);
    }
    
    public func updateItem(for context: Context, jid: JID, name: String?, subscription: RosterItemSubscription, groups: [String], ask: Bool, annotations: [RosterItemAnnotation]) {
        let account = context.userBareJid;
        
        let data = DBRosterData(groups: groups, annotations: annotations);
        dispatcher.sync {
            guard let item = item(for: account, jid: jid) else {
                let params: [String: Any?] = ["account": account, "jid": jid, "name": name, "subscription": subscription.rawValue, "timestamp": Date(), "ask": ask, "data": data];
                
                let id = try! Database.main.writer({ database -> Int? in
                    try database.insert(query: .rosterInsertItem, params: params);
                    return database.lastInsertedRowId
                })!;
                let item = RosterItem(id: id, context: context, jid: jid, name: name, subscription: subscription, groups: groups, ask: ask, annotations: annotations);
                self.accountRosters[account]?.update(item: item);
                self.items.insert(item);
                itemUpdated(item, context: context);
                return;
            }

            let params: [String: Any?] = ["id": item.id, "name": name, "subscription": subscription.rawValue, "timestamp": Date(), "ask": ask, "data": data];
            try! Database.main.writer({ database in
                try database.update(query: .rosterUpdateItem, params: params);
            })

            let newItem = RosterItem(id: item.id, context: context, jid: jid, name: name, subscription: subscription, groups: groups, ask: ask, annotations: annotations);
            self.accountRosters[account]?.update(item: newItem);
            var newItems = self.items;
            newItems.remove(item);
            newItems.insert(newItem);
            self.items = newItems;
            itemUpdated(newItem, context: context);
        }
    }
        
    func remove(for account: BareJID, jid: JID) {
        guard let accountRoster = dispatcher.sync(execute: {
            return self.accountRosters[account];
        }) else {
            return;
        }
        if let item = accountRoster.item(for: jid) {
            accountRoster.remove(for: jid);
            dispatcher.sync {
                try! Database.main.writer({ database in
                    try database.delete(query: .rosterDeleteItem, params: ["id": item.id]);
                })
                self.items.remove(item);
            }
        }
    }
    
    func itemUpdated(_ newItem: RosterItem, context: Context) {
        ContactManager.instance.update(name: newItem.name, for: .init(account: context.userBareJid, jid: newItem.jid.bareJid, type: .buddy))
    }
    
    public func deleteItem(for context: Context, jid: JID) {
        self.remove(for: context.userBareJid, jid: jid);
    }
    
    public func version(for context: Context) -> String? {
        return nil;
    }
    
    public func set(version: String?, for context: Context) {
        // not implemented
    }
    
    public func initialize(context: Context) {
        return dispatcher.async {
            guard self.accountRosters[context.userBareJid] == nil else {
                return;
            }
            
            let items = try! Database.main.reader({ database in
                try database.select(query: .rosterFindItemsForAccount, params: ["account": context.userBareJid]).mapAll({ RosterItem.from(cursor: $0, context: context) })
            });
            
            self.accountRosters[context.userBareJid] = AccountRoster(items: items);
            self.items = Set(self.items + items);
        }
    }
    
    public func deinitialize(context: Context) {
        dispatcher.async {
            guard let roster = self.accountRosters[context.userBareJid] else {
                return;
            }
            self.accountRosters.removeValue(forKey: context.userBareJid);
            let items = Set(roster.items);
            self.items = self.items.filter({ !items.contains($0) });
        }
    }

}

struct DBRosterData: Codable, DatabaseConvertibleStringValue {
    
    let groups: [String];
    let annotations: [RosterItemAnnotation];
        
}

public class RosterItem: TigaseSwift.RosterItemBase, Identifiable, Hashable {
    
    public static func == (lhs: RosterItem, rhs: RosterItem) -> Bool {
        return lhs.id == rhs.id;
    }
    
    static func from(cursor: Cursor, context: Context) -> RosterItem? {
        let itemId: Int = cursor.int(for: "id")!;
        let jid: JID = cursor.jid(for: "jid")!;
        let name: String? = cursor.string(for: "name");
        let subscription = RosterItemSubscription(rawValue: cursor.string(for: "subscription")!)!;
        let ask: Bool = cursor.bool(for: "ask");
        let data: DBRosterData = cursor.object(for: "data") ?? DBRosterData(groups: [], annotations: []);
        
        return RosterItem(id: itemId, context: context, jid: jid, name: name, subscription: subscription, groups: data.groups, ask: ask, annotations: data.annotations);
    }
    
    public let id: Int;
    public private(set) weak var context: Context?;
    
    public init(id: Int, context: Context, jid: JID, name: String?, subscription: RosterItemSubscription, groups: [String], ask: Bool, annotations: [RosterItemAnnotation]) {
        self.id = id;
        self.context = context;
        super.init(jid: jid, name: name, subscription: subscription, groups: groups, ask: ask, annotations: annotations);
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id);
    }
        
}
