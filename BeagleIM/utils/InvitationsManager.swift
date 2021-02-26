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
    let dispatcher = QueueDispatcher(label: "InvitationManagerQueue");
    
    public let itemsPublisher: PassthroughSubject<Set<InvitationItem>, Never> = PassthroughSubject();

    private var order: Int = 1;
    
    init() {
        XmppService.instance.$connectedClients.receive(on: dispatcher.queue).map({ $0.map({ $0.userBareJid }) }).sink(receiveValue: { accounts in
            self.volatileItems = self.volatileItems.filter({ accounts.contains($0.account) });
        }).store(in: &cancellables);
        XmppService.instance.$connectedClients.receive(on: dispatcher.queue).map({ $0.map({ $0.userBareJid })}).combineLatest($peristentItems, { accounts, invites in
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
    
    func addPresenceSubscribe(for account: BareJID, from jid: JID) {
        dispatcher.async {
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
        dispatcher.async {
            let invitation = InvitationItem(type: .mucInvitation, account: account, jid: jid, object: mucInvitation, order:  self.nextOrder());
            guard !self.peristentItems.contains(invitation) else {
                return;
            }
            self.peristentItems.insert(invitation);
            
            self.addded(invitations: [invitation]);
        }
    }
    
    func mucJoined(on account: BareJID, roomJid: BareJID) {
        dispatcher.async {
            let tmp = InvitationItem(type: .mucInvitation, account: account, jid: JID(roomJid), object: nil, order:  self.nextOrder());
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
                guard let mucModule = XmppService.instance.getClient(for: invitation.account)?.module(.muc) else {
                    return;
                }

                let mucInvitation = invitation.object as! MucModule.Invitation;
                let alert = NSAlert();
                alert.messageText = "Invitation to groupchat";
                if let inviter = mucInvitation.inviter {
                    let name = XmppService.instance.clients.values.compactMap({ (client) -> String? in
                        if let n = DBRosterStore.instance.item(for: client, jid: inviter)?.name {
                            return "\(n) (\(inviter))";
                        } else {
                            return nil;
                        }
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
                        mucModule.join(roomName: roomName, mucServer: mucInvitation.roomJid.domain, nickname: nickname, password: mucInvitation.password).handle({ result in
                            switch result {
                            case .failure(let error):
                                guard let context = mucModule.context, let room = DBChatStore.instance.room(for: context, with: mucInvitation.roomJid) else {
                                    return;
                                }
                                MucEventHandler.showJoinError(error, for: room);
                            case .success(_):
                                PEPBookmarksModule.updateOrAdd(for: invitation.account, bookmark: Bookmarks.Conference(name: roomName, jid: JID(BareJID(localPart: roomName, domain: mucInvitation.roomJid.domain)), autojoin: true, nick: nickname, password: mucInvitation.password));
                            }
                            self.remove(invitation: invitation);
                        });
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
        content.title = "Authorization request";
        content.body = "\(rosterItem?.name ?? invitation.jid.stringValue) requests authorization to access information about you presence";
        content.sound = UNNotificationSound.default;
        content.userInfo = ["account": invitation.account.stringValue, "jid": invitation.jid.stringValue, "id": "presence-subscription-request"];
        let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
    }
    
    private func deliverMucInvitationNotification(invitation: InvitationItem) {
        let mucInvitation = invitation.object as! MucModule.Invitation;
        let content = UNMutableNotificationContent();
        content.title = "Invitation to groupchat";
        content.body = "You (\(invitation.account)) were invited to the groupchat \(mucInvitation.roomJid)";
        content.sound = UNNotificationSound.default;
        content.userInfo = ["account": invitation.account.stringValue, "jid": invitation.jid.stringValue, "id": "presence-subscription-request"];
        let request = UNNotificationRequest(identifier: invitation.id, content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil);
    }
}
