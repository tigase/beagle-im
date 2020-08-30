//
// VCardManager.swift
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

class VCardManager {
    
    public static let instance = VCardManager();
    
    open func retrieveVCard(for jid: BareJID, on account: BareJID, completionHandler: ((VCard?)->Void)?) {
        self.retrieveVCard(for: JID(jid), on: account, completionHandler: completionHandler);
    }
    
    open func retrieveVCard(for jid: JID, on account: BareJID, completionHandler: ((VCard?)->Void)?) {
        guard let modulesManager = XmppService.instance.getClient(for: account)?.modulesManager else {
            completionHandler?(nil);
            return;
        }
        
        let queryJid = jid.bareJid == account ? nil : jid;
        if let vcard4Module: VCard4Module = modulesManager.getModule(VCard4Module.ID) {
            self.retrieveVCard(module: vcard4Module, for: queryJid, on: account) { (vcard) in
                guard vcard != nil else {
                    guard let vcardTempModule: VCardTempModule = modulesManager.getModule(VCardTempModule.ID) else {
                        completionHandler?(nil);
                        return;
                    }
                    self.retrieveVCard(module: vcardTempModule, for: queryJid, on: account, completionHandler: completionHandler);
                    return;
                }
                completionHandler?(vcard);
            }
        }
        else if let vcardTempModule: VCardTempModule = modulesManager.getModule(VCardTempModule.ID) {
            self.retrieveVCard(module: vcardTempModule, for: queryJid, on: account, completionHandler: completionHandler);
        } else {
            completionHandler?(nil);
        }
    }
    
    open func refreshVCard(for jid: BareJID, on account: BareJID, completionHandler: ((VCard?)->Void)?) {
        retrieveVCard(for: jid, on: account, completionHandler: { vcard in
            if let vcard = vcard {
                DBVCardStore.instance.updateVCard(for: jid, on: account, vcard: vcard);
            }
            completionHandler?(vcard);
        })
    }
    
    fileprivate func retrieveVCard(module: VCardModuleProtocol, for jid: JID?, on account: BareJID, completionHandler: ((VCard?)->Void)?) {
        module.retrieveVCard(from: jid, onSuccess: { vcard in
            completionHandler?(vcard);
        }, onError: { errorCondition in
            completionHandler?(nil);
        });
    }
}
