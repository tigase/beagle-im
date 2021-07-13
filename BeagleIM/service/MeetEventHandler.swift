//
// MeetEventHandler.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import Combine
import TigaseSwift
import AppKit

class MeetEventHandler: XmppServiceExtension {
    
    static let instance = MeetEventHandler();
    
    private var notifications: [String: Alert] = [:];
    
    private init() {
        
    }
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.module(.meet).eventsPublisher.sink(receiveValue: { [weak self] event in
            switch event {
            case .inivitation(let action, let sender):
                switch action {
                case .propose(let id, let meetJid, let media):
                    DispatchQueue.main.async {
                        let alert = Alert();
                        alert.icon = NSImage(named: "videoCall");
                        alert.messageText = "Invitiation to meeting";
                        alert.informativeText = "User \(DBRosterStore.instance.item(for: client, jid: sender.withoutResource)?.name ?? sender.bareJid.stringValue) invites you to join a meeting";
                        alert.addButton(withTitle: "Accept");
                        alert.addButton(withTitle: "Decline");

                        self?.notifications[id] = alert;
                        
                        alert.run(completionHandler: { response in
                            switch response {
                            case .alertFirstButtonReturn:
                                client.module(.meet).sendMessageInitiation(action: .proceed(id: id), to: sender);
                                MeetManager.instance.registerMeet(at: JID(meetJid), using: client)?.join();
                            default:
                                client.module(.meet).sendMessageInitiation(action: .reject(id: id), to: sender);
                            }
                        })
                    }
                case .accept(let id):
                    break;
                case .proceed(let id):
                    break;
                case .retract(let id):
                    self?.dismissNotification(forId: id);
                case .reject(let id):
                    self?.dismissNotification(forId: id)
                }

                break;
            default:
                break;
            }
        }).store(in: &cancellables);
    }
    
    func dismissNotification(forId id: String) {
        DispatchQueue.main.async {
            self.notifications.removeValue(forKey: id)?.dismiss();
        }
    }
}
