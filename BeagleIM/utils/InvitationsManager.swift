//
//  InvitationsManager.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 17/02/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift
import UserNotifications

class InvitationManager {
    
    static let INVITATIONS_CHANGED = Notification.Name(rawValue: "invitationsChanged");
    
    static let instance = InvitationManager();
 
    private var allItems: [InvitationItem] = [] {
        didSet {
            self.items = self.allItems.filter({ it in
                return (XmppService.instance.getClient(for: it.account)?.state ?? .disconnected) == .connected;
            }).sorted(by: { (i1, i2) -> Bool in
                return i1.jid.stringValue < i2.jid.stringValue;
            });
        }
    }
    
    private(set) var items: [InvitationItem] = [] {
        didSet {
            NotificationCenter.default.post(name: InvitationManager.INVITATIONS_CHANGED, object: self);
        }
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(accountStatusChanged(_:)), name: XmppService.ACCOUNT_STATUS_CHANGED, object: nil);
    }
    
    func addPresenceSubscribe(for account: BareJID, from jid: JID) {
        DispatchQueue.main.async {
            var items = self.allItems.filter({ (it) -> Bool in
                return it.jid != jid || it.type != .presenceSubscription;
            })
            let invitation = InvitationItem(type: .presenceSubscription, account: account, jid: jid, object: nil);
            items.append(invitation);
            self.allItems = items;
            
            let rosterItem = XmppService.instance.getClient(for: account)?.rosterStore?.get(for: jid);
            var content = UNMutableNotificationContent();
            content.title = "Authorization request";
            content.body = "\(rosterItem?.name ?? jid.stringValue) requests authorization to access information about you presence";
            content.sound = UNNotificationSound.default;
            content.userInfo = ["account": account.stringValue, "jid": jid.stringValue, "id": "presence-subscription-request"];
            let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
        }
    }

    func addMucInvitation(for account: BareJID, roomJid: BareJID, invitation mucInvitation: MucModule.Invitation) {
        let jid = JID(roomJid);
        DispatchQueue.main.async {
            var items = self.allItems.filter({ (it) -> Bool in
                return it.jid != jid || it.type != .mucInvitation;
            })
            let invitation = InvitationItem(type: .mucInvitation, account: account, jid: jid, object: mucInvitation);
            items.append(invitation);
            self.allItems = items;
            
            let rosterItem = XmppService.instance.getClient(for: account)?.rosterStore?.get(for: jid);
            var content = UNMutableNotificationContent();
            content.title = "Invitation to groupchat";
            content.body = "You (\(invitation.account)) were invited to the groupchat \(mucInvitation.roomJid)";
            content.sound = UNNotificationSound.default;
            content.userInfo = ["account": account.stringValue, "jid": jid.stringValue, "id": "presence-subscription-request"];
            let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
            UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
        }
    }
    
    func mucJoined(on account: BareJID, roomJid: BareJID) {
        DispatchQueue.main.async {
            self.allItems = self.allItems.filter({ (it) -> Bool in
                return !(it.type == .mucInvitation && it.account == account && it.jid.bareJid == roomJid);
            })
        }
    }
    
    func handle(invitationWithId id: String, window: NSWindow) {
        DispatchQueue.main.async {
            guard let invitation = self.allItems.first(where: { (it) -> Bool in
                return it.id == id;
            }) else {
                return;
            }
            self.handle(invitation: invitation, window: window);
        }
    }

    func handle(invitation: InvitationItem, window: NSWindow) {
        DispatchQueue.main.async {
            switch invitation.type {
            case .mucInvitation:
                guard let mucModule: MucModule = XmppService.instance.getClient(for: invitation.account)?.modulesManager.getModule(MucModule.ID) else {
                    return;
                }

                let mucInvitation = invitation.object as! MucModule.Invitation;
                let alert = NSAlert();
                alert.messageText = "Invitation to groupchat";
                if let inviter = mucInvitation.inviter {
                    let name = XmppService.instance.clients.values.flatMap({ (client) -> [String] in
                        guard let n = client.rosterStore?.get(for: inviter)?.name else {
                            return [];
                        }
                        return ["\(n) (\(inviter))"];
                    }).first ?? inviter.stringValue;
                    alert.informativeText = "User \(name) invited you (\(invitation.account)) to the groupchat \(mucInvitation.roomJid)";
                } else {
                    alert.informativeText = "You (\(invitation.account)) were invited to the groupchat \(mucInvitation.roomJid)";
                }
                alert.addButton(withTitle: "Accept");
                alert.addButton(withTitle: "Decline");
                alert.beginSheetModal(for: window, completionHandler: { response in
                    if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                        let roomName = mucInvitation.roomJid.localPart!;
                        let nickname = AccountManager.getAccount(for: invitation.account)?.nickname ?? invitation.account.localPart!;
                        _ = mucModule.join(roomName: roomName, mucServer: mucInvitation.roomJid.domain, nickname: nickname, password: mucInvitation.password);
                        
                        PEPBookmarksModule.updateOrAdd(for: invitation.account, bookmark: Bookmarks.Conference(name: roomName, jid: JID(BareJID(localPart: roomName, domain: mucInvitation.roomJid.domain)), autojoin: true, nick: nickname, password: mucInvitation.password));
                    } else {
                        mucModule.decline(invitation: mucInvitation, reason: nil);
                    }
                    self.remove(invitation: invitation);
                })
            case .presenceSubscription:
                let jid = invitation.jid;
                let account = invitation.account;
                let alert = NSAlert();
                alert.icon = NSImage(named: NSImage.userName);
                alert.messageText = "Authorization request";
                alert.informativeText = "\(jid.bareJid) requests authorization to access information about you presence";
                alert.addButton(withTitle: "Accept");
                alert.addButton(withTitle: "Deny");
                
                if let blockingModule: BlockingCommandModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(BlockingCommandModule.ID), blockingModule.isAvailable {
                    //alert.addSpacing();
                    alert.addButton(withTitle: "Block");
                }
                
                alert.beginSheetModal(for: window, completionHandler: { result in
                    if result == .alertFirstButtonReturn {
                        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID) else {
                            return;
                        }
                        
                        presenceModule.subscribed(by: jid);
                        
                        if Settings.requestPresenceSubscription.bool() {
                            presenceModule.subscribe(to: jid);
                        }
                        self.remove(invitation: invitation);
                    } else if result == .alertSecondButtonReturn {
                        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID) else {
                            return;
                        }
                        
                        presenceModule.unsubscribed(by: jid);
                        self.remove(invitation: invitation);
                    } else if result == .alertThirdButtonReturn {
                        guard let blockingModule: BlockingCommandModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(BlockingCommandModule.ID) else {
                            return;
                        }
                        if let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID) {
                            presenceModule.unsubscribed(by: jid);
                        }

                        self.remove(invitation: invitation);
                        blockingModule.block(jids: [jid.withoutResource], completionHandler: { result in
                            DispatchQueue.main.async {
                                switch result {
                                case .success(_):
                                    // everything went ok!
                                    break;
                                case .failure(let err):
                                    let alert = Alert();
                                    alert.messageText = "It was not possible to block \(jid.stringValue)";
                                    alert.informativeText = "Server returned an error: \(err.rawValue)";
                                    alert.addButton(withTitle: "OK");
                                    alert.run(completionHandler: { res in
                                        // do we have anything to do here?
                                    });
                                    break;
                                }
                            }
                        });
                    }
                });

            }
        }
    }
    
    func remove(invitation: InvitationItem) {
        DispatchQueue.main.async {
            self.allItems = self.allItems.filter({ (it) -> Bool in
                return it.jid != invitation.jid || it.type != invitation.type;
            });
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [invitation.id]);
        }
    }
 
    @objc func accountStatusChanged(_ notification: Notification) {
        guard let account = notification.object as? BareJID, XmppService.instance.getClient(for: account)?.state ?? .disconnected == .disconnected else {
            return;
        }
        DispatchQueue.main.async {
            var removed = self.allItems;
            self.allItems = self.allItems.filter({ (it) -> Bool in
                return it.account != account && it.type != .presenceSubscription;
            });
            removed.removeAll(where: { (it) -> Bool in
                return !self.allItems.contains(it);
            });
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: removed.map({ it in it.id }));
        }
    }
    
}
