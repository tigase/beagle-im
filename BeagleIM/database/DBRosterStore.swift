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

class DBRosterStoreWrapper: RosterStore {
    
    fileprivate var roster = [JID: DBRosterItem]();
    
    fileprivate var queue = DispatchQueue(label: "db_roster_store_wrapper", attributes: DispatchQueue.Attributes.concurrent);
    
    fileprivate let sessionObject: SessionObject;
    fileprivate let store = DBRosterStore.instance;
    
    open override var count:Int {
        get {
            return queue.sync {
                return self.roster.count;
            }
        }
    }
    
    public init(sessionObject: SessionObject) {
        self.sessionObject = sessionObject;
    }
    
    open func initialize() {
        queue.sync(flags: .barrier) {
            self.store.getAll(for: sessionObject.userBareJid!).forEach { item in
                roster[item.jid] = item;
            }
        }
    }
    
    open override func addItem(_ item:RosterItem) {
        queue.async(flags: .barrier, execute: {
            let dbItem = self.store.set(for: self.sessionObject.userBareJid!, item: item);
            self.roster[item.jid] = dbItem;
        })
    }
    
    open func getJids() -> [JID] {
        var result = [JID]();
        queue.sync {
            self.roster.keys.forEach({ (jid) in
                result.append(jid);
            });
        }
        return result;
    }
    
    open func getAll() -> [RosterItem] {
        return queue.sync {
            return self.roster.values.map({ (item) -> RosterItem in
                return item;
            })
        }
    }
    
    open override func get(for jid:JID) -> RosterItem? {
        return queue.sync {
            return self.roster[jid];
        }
    }
    
    open override func removeItem(for jid:JID) {
        queue.async(flags: .barrier, execute: {
            guard let item = self.roster.removeValue(forKey: jid) else {
                return;
            }
            self.store.remove(for: self.sessionObject.userBareJid!, item: item)
        })
    }
    
    open override func removeAll() {
        queue.async(flags: .barrier) {
            self.store.removeAll(for: self.sessionObject.userBareJid!);
            self.roster.removeAll();
        }
    }
    
}

open class DBRosterStore {
    
    static let ITEM_UPDATED = Notification.Name("rosterItemUpdated");
    static let instance: DBRosterStore = DBRosterStore.init();
    
    public let dispatcher: QueueDispatcher;
    
    fileprivate let insertItemStmt: DBStatement;
    fileprivate let updateItemStmt: DBStatement;
    fileprivate let deleteItemStmt: DBStatement;
    
    fileprivate let getAllItemsGroupsStmt: DBStatement;
    fileprivate let getAllItemsStmt: DBStatement;
    
    fileprivate let insertGroupStmt: DBStatement;
    fileprivate let getGroupIdStmt: DBStatement;
    fileprivate let insertItemGroupStmt: DBStatement;
    fileprivate let deleteItemGroupsStmt: DBStatement;
    
    public init() {
        self.dispatcher = QueueDispatcher(label: "db_roster_store");
        
        insertItemStmt = try! DBConnection.main.prepareStatement("INSERT INTO roster_items (account, jid, name, subscription, timestamp, ask, annotations) VALUES (:account, :jid, :name, :subscription, :timestamp, :ask, :annotations)");
        updateItemStmt = try! DBConnection.main.prepareStatement("UPDATE roster_items SET name = :name, subscription = :subscription, timestamp = :timestamp, ask = :ask, annotations = :annotations WHERE id = :id");
        deleteItemStmt = try! DBConnection.main.prepareStatement("DELETE FROM roster_items WHERE id = :id");
        
        getAllItemsGroupsStmt = try! DBConnection.main.prepareStatement("SELECT rig.item_id as item_id, rg.name as name FROM roster_items ri INNER JOIN roster_items_groups rig ON ri.id = rig.item_id INNER JOIN roster_groups rg ON rig.group_id = rg.id WHERE ri.account = :account");
        getAllItemsStmt = try! DBConnection.main.prepareStatement("SELECT id, jid, name, subscription, ask, annotations FROM roster_items WHERE account = :account");
        
        getGroupIdStmt = try! DBConnection.main.prepareStatement("SELECT id from roster_groups WHERE name = :name");
        insertGroupStmt = try! DBConnection.main.prepareStatement("INSERT INTO roster_groups (name) VALUES (:name)");
        insertItemGroupStmt = try! DBConnection.main.prepareStatement("INSERT INTO roster_items_groups (item_id, group_id) VALUES (:item_id, :group_id)");
        deleteItemGroupsStmt = try! DBConnection.main.prepareStatement("DELETE FROM roster_items_groups WHERE item_id = :item_id");
    }
    
    func getAll(for account: BareJID) -> [DBRosterItem] {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account];
            var groups: [Int: [String]] = [:];
            try! self.getAllItemsGroupsStmt.query(params) { cursor in
                let itemId: Int = cursor["item_id"]!;
                let group: String = cursor["name"]!;
                
                var tmp = groups[itemId] ?? [];
                tmp.append(group);
                groups[itemId] = tmp;
            }
            
            return try! self.getAllItemsStmt.query(params, map: { (cursor) -> DBRosterItem? in
                let itemId: Int = cursor["id"]!;
                let jid: JID = cursor["jid"]!;
                let name: String? = cursor["name"];
                let subscription = RosterItem.Subscription(rawValue: cursor["subscription"]!)!;
                let ask: Bool = cursor["ask"]!;
                var annotations: [RosterItemAnnotation] = [];
                if let annotationsStr: String = cursor["annotations"], let annotationsData = annotationsStr.data(using: .utf8) {
                    if let val = try? JSONDecoder().decode([RosterItemAnnotation].self, from: annotationsData) {
                        annotations = val;
                    }
                }
                
                let itemGroups = groups[itemId] ?? [];
                
                return DBRosterItem(id: itemId, jid: jid, name: name, subscription: subscription, groups: itemGroups, ask: ask, annotations: annotations);
            });
        }
    }
    
    func remove(for account: BareJID, item: DBRosterItem) {
        dispatcher.sync {
            deleteItemGroups(item: item);
            let params: [String: Any?] = ["id": item.id];
            _ = try! self.deleteItemStmt.update(params);
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
            guard let i = item as? DBRosterItem else {
                let annotations = String(data: (try? JSONEncoder().encode(item.annotations)) ?? Data(), encoding: .utf8);
                let params: [String: Any?] = ["account": account, "jid": item.jid, "name": item.name, "subscription": item.subscription.rawValue, "timestamp": Date(), "ask": item.ask, "annotations": annotations];
                
                let id = try! self.insertItemStmt.insert(params)!;
                let dbItem = DBRosterItem(id: id, item: item);
                self.insertItemGroups(item: dbItem);
                return dbItem;
            }

            let annotations = String(data: (try? JSONEncoder().encode(item.annotations)) ?? Data(), encoding: .utf8);
            let params: [String: Any?] = ["id": i.id, "name": i.name, "subscription": item.subscription.rawValue, "timestamp": Date(), "ask": item.ask, "annotations": annotations];
            
            _ = try! self.updateItemStmt.update(params);
            
            deleteItemGroups(item: i);
            insertItemGroups(item: i);
            
            return i;
        }
    }
    
    fileprivate func insertItemGroups(item: DBRosterItem) {
        item.groups.forEach({ group in
            let groupId = ensure(group: group);
            let params: [String: Any?] = ["item_id": item.id, "group_id": groupId];
            _ = try! self.insertItemGroupStmt.insert(params);
        })
    }
    
    fileprivate func deleteItemGroups(item: DBRosterItem) {
        let params: [String: Any?] = ["item_id": item.id];
        _ = try! deleteItemGroupsStmt.update(params);
    }
    
    fileprivate func ensure(group: String) -> Int {
        let params: [String: Any?] = ["name": group];
        guard let groupId = try! getGroupIdStmt.scalar(params) else {
            return try! insertGroupStmt.insert(params)!;
        }
        return groupId;
    }
    
    class RosterItemUpdated {
        
    }
}

class DBRosterItem: RosterItem {
    
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
