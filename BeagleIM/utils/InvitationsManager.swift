//
//  InvitationsManager.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 17/02/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import AppKit
import Martin
import UserNotifications
import Combine

class InvitationManager {
    
    static let INVITATION_CLICKED = Notification.Name(rawValue: "invitationClicked");
//    static let INVITATIONS_ADDED = Notification.Name(rawValue: "invitationsAdded");
//    static let INVITATIONS_REMOVED = Notification.Name(rawValue: "invitationsRemoved");
    
    static let instance = InvitationManager();
 
    @Published
    private var peristentItems: Set<InvitationItem> = [];
    @Published
    private var volatileItems: Set<InvitationItem> = [];

    private var cancellables: Set<AnyCancellable> = [];
    let queue = DispatchQueue(label: "InvitationManagerQueue");
    
    public let itemsPublisher: PassthroughSubject<Set<InvitationItem>, Never> = PassthroughSubject();

    private var order: Int = 1;
    
    init() {
        XmppService.instance.$connectedClients.receive(on: queue).map({ $0.map({ $0.userBareJid }) }).sink(receiveValue: { accounts in
            self.volatileItems = self.volatileItems.filter({ accounts.contains($0.account) });
        }).store(in: &cancellables);
        XmppService.instance.$connectedClients.receive(on: queue).map({ $0.map({ $0.userBareJid })}).combineLatest($peristentItems, { accounts, invites in
            return invites.filter({ accounts.contains($0.account) });
        }).combineLatest($volatileItems, { persistent, volatile -> Set<InvitationItem> in
            return persistent.union(volatile);
        }).debounce(for: 0.1, scheduler: DispatchQueue.main).subscribe(itemsPublisher).store(in: &cancellables);
    }
    
    func nextOrder() -> Int {
        defer {
            order = order + 1;
        }
        return order;
    }
    
    func invitation(type: InvitationItemType, account: BareJID, jid: JID) -> InvitationItem? {
        queue.sync {
            return self.volatileItems.first(where: { $0.type == type && $0.account == account && $0.jid == jid }) ?? self.peristentItems.first(where: { $0.type == type && $0.account == account && $0.jid == jid });
        }
    }
    
    func addPresenceSubscribe(for account: BareJID, from jid: JID) {
        queue.async {
            let invitation = InvitationItem(type: .presenceSubscription, account: account, jid: jid, object: nil, order:  self.nextOrder());
            guard !self.volatileItems.contains(invitation) else {
                return;
            }
            self.volatileItems.insert(invitation);

            self.addded(invitations: [invitation]);
        }
    }

    func addMucInvitation(for account: BareJID, roomJid: BareJID, invitation mucInvitation: MucModule.Invitation) {
        let jid = JID(roomJid);
        queue.async {
            let invitation = InvitationItem(type: .mucInvitation, account: account, jid: jid, object: mucInvitation, order:  self.nextOrder());
            guard !self.peristentItems.contains(invitation) else {
                return;
            }
            self.peristentItems.insert(invitation);
            
            self.addded(invitations: [invitation]);
        }
    }
    
    func mucJoined(on account: BareJID, roomJid: BareJID) {
        queue.async {
            let tmp = InvitationItem(type: .mucInvitation, account: account, jid: JID(roomJid), object: nil, order:  self.nextOrder());
            if let invitation = self.peristentItems.remove(tmp) {
                self.removed(invitations: [invitation]);
            }
        }
    }
    
    func handle(invitationWithId id: String, window: NSWindow) {
        queue.async {
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
                guard let mucModule = XmppService.instance.getClient(for: invitation.account)?.module(.muc) else {
                    return;
                }

                let mucInvitation = invitation.object as! MucModule.Invitation;
                let alert = NSAlert();
                alert.messageText = NSLocalizedString("Invitation to groupchat", comment: "invitation alert - title");
                if let inviter = mucInvitation.inviter {
                    let name = XmppService.instance.clients.values.compactMap({ (client) -> String? in
                        if let n = DBRosterStore.instance.item(for: client, jid: inviter)?.name {
                            return "\(n) (\(inviter))";
                        } else {
                            return nil;
                        }
                    }).first ?? inviter.description;
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("User %@ invited you (%@) to the groupchat %@", comment: "invitation alert - message"), name, invitation.account.description, mucInvitation.roomJid.description);
                } else {
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("You (%@) were invited to the groupchat %@", comment: "invitation alert - message"), invitation.account.description, mucInvitation.roomJid.description);
                }
                alert.addButton(withTitle: NSLocalizedString("Accept", comment: "Button"));
                alert.addButton(withTitle: NSLocalizedString("Decline", comment: "Button"));
                alert.beginSheetModal(for: window, completionHandler: { response in
                    if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                        guard let controller = NSStoryboard(name: "MIX", bundle: nil).instantiateController(withIdentifier: "EnterChannelViewController") as? EnterChannelViewController else {
                            return;
                        }
                        
                        _ = controller.view;
                        controller.suggestedNickname = nil;
                        controller.account = invitation.account;
                        controller.channelJid = mucInvitation.roomJid;
                        controller.channelName = nil;
                        controller.componentType = .muc;
                        controller.password = mucInvitation.password;
                        controller.isPasswordVisible = mucInvitation.password == nil;
                        
                        let windowController = NSWindowController(window: NSWindow(contentViewController: controller));
                        window.beginSheet(windowController.window!, completionHandler: { result in
                            switch result {
                            case .OK:
                                self.remove(invitation: invitation);
                            default:
                                break;
                            }
                        });
                    } else {
                        mucModule.decline(invitation: mucInvitation, reason: nil);
                        self.remove(invitation: invitation);
                    }
                })
            case .presenceSubscription:
                NotificationCenter.default.post(name: InvitationManager.INVITATION_CLICKED, object: invitation);
            }
        }
    }
    
    func remove(invitation: InvitationItem) {
        queue.async {
            guard self.peristentItems.remove(invitation) != nil || self.volatileItems.remove(invitation) != nil else {
                return;
            }
            self.removed(invitations: [invitation]);
        }
    }
    
    func remove(invitations: [InvitationItem]) {
        queue.async {
            let toRemove = invitations.filter({ self.peristentItems.contains($0) || self.volatileItems.contains($0) });
            guard !toRemove.isEmpty else {
                return;
            }
            
            let toRemoveSet = Set(toRemove);
            
            self.peristentItems = self.peristentItems.filter({ !toRemoveSet.contains($0) });
            self.volatileItems = self.volatileItems.filter({ !toRemoveSet.contains($0) });
            self.removed(invitations: toRemove);
        }
    }
 
    func removeAll(fromServers: [String], on account: BareJID) {
        let domains = Set(fromServers);
        queue.async {
            let persistentToRemove = self.peristentItems.filter({ $0.account == account && domains.contains($0.jid.domain) });
            self.peristentItems = self.peristentItems.filter({ !persistentToRemove.contains($0) });
            let volatileToRemove = self.volatileItems.filter({ $0.account == account && domains.contains($0.jid.domain) });
            self.volatileItems = self.volatileItems.filter({ !volatileToRemove.contains($0) });
            self.removed(invitations: Array(persistentToRemove) + Array(volatileToRemove));
        }
    }
    
    private func addded(invitations: [InvitationItem]) {
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
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: invites.map({ $0.id }));
    }
    
    private func deliverPresenceSubscriptionNotification(invitation: InvitationItem) {
        let rosterItem = DBRosterStore.instance.item(for: invitation.account, jid: invitation.jid);
        let content = UNMutableNotificationContent();
        content.title = NSLocalizedString("Authorization request", comment: "alert window title");
        content.body = String.localizedStringWithFormat(NSLocalizedString("%@ requests authorization to access information about you presence", comment: "alert window message"), rosterItem?.name ?? invitation.jid.description);
        content.sound = UNNotificationSound.default;
        content.userInfo = ["account": invitation.account.description, "jid": invitation.jid.description, "id": "presence-subscription-request"];
        let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
    }
    
    private func deliverMucInvitationNotification(invitation: InvitationItem) {
        let mucInvitation = invitation.object as! MucModule.Invitation;
        let content = UNMutableNotificationContent();
        content.title = NSLocalizedString("Invitation to groupchat", comment: "alert window title");
        content.body = String.localizedStringWithFormat(NSLocalizedString("You (%@) were invited to the groupchat %@", comment: "alert window message"), invitation.account.description, mucInvitation.roomJid.description);
        content.sound = UNNotificationSound.default;
        content.userInfo = ["account": invitation.account.description, "jid": invitation.jid.description, "id": "presence-subscription-request"];
        let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
    }
}
