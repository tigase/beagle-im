//
// DBAccountStore.swift
//
// BeagleIM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

extension Query {
    static let accountsList = Query("SELECT name, enabled, server_endpoint, roster_version, status_message, last_endpoint, additional FROM accounts");
    static let accountInsert = Query("INSERT INTO accounts (name, enabled, server_endpoint, roster_version, status_message, additional) VALUES (:name, :enabled, :server_endpoint, :roster_version, :status_message, :push, :additional)");
    static let accountDelete = Query("DELETE FROM accounts WHERE name = :name");
}

public class DBAccountStore {
        
    static func create(account: Account) throws {
        try Database.main.writer({ writer in
            try writer.insert(query: .accountInsert, params: ["name": account.name, "enabled": account.enabled, "server_endpoint": account.serverEndpoint, "roster_version": account.rosterVersion, "status_message": account.statusMessage, "additional": account.additional])
        })
    }
    
    static func delete(account: Account) throws {
        try Database.main.writer({ writer in
            try writer.delete(query: .accountDelete, params: ["name", account.name]);
        })
    }
    
    static func update(from: Account, to: Account) throws {
        guard from.name == to.name else {
            throw XMPPError(condition: .not_acceptable);
        }
        var params: [String: Any] = [:];
        if from.enabled != to.enabled {
            params["enabled"] = to.enabled;
        }
        if from.serverEndpoint != to.serverEndpoint {
            params["server_endpoint"] = to.serverEndpoint;
        }
        if from.rosterVersion != to.rosterVersion {
            params["roster_version"] = to.rosterVersion;
        }
        if from.statusMessage != to.statusMessage {
            params["status_message"] = to.statusMessage;
        }
        if from.additional != to.additional {
            params["additional"] = to.additional;
        }
        
        guard !params.isEmpty else {
            return;
        }
        
        let query = "UPDATE accounts SET \(params.keys.map({ "\($0) = :\($0)" }).joined(separator: ", ")) WHERE name = :name";
        
        params["name"] = to.name;
        
        try Database.main.writer({ writer in
            try writer.update(query, cached: false, params: params);
        })
    }
    
    static func list() throws -> [Account] {
        return try Database.main.reader({ reader in
            try reader.select(query: .accountsList, params: [:]).mapAll({ cursor in
                return Account(name: cursor.bareJid(for: "name")!, enabled: cursor.bool(for: "enabled"), serverEndpoint: cursor.object(for: "server_endpoint"), lastEndpoint: cursor.object(for: "last_endpoint"), rosterVersion: cursor.string(for: "roster_version"), statusMessage: cursor.string(for: "status_message"), additional: cursor.object(for: "additional")!);
            })
        })
    }
    
}
