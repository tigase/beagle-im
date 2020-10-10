//
// DBVCardStore.swift
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

    static let vcardInsert = Query("INSERT INTO vcards_cache (jid, data, timestamp) VALUES (:jid,:data,:timestamp)");
    static let vcardUpdate = Query("UPDATE vcards_cache SET data = :data, timestamp = :timestamp WHERE jid = :jid");
    static let vcardFindByJid = Query("SELECT data FROM vcards_cache WHERE jid = :jid");
    
}

class DBVCardStore {
    
    public static let VCARD_UPDATED = Notification.Name("vcardUpdated");
    public static let instance = DBVCardStore();
    
    private let dispatcher = QueueDispatcher(label: "vcard_store");
        
    private init() {
        
    }
    
    open func vcard(for jid: BareJID, completionHandler: @escaping (VCard?)->Void) {
        dispatcher.async {
            let data: String? = try! Database.main.reader({ database in
                try database.select(query: .vcardFindByJid, params: ["jid": jid]).mapFirst({ cursor -> String? in
                    return cursor.string(for: "data");
                })
            });
            
            guard let value = data, let elem = Element.from(string: value) else {
                completionHandler(nil);
                return;
            }
            completionHandler(VCard(vcard4: elem) ?? VCard(vcardTemp: elem));
        }
    }
    
    open func updateVCard(for jid: BareJID, on account: BareJID, vcard: VCard) {
        dispatcher.async {
            try! Database.main.writer({ database in
                let params: [String: Any?] = ["jid": jid, "data": vcard.toVCard4(), "timestamp": Date()];
                try database.update(query: .vcardUpdate, params: params);
                if database.changes == 0 {
                    try database.insert(query: .vcardInsert, params: params);
                }
            })
            NotificationCenter.default.post(name: DBVCardStore.VCARD_UPDATED, object: VCardItem(vcard: vcard, for: jid, on: account));
        }
    }
    
    class VCardItem {
        
        let vcard: VCard;
        let account: BareJID;
        let jid: BareJID;
        
        init(vcard: VCard, for jid: BareJID, on account: BareJID) {
            self.vcard = vcard;
            self.jid = jid;
            self.account = account;
        }
    }
    
}
