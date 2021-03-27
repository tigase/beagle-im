//
// MixEventHandler.swift
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
import Combine

class MixEventHandler: XmppServiceExtension {
        
    static let instance = MixEventHandler();
        
    private init() {
    }
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.$state.sink(receiveValue: { [weak client] state in
            guard let client = client, case .connected(let resumed) = state, !resumed else {
                return;
            }
            let disco = client.module(.disco);
            for channel in client.module(.mix).channelManager.channels(for: client) {
                disco.getItems(for: JID(channel.jid), completionHandler: { result in
                    switch result {
                    case .success(let info):
                        (channel as! Channel).updateOptions({ options in
                            options.features = Set(info.items.compactMap({ $0.node }).compactMap({ Channel.Feature(rawValue: $0) }));
                        })
                    case .failure(_):
                        break;
                    }
                });
            }
        }).store(in: &cancellables);
        client.module(.mix).participantsEvents.sink(receiveValue: { event in
            guard case .joined(let participant) = event, let channel = participant.channel else {
                return;
            }
            
            let jid = participant.jid ?? BareJID(localPart: participant.id + "#" + channel.jid.localPart!, domain: channel.jid.domain);
            DBVCardStore.instance.vcard(for: jid, completionHandler: { vcard in
                guard vcard == nil else {
                    return;
                }
                VCardManager.instance.refreshVCard(for: jid, on: channel.account, completionHandler: nil);
            })
        }).store(in: &cancellables);
        client.module(.mix).messagesPublisher.sink(receiveValue: { e in
            DBChatHistoryStore.instance.append(for: e.channel as! Channel, message: e.message, source: .stream);
        }).store(in: &cancellables);
    }
    
}
