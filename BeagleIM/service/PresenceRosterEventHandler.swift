//
// PresenceRosterEventHandler.swift
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

import AppKit
import TigaseSwift

class PresenceRosterEventHandler: XmppServiceEventHandler {
    
    let events: [Event] = [RosterModule.ItemUpdatedEvent.TYPE,PresenceModule.BeforePresenceSendEvent.TYPE, PresenceModule.SubscribeRequestEvent.TYPE];
    
    var status: XmppService.Status {
        return XmppService.instance.status;
    }
    
    func handle(event: Event) {
        switch event {
        case let e as RosterModule.ItemUpdatedEvent:
            NotificationCenter.default.post(name: DBRosterStore.ITEM_UPDATED, object: e);
        case let e as PresenceModule.BeforePresenceSendEvent:
            e.presence.show = status.show;
            e.presence.status = status.message;
        case let e as PresenceModule.SubscribeRequestEvent:
            guard let jid = e.presence.from else {
                return;
            }
            DispatchQueue.main.async {
                let alert = Alert();
                alert.icon = NSImage(named: NSImage.userName);
                alert.messageText = "Authorization request";
                alert.informativeText = "\(jid.bareJid) requests authorization to access information about you presence";
                alert.addButton(withTitle: "Accept");
                alert.addButton(withTitle: "Deny");
                
                if let blockingModule: BlockingCommandModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(BlockingCommandModule.ID), blockingModule.isAvailable {
                    alert.addSpacing();
                    alert.addButton(withTitle: "Block");
                }
                
                alert.run(completionHandler: { (controller, result, completionHandler) in
                    if result == .alertFirstButtonReturn {
                        completionHandler();
                        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(PresenceModule.ID) else {
                            return;
                        }
                        
                        presenceModule.subscribed(by: jid);
                        
                        if Settings.requestPresenceSubscription.bool() {
                            presenceModule.subscribe(to: jid);
                        }
                    } else if result == .alertSecondButtonReturn {
                        completionHandler();
                        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(PresenceModule.ID) else {
                            return;
                        }
                        
                        presenceModule.unsubscribed(by: jid);
                    } else if result == .alertThirdButtonReturn {
                        guard let blockingModule: BlockingCommandModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(BlockingCommandModule.ID) else {
                            return;
                        }
                        DispatchQueue.main.async {
                            controller.showProgressIndicator();
                        }
                        if let presenceModule: PresenceModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(PresenceModule.ID) {
                            presenceModule.unsubscribed(by: jid);
                        }
                        blockingModule.block(jids: [jid.withoutResource], completionHandler: { result in
                            DispatchQueue.main.async {
                                controller.hideProgressIndicator();
                                switch result {
                                case .success(_):
                                    // everything went ok!
                                    completionHandler();
                                    break;
                                case .failure(let err):
                                    let alert = NSAlert();
                                    alert.messageText = "Error";
                                    alert.informativeText = "Server returned an error: \(err.rawValue)";
                                    alert.addButton(withTitle: "OK");
                                    alert.beginSheetModal(for: controller.view.window!, completionHandler: { res in
                                        // do we have anything to do here?
                                    });
                                    break;
                                }
                            }
                        });
                    }
                });
            }
        default:
            break;
        }
    }
    
}
