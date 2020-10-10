//
// DBRosterStoreWrapper.swift
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
    
    open override func getJids() -> [JID] {
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
