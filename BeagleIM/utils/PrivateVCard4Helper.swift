//
// PrivateVCard4Helper.swift
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
import Martin

class PrivateVCard4Helper {
    
    static let NODE = "tigase:vcard:private:0";
    
    static var isEnabled: Bool {
        return Settings.showAdvancedXmppFeatures;
    }
    
    static func retrieve(on account: BareJID, from jid: BareJID) async throws -> VCard {
        if isEnabled, let pubsubModule = XmppService.instance.getClient(for: account)?.module(.pubsub) {
            let items = try await pubsubModule.retrieveItems(from: jid, for: NODE, limit: .items(withIds: ["current"]));
            guard let item = items.items.first.map({ $0.payload }), let vcard = VCard(vcard4: item) else {
                throw XMPPError(condition: .item_not_found);
            }
            return vcard;
        } else {
            throw XMPPError(condition: .item_not_found);
        }
    }
    
    static func publish(on account: BareJID, vcard: VCard) async throws {
        if isEnabled, let pubsubModule = XmppService.instance.getClient(for: account)?.module(.pubsub) {
            let publishOptions = PubSubNodeConfig()
            publishOptions.accessModel = .presence;
            do {
                _ = try await pubsubModule.publishItem(at: account, to: NODE, itemId: "current", payload: vcard.toVCard4(), publishOptions: publishOptions);
            } catch let publishError as XMPPError  {
                guard publishError.condition != .conflict else {
                    throw publishError;
                }
                do {
                    let config = try await pubsubModule.retrieveNodeConfiguration(from: account, node: NODE);
                    config.accessModel = .presence;
                    try await pubsubModule.configureNode(at: account, node: NODE, with: publishOptions);
                } catch {
                    throw publishError;
                }
                _ = try await pubsubModule.publishItem(at: account, to: NODE, itemId: "current", payload: vcard.toVCard4(), publishOptions: publishOptions);
            }
        } else {
            throw XMPPError(condition: .undefined_condition);
        }
    }
}
