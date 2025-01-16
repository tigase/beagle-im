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
    
    static func retrieve(on account: BareJID, from jid: BareJID, completionHandler: @escaping (Result<VCard,XMPPError>)->Void) {
        if isEnabled, let pubsubModule = XmppService.instance.getClient(for: account)?.module(.pubsub) {
            pubsubModule.retrieveItems(from: jid, for: NODE, limit: .items(withIds: ["current"]), completionHandler: { result in
                switch result {
                case .success(let items):
                    if let item = items.items.first.map({ $0.payload }), let vcard = VCard(vcard4: item) {
                        completionHandler(.success(vcard));
                        return;
                    }
                    break;
                default:
                    break;
                }
                completionHandler(.failure(XMPPError(condition: .item_not_found)));
            });
        } else {
            completionHandler(.failure(XMPPError(condition: .item_not_found)));
        }
    }
    
    static func publish(on account: BareJID, vcard: VCard, completionHandler: @escaping (Result<String,XMPPError>)->Void) {
        if isEnabled, let pubsubModule = XmppService.instance.getClient(for: account)?.module(.pubsub) {
            let publishOptions = PubSubNodeConfig();
            publishOptions.FORM_TYPE = "http://jabber.org/protocol/pubsub#publish-options";
            publishOptions.accessModel = .presence
            pubsubModule.publishItem(at: account, to: NODE, itemId: "current", payload: vcard.toVCard4(), publishOptions: publishOptions, completionHandler: { result in
                switch result {
                case .failure(let error):
                    guard error.condition != .conflict else {
                        pubsubModule.retrieveNodeConfiguration(from: account, node: NODE, completionHandler: { res in
                            switch res {
                            case .failure(_):
                                completionHandler(result);
                            case .success(let configuration):
                                configuration.accessModel = .presence;
                                pubsubModule.configureNode(at: account, node: NODE, with: configuration, completionHandler: { res in
                                    switch res {
                                    case .failure(_):
                                        completionHandler(result);
                                    case .success:
                                        pubsubModule.publishItem(at: account, to: NODE, itemId: "current", payload: vcard.toVCard4(), publishOptions: publishOptions, completionHandler: { result in
                                            completionHandler(result);
                                        });
                                    }
                                })
                            }
                        })
                        return;
                    }
                default:
                    break;
                }
                completionHandler(result);
            });
        } else {
            completionHandler(.failure(.undefined_condition));
        }
    }
}
