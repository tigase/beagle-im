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
        
    open func retrieveVCard(for jid: JID, on account: BareJID) async throws -> VCard {
        guard let client = XmppService.instance.getClient(for: account) else {
            throw XMPPError.undefined_condition;
        }
        
        let queryJid = jid.bareJid == account ? nil : jid;
        
        do {
            return try await client.module(.vcard4).retrieveVCard(from: queryJid);
        } catch {
            guard (error as? XMPPError ?? .undefined_condition).condition.type != .wait else {
                throw error;
            }
            return try await client.module(.vcardTemp).retrieveVCard(from: queryJid);
        }
    }
    
    open func refreshVCard(for jid: BareJID, on account: BareJID) async throws -> VCard {
        let vcard = try await retrieveVCard(for: jid.jid(), on: account);
        DBVCardStore.instance.updateVCard(for: jid, on: account, vcard: vcard);
        return vcard;
    }
    
    public static func fetchPhoto(photo: VCard.Photo) async throws -> Data {
        if let binval = photo.binval {
            guard let data = Data(base64Encoded: binval, options: .ignoreUnknownCharacters) else {
                throw XMPPError(condition: .not_acceptable, message: "Unable to decode base64 data");
            }
            return data;
        } else if let uri = photo.uri {
            if uri.hasPrefix("data:image") && uri.contains(";base64,") {
                guard let idx = uri.firstIndex(of: ","), let data = Data(base64Encoded: String(uri.suffix(from: uri.index(after: idx))), options: .ignoreUnknownCharacters) else {
                    throw XMPPError(condition: .not_acceptable, message: "Unable to decode image URI");
                }
                return data;
            } else if let url = URL(string: uri) {
                return try await withUnsafeThrowingContinuation({ continuation in
                    let task = URLSession.shared.dataTask(with: url) { (data, response, err) in
                        if let error = err {
                            continuation.resume(throwing: error);
                        } else {
                            guard let data = data else {
                                continuation.resume(throwing: XMPPError(condition: .item_not_found));
                                return;
                            }
                            continuation.resume(returning: data);
                        }
                    };
                    task.resume();
                })
            } else {
                throw XMPPError(condition: .not_acceptable, message: "Unable to decode image URI");
            }
        } else {
            throw XMPPError(condition: .item_not_found);
        }
    }
}
