//
//  VCardManager.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 06.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
