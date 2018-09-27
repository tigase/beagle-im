//
//  DBVCardStore.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 06.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
