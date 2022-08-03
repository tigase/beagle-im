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
import Martin

class VCardManager {
    
    public static let instance = VCardManager();
    
    open func retrieveVCard(for jid: BareJID, on account: BareJID, completionHandler: @escaping (Result<VCard,XMPPError>)->Void) {
        self.retrieveVCard(for: JID(jid), on: account, completionHandler: completionHandler);
    }
    
    open func retrieveVCard(for jid: JID, on account: BareJID, completionHandler: @escaping (Result<VCard,XMPPError>)->Void) {
        guard let client = XmppService.instance.getClient(for: account) else {
            completionHandler(.failure(.undefined_condition));
            return;
        }
        
        let queryJid = jid.bareJid == account ? nil : jid;
        
        self.retrieveVCard(module: client.module(.vcard4), for: queryJid, on: account) { (result) in
            switch result {
            case .success(let vcard):
                completionHandler(.success(vcard));
            case .failure(_):
                self.retrieveVCard(module: client.module(.vcardTemp), for: queryJid, on: account, completionHandler: completionHandler);
            }
        }
    }
    
    open func refreshVCard(for jid: BareJID, on account: BareJID, completionHandler: ((Result<VCard,XMPPError>)->Void)?) {
        retrieveVCard(for: jid, on: account, completionHandler: { result in
            switch result {
            case .success(let vcard):
                DBVCardStore.instance.updateVCard(for: jid, on: account, vcard: vcard);
            default:
                break;
            }
            completionHandler?(result);
        })
    }
    
    fileprivate func retrieveVCard(module: VCardModuleProtocol, for jid: JID?, on account: BareJID, completionHandler: @escaping (Result<VCard,XMPPError>)->Void) {
        module.retrieveVCard(from: jid, completionHandler: completionHandler);
    }
}
