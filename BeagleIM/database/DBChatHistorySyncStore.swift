//
// DBChatHistorySyncStore.swift
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
import TigaseSwift
import os

class DBChatHistorySyncStore {
    
    static let instance = DBChatHistorySyncStore()
    
    private let addSyncPeriod: DBStatement;
    private let loadSyncPeriods: DBStatement;
    private let loadSyncPeriodsWith: DBStatement;
    private let removeSyncPeriod: DBStatement;
    private let updateSyncPeriodAfter: DBStatement;
    private let updateSyncPeriodTo: DBStatement;
    
    init() {
        addSyncPeriod = try! DBConnection.main.prepareStatement("INSERT INTO chat_history_sync (id, account, component, from_timestamp, from_id, to_timestamp) VALUES (:id, :account, :component, :from_timestamp, :from_id, :to_timestamp)");
        loadSyncPeriods = try! DBConnection.main.prepareStatement("SELECT id, account, from_timestamp, from_id, to_timestamp FROM chat_history_sync WHERE account = :account AND component IS NULL ORDER BY from_timestamp ASC");
        loadSyncPeriodsWith = try! DBConnection.main.prepareStatement("SELECT id, account, component, from_timestamp, from_id, to_timestamp FROM chat_history_sync WHERE account = :account AND component = :component ORDER BY from_timestamp ASC");
        removeSyncPeriod = try! DBConnection.main.prepareStatement("DELETE FROM chat_history_sync WHERE id = :id");
        updateSyncPeriodAfter = try! DBConnection.main.prepareStatement("UPDATE chat_history_sync SET from_id = :after WHERE id = :id");
        updateSyncPeriodTo = try! DBConnection.main.prepareStatement("UPDATE chat_history_sync SET to_timestamp = :to_timestamp WHERE id = :id");
        
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged(_:)), name: AccountManager.ACCOUNT_CHANGED, object: nil);
    }
    
    @objc func accountChanged(_ notification: Notification) {
        guard let acc = notification.object as? AccountManager.Account, AccountManager.getAccount(for: acc.name) == nil else {
            return;
        }
        
        removeSyncPeriods(forAccount: acc.name);
    }

    func addSyncPeriod(_ period: Period) {
        if let last = loadSyncPeriods(forAccount: period.account, component: period.component).last, last.from <= period.from && last.to >= period.from {
            // we only need to update `to` value
            os_log("updating sync period to for account %s and component %s", log: .chatHistorySync, type: .debug, period.account.stringValue, period.component?.stringValue ?? "nil");
            _ = try! updateSyncPeriodTo.update(["id": last.id.uuidString, "to_timestamp": max(last.to, period.to)] as [String: Any?]);
            return;
        }
        os_log("adding sync period %s for account %s and component %s from %{time_t}d to %{time_t}d", log: .chatHistorySync, type: .debug, period.id.uuidString, period.account.stringValue, period.component?.stringValue ?? "nil", time_t(period.from.timeIntervalSince1970), time_t(period.to.timeIntervalSince1970));
        _ = try! addSyncPeriod.insert(["id": period.id.uuidString, "account": period.account, "component": period.component, "from_timestamp": period.from, "to_timestamp": period.to] as [String: Any?]);
    }
    
    func loadSyncPeriods(forAccount account: BareJID, component: BareJID?) -> [Period] {
        // how about periods with less than a few minutes/seconds apart? should we merge them?
        if let component = component {
            let periods = try! loadSyncPeriodsWith.query(["account": account, "component": component] as [String: Any?], map: {
                return Period(id: UUID(uuidString: $0["id"]!)!, account: $0["account"]!, component: $0["component"], from: $0["from_timestamp"]!, after: $0["from_id"], to: $0["to_timestamp"]!);
            });
            os_log("loaded %d sync periods for account %s and component %s", log: .chatHistorySync, type: .debug, periods.count, account.stringValue, component.stringValue);
            return periods;
        }
        else {
            let periods = try! loadSyncPeriods.query(["account": account] as [String: Any?], map: {
                return Period(id: UUID(uuidString: $0["id"]!)!, account: $0["account"]!, from: $0["from_timestamp"]!, after: $0["from_id"], to: $0["to_timestamp"]!);
            });
            os_log("loaded %d sync periods for account %s", log: .chatHistorySync, type: .debug, periods.count, account.stringValue);
            return periods;
        }
    }
    
    func removeSyncPerod(_ period: Period) {
        os_log("removing sync period %s for account %s and component %s", log: .chatHistorySync, type: .debug, period.id.uuidString, period.account.stringValue, period.component?.stringValue ?? "nil");
        _ = try! removeSyncPeriod.update(["id": period.id.uuidString] as [String: Any?]);
    }
    
    func removeSyncPeriods(forAccount account: BareJID, component: BareJID? = nil) {
        if let component = component {
            _ = try! DBConnection.main.prepareStatement("DELETE FROM chat_history_sync WHERE account = :account AND component = :component").update(["account": account, "component": component] as [String: Any?]);
        } else {
            _ = try! DBConnection.main.prepareStatement("DELETE FROM chat_history_sync WHERE account = :account").update(["account": account] as [String: Any?]);
        }
    }
    
    func updatePeriod(_ period: Period, after: String) {
        os_log("updating sync period %s for account %s and component %s to after %s", log: .chatHistorySync, type: .debug, period.id.uuidString, period.account.stringValue, period.component?.stringValue ?? "nil", after);
        _ = try! updateSyncPeriodAfter.update(["id": period.id.uuidString, "after": after] as [String: Any?]);
    }
    
    class Period {
        let id: UUID;
        let account: BareJID;
        let component: BareJID?;
        let from: Date;
        var after: String?;
        let to: Date;
        
        init(id: UUID = UUID(), account: BareJID, component: BareJID? = nil, from: Date, after: String?, to: Date = Date()) {
            self.id = id;
            self.account = account;
            self.component = component;
            self.from = from;
            self.after = after;
            self.to = to;
        }
    }
}
