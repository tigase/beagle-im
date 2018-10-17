//
//  PresenceRosterEventHandler.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 27/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
                
                alert.run(completionHandler: { (result) in
                    if result == .alertFirstButtonReturn {
                        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(PresenceModule.ID) else {
                            return;
                        }
                        
                        presenceModule.subscribed(by: jid);
                        
                        if Settings.requestPresenceSubscription.bool() {
                            presenceModule.subscribe(to: jid);
                        }
                    } else {
                        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(PresenceModule.ID) else {
                            return;
                        }
                        
                        presenceModule.unsubscribed(by: jid);
                    }
                });
            }
        default:
            break;
        }
    }
    
}
