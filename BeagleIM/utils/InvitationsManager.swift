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
    
    static let INVITATION_CLICKED = Notification.Name(rawValue: "invitationClicked");
    static let INVITATIONS_ADDED = Notification.Name(rawValue: "invitationsAdded");
    static let INVITATIONS_REMOVED = Notification.Name(rawValue: "invitationsRemoved");
    
    static let instance = InvitationManager();
 
    private var peristentItems: Set<InvitationItem> = [];
    private var volatileItems: Set<InvitationItem> = [];

    let dispatcher = QueueDispatcher(label: "InvitationManagerQueue");
    
    var items: Set<InvitationItem> {
        return dispatcher.sync {
            let connectedAccounts = Set(XmppService.instance.clients.values.filter({ $0.state == .connected }).map({ $0.sessionObject.userBareJid! }));
            let result = peristentItems.filter({ connectedAccounts.contains($0.account) })
            return result.union(volatileItems)
        }
    }
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(accountStatusChanged(_:)), name: XmppService.ACCOUNT_STATUS_CHANGED, object: nil);        
    }
    
    func addPresenceSubscribe(for account: BareJID, from jid: JID) {
        dispatcher.async {
            let invitation = InvitationItem(type: .presenceSubscription, account: account, jid: jid, object: nil);
            guard !self.volatileItems.contains(invitation) else {
                return;
            }
            self.volatileItems.insert(invitation);

            self.addded(invitations: [invitation]);
        }
    }

    func addMucInvitation(for account: BareJID, roomJid: BareJID, invitation mucInvitation: MucModule.Invitation) {
        let jid = JID(roomJid);
        dispatcher.async {
            let invitation = InvitationItem(type: .mucInvitation, account: account, jid: jid, object: mucInvitation);
            guard !self.peristentItems.contains(invitation) else {
                return;
            }
            self.peristentItems.insert(invitation);
            
            self.addded(invitations: [invitation]);
        }
    }
    
    func mucJoined(on account: BareJID, roomJid: BareJID) {
        dispatcher.async {
            let tmp = InvitationItem(type: .mucInvitation, account: account, jid: JID(roomJid), object: nil);
            if let invitation = self.peristentItems.remove(tmp) {
                self.removed(invitations: [invitation]);
            }
        }
    }
    
    func handle(invitationWithId id: String, window: NSWindow) {
        dispatcher.async {
            guard let invitation = self.peristentItems.first(where: { $0.id == id }) else {
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
                NotificationCenter.default.post(name: InvitationManager.INVITATION_CLICKED, object: invitation);
            }
        }
    }
    
    func remove(invitation: InvitationItem) {
        dispatcher.async {
            guard self.peristentItems.remove(invitation) != nil || self.volatileItems.remove(invitation) != nil else {
                return;
            }
            self.removed(invitations: [invitation]);
        }
    }
 
    @objc func accountStatusChanged(_ notification: Notification) {
        guard let account = notification.object as? BareJID else {
            return;
        }

        let connected = XmppService.instance.getClient(for: account)?.state ?? .disconnected == .connected;
        dispatcher.async {
            if connected {
                let toAdd = self.peristentItems.filter({ $0.account == account });
                self.addded(invitations: Array(toAdd));
            } else {
                let toRemove = self.volatileItems.filter({ $0.account == account });
                self.volatileItems.subtract(toRemove);
                self.removed(invitations: Array(toRemove.union(self.peristentItems.filter({ $0.account == account }))));
            }
        }
    }
    
    private var delayedInvitations: [InvitationItem] = [];
    private var delayedTimer: Foundation.Timer?
    private func addded(invitations: [InvitationItem]) {
        delayedInvitations = invitations + delayedInvitations;
        dispatcher.asyncAfter(deadline: .now() + 0.2, execute: {
            guard !self.delayedInvitations.isEmpty else {
                return;
            }
            self.delayedAdded(invitations: self.delayedInvitations);
            self.delayedInvitations = [];
        })
    }
    
    private func delayedAdded(invitations: [InvitationItem]) {
        NotificationCenter.default.post(name: InvitationManager.INVITATIONS_ADDED, object: invitations);
        for invitation in invitations {
            switch invitation.type {
            case .mucInvitation:
                deliverMucInvitationNotification(invitation: invitation);
            case .presenceSubscription:
                deliverPresenceSubscriptionNotification(invitation: invitation);
            }
        }
    }
    
    private func removed(invitations invites: [InvitationItem]) {
        var invitations = invites;
        if !delayedInvitations.isEmpty {
            let toSkip = Set(delayedInvitations).intersection(invitations);
            if !toSkip.isEmpty {
                delayedInvitations.removeAll(where: { toSkip.contains($0)}) ;
                invitations = invitations.filter({ !toSkip.contains($0) });
            }
        }
        NotificationCenter.default.post(name: InvitationManager.INVITATIONS_REMOVED, object: invitations);
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: invitations.map({ $0.id }));
    }
    
    private func deliverPresenceSubscriptionNotification(invitation: InvitationItem) {
        let rosterItem = XmppService.instance.getClient(for: invitation.account)?.rosterStore?.get(for: invitation.jid);
        let content = UNMutableNotificationContent();
        content.title = "Authorization request";
        content.body = "\(rosterItem?.name ?? invitation.jid.stringValue) requests authorization to access information about you presence";
        content.sound = UNNotificationSound.default;
        content.userInfo = ["account": invitation.account.stringValue, "jid": invitation.jid.stringValue, "id": "presence-subscription-request"];
        let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
    }
    
    private func deliverMucInvitationNotification(invitation: InvitationItem) {
        let mucInvitation = invitation.object as! MucModule.Invitation;
        _ = XmppService.instance.getClient(for: invitation.account)?.rosterStore?.get(for: invitation.jid);
        let content = UNMutableNotificationContent();
        content.title = "Invitation to groupchat";
        content.body = "You (\(invitation.account)) were invited to the groupchat \(mucInvitation.roomJid)";
        content.sound = UNNotificationSound.default;
        content.userInfo = ["account": invitation.account.stringValue, "jid": invitation.jid.stringValue, "id": "presence-subscription-request"];
        let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
    }
}
