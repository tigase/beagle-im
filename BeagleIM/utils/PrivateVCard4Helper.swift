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
import TigaseSwift

class PrivateVCard4Helper {
    
    static let NODE = "tigase:vcard:private:0";
    
    static var isEnabled: Bool {
        return Settings.showAdvancedXmppFeatures.bool();
    }
    
    static func retrieve(on account: BareJID, from jid: BareJID, completionHandler: @escaping (Result<VCard,ErrorCondition>)->Void) {
        if isEnabled, let pubsubModule: PubSubModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PubSubModule.ID) {
            pubsubModule.retrieveItems(from: jid, for: NODE, itemIds: ["current"], completionHandler: { result in
                switch result {
                case .success(let response, let node, let items, _):
                    if let item = items.first.map({ $0.payload }), let vcard = VCard(vcard4: item) {
                        completionHandler(.success(vcard));
                        return;
                    }
                    break;
                default:
                    break;
                }
                completionHandler(.failure(.item_not_found));
            });
        } else {
            completionHandler(.failure(.item_not_found));
        }
    }
    
    static func publish(on account: BareJID, vcard: VCard, completionHandler: @escaping (PubSubPublishItemResult)->Void) {
        if isEnabled, let pubsubModule: PubSubModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PubSubModule.ID) {
            let publishOptions = JabberDataElement(type: .submit);
            publishOptions.addField(HiddenField(name: "FORM_TYPE")).value = "http://jabber.org/protocol/pubsub#publish-options";
            publishOptions.addField(TextSingleField(name: "pubsub#access_model")).value = "presence";
            pubsubModule.publishItem(at: account, to: NODE, itemId: "current", payload: vcard.toVCard4(), publishOptions: publishOptions, completionHandler: { result in
                switch result {
                case .failure(let errorCondition, _, _):
                    guard errorCondition != .conflict else {
                        pubsubModule.retrieveNodeConfiguration(from: account, node: NODE, completionHandler: { res in
                            switch res {
                            case .failure(_, _, _):
                                completionHandler(result);
                            case .success(let configuration):
                                let field = configuration.getField(named: "pubsub#access_model") ?? configuration.addField(TextSingleField(name: "pubsub#access_model"));
                                field.value = "presence";
                                pubsubModule.configureNode(at: account, node: NODE, with: configuration, completionHandler: { res in
                                    switch res {
                                    case .failure(_, _, _):
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
            completionHandler(.failure(errorCondition: .item_not_found, pubSubErrorCondition: nil, response: nil));
        }
    }
}
