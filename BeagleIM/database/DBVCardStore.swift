//
// DBVCardStore.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation
import TigaseSwift

class DBVCardStore {
    
    public static let VCARD_UPDATED = Notification.Name("vcardUpdated");
    public static let instance = DBVCardStore();
    
    fileprivate let dispatcher = QueueDispatcher(label: "vcard_store");
    
    fileprivate let updateVCardStmt = try! DBConnection.main.prepareStatement("UPDATE vcards_cache SET data = :data, timestamp = :timestamp WHERE jid = :jid");
    fileprivate let insertVCardStmt = try! DBConnection.main.prepareStatement("INSERT INTO vcards_cache (jid, data, timestamp) VALUES (:jid,:data,:timestamp)");
    fileprivate let getVCardStmt = try! DBConnection.main.prepareStatement("SELECT data FROM vcards_cache WHERE jid = :jid");
    
    fileprivate init() {
        
    }
    
    open func vcard(for jid: BareJID, completionHandler: @escaping (VCard?)->Void) {
        dispatcher.async {
            let params: [String: Any?] = ["jid": jid];
            let elem = try! self.getVCardStmt.findFirst(params, map: { (cursor) -> Element? in
                return Element.from(string: cursor["data"]!);
            });
            completionHandler(VCard(vcard4: elem) ?? VCard(vcardTemp: elem));
        }
    }
    
    open func updateVCard(for jid: BareJID, on account: BareJID, vcard: VCard) {
        dispatcher.async {
            let params: [String: Any?] = ["jid": jid, "data": vcard.toVCard4(), "timestamp": Date()];
            if try! self.updateVCardStmt.update(params) == 0 {
                _ = try! self.insertVCardStmt.update(params);
            }
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
