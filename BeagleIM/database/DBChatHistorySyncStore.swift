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
import TigaseSQLite3
import Combine

extension Query {
    static let mamSyncInsertPeriod = Query("INSERT INTO chat_history_sync (id, account, component, from_timestamp, from_id, to_timestamp) VALUES (:id, :account, :component, :from_timestamp, :from_id, :to_timestamp)");
    static let mamSyncFindPeriodsForAccount = Query("SELECT id, account, component, from_timestamp, from_id, to_timestamp FROM chat_history_sync WHERE account = :account AND component IS NULL ORDER BY from_timestamp ASC");
    static let mamSyncFindPeriodsForAccountWith = Query("SELECT id, account, component, from_timestamp, from_id, to_timestamp FROM chat_history_sync WHERE account = :account AND component = :component ORDER BY from_timestamp ASC");
    static let mamSyncDeletePeriod = Query("DELETE FROM chat_history_sync WHERE id = :id");
    static let mamSyncDeletePeriodsForAccount = Query("DELETE FROM chat_history_sync WHERE account = :account");
    static let mamSyncDeletePeriodsForAccountWith = Query("DELETE FROM chat_history_sync WHERE account = :account AND component = :component");
    static let mamSyncUpdatePeriodAfter = Query("UPDATE chat_history_sync SET from_id = :after WHERE id = :id");
    static let mamSyncUpdatePeriodTo = Query("UPDATE chat_history_sync SET to_timestamp = :to_timestamp WHERE id = :id");
}

class DBChatHistorySyncStore {
    
    static let instance = DBChatHistorySyncStore()
        
    private var cancellables: Set<AnyCancellable> = [];
    
    init() {
        AccountManager.accountEventsPublisher.sink(receiveValue: { [weak self] event in
            self?.accountChanged(event);
        }).store(in: &cancellables)
    }
    
    func accountChanged(_ event: AccountManager.Event) {
        switch event {
        case .removed(let account):
            removeSyncPeriods(forAccount: account.name);
        default:
            break;
        }
    }

    func addSyncPeriod(_ period: Period) {
        if let last = loadSyncPeriods(forAccount: period.account, component: period.component).last, last.from <= period.from && last.to >= period.from {
            // we only need to update `to` value
            os_log("updating sync period to for account %s and component %s", log: .chatHistorySync, type: .debug, period.account.stringValue, period.component?.stringValue ?? "nil");
            try! Database.main.writer({ database in
                try database.update(query: .mamSyncUpdatePeriodTo, cached: false, params: ["id": last.id.uuidString, "to_timestamp": max(last.to, period.to)]);
            })
            return;
        }
        os_log("adding sync period %s for account %s and component %s from %{time_t}d to %{time_t}d", log: .chatHistorySync, type: .debug, period.id.uuidString, period.account.stringValue, period.component?.stringValue ?? "nil", time_t(period.from.timeIntervalSince1970), time_t(period.to.timeIntervalSince1970));
        try! Database.main.writer({ database in
            try database.insert(query: .mamSyncInsertPeriod, cached: false, params: ["id": period.id.uuidString, "account": period.account, "component": period.component, "from_timestamp": period.from, "to_timestamp": period.to]);
        })
    }
    
    func loadSyncPeriods(forAccount account: BareJID, component: BareJID?) -> [Period] {
        var params = ["account": account];
        if let component = component {
            params["component"] = component;
        }
        
        // how about periods with less than a few minutes/seconds apart? should we merge them?
        let query: Query = component == nil ? .mamSyncFindPeriodsForAccount : .mamSyncFindPeriodsForAccountWith;
        let periods = try! Database.main.reader({ database in
            try database.select(query: query, cached: false, params: params).mapAll({ cursor -> Period? in
                return Period(id: UUID(uuidString: cursor["id"]!)!, account: cursor["account"]!, component: cursor["component"], from: cursor["from_timestamp"]!, after: cursor["from_id"], to: cursor["to_timestamp"]!);
            })
        })
        os_log("loaded %d sync periods for account %s and component %s", log: .chatHistorySync, type: .debug, periods.count, account.stringValue, component?.stringValue ?? "nil");
        return periods;
    }
    
    func removeSyncPerod(_ period: Period) {
        os_log("removing sync period %s for account %s and component %s", log: .chatHistorySync, type: .debug, period.id.uuidString, period.account.stringValue, period.component?.stringValue ?? "nil");
        try! Database.main.writer({ database in
            try database.delete(query: .mamSyncDeletePeriod, cached: false, params: ["id": period.id.uuidString])
        })
    }
    
    func removeSyncPeriods(forAccount account: BareJID, component: BareJID? = nil) {
        try! Database.main.writer({ database in
            if let component = component {
                try database.delete(query: .mamSyncDeletePeriodsForAccountWith, cached: false, params: ["account": account, "component": component]);
            } else {
                try database.delete(query: .mamSyncDeletePeriodsForAccount, cached: false, params: ["account": account]);
            }
        })
    }
    
    func updatePeriod(_ period: Period, after: String) {
        os_log("updating sync period %s for account %s and component %s to after %s", log: .chatHistorySync, type: .debug, period.id.uuidString, period.account.stringValue, period.component?.stringValue ?? "nil", after);
        try! Database.main.writer({ database in
            try database.update(query: .mamSyncUpdatePeriodAfter, cached: false, params: ["id": period.id.uuidString, "after": after]);
        })
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
