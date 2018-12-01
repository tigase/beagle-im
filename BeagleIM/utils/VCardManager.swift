//
// VCardManager.swift
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

class VCardManager {
    
    public static let instance = VCardManager();
    
    open func refreshVCard(for jid: BareJID, on account: BareJID, completionHandler: ((VCard?)->Void)?) {
        guard let modulesManager = XmppService.instance.getClient(for: account)?.modulesManager else {
            completionHandler?(nil);
            return;
        }
        
        let queryJid = jid == account ? nil : JID(jid);
        if let vcard4Module: VCard4Module = modulesManager.getModule(VCard4Module.ID) {
            self.refreshVCard(module: vcard4Module, for: queryJid, on: account) { (vcard) in
                guard vcard != nil else {
                    guard let vcardTempModule: VCardTempModule = modulesManager.getModule(VCardTempModule.ID) else {
                        completionHandler?(nil);
                        return;
                    }
                    self.refreshVCard(module: vcardTempModule, for: queryJid, on: account, completionHandler: completionHandler);
                    return;
                }
            }
        }
        else if let vcardTempModule: VCardTempModule = modulesManager.getModule(VCardTempModule.ID) {
            self.refreshVCard(module: vcardTempModule, for: queryJid, on: account, completionHandler: completionHandler);
        } else {
            completionHandler?(nil);
        }
    }
    
    fileprivate func refreshVCard(module: VCardModuleProtocol, for jid: JID?, on account: BareJID, completionHandler: ((VCard?)->Void)?) {
        module.retrieveVCard(from: jid, onSuccess: { vcard in
            DBVCardStore.instance.updateVCard(for: jid?.bareJid ?? account, on: account, vcard: vcard);
            completionHandler?(vcard);
        }, onError: { errorCondition in
            completionHandler?(nil);
        });
    }
}
