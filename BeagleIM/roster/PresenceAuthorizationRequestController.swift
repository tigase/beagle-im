//
// PresenceAuthorizationRequestController.swift
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

import AppKit
import Martin

class PresenceAuthorizationRequestController: NSViewController {

    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var nameField: NSTextField!;
    @IBOutlet var jidField: NSTextField!;
    @IBOutlet var descriptionField: NSTextField!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var blockingPullDownButton: NSPopUpButton!;
    
    var invitation: InvitationItem!;
    
    var account: BareJID! {
        self.invitation.account;
    }
    var jid: JID! {
        self.invitation.jid;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        nameField.stringValue = jid.stringValue;
        jidField.stringValue = jid.stringValue;
        jidField.isHidden = true;
        descriptionField.stringValue = String.localizedStringWithFormat(NSLocalizedString("Do you want to allow access to your online status and associated data for account %@?", comment: "confirm to allow access to your presence information"), jid.stringValue)
        refreshVCard();
        
        let blockingModule: BlockingCommandModule? = XmppService.instance.getClient(for: account)?.module(.blockingCommand);
        blockingPullDownButton.isHidden = !(blockingModule?.isAvailable ?? false);
        blockingPullDownButton.menu?.item(at: 0)?.isEnabled = true;
        blockingPullDownButton.menu?.item(at: 1)?.isEnabled = true;
        blockingPullDownButton.menu?.item(at: 2)?.isEnabled = blockingModule?.isReportingSupported ?? false;
        blockingPullDownButton.menu?.item(at: 3)?.isEnabled = blockingModule?.isReportingSupported ?? false;
        blockingPullDownButton.menu?.item(at: 4)?.isEnabled = true;
    }
    
    @IBAction func allowClicked(_ sender: Any) {
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.module(.presence) else {
            return;
        }
            
        presenceModule.subscribed(by: jid);
        presenceModule.subscribe(to: jid);
        
        InvitationManager.instance.remove(invitation: invitation);
    }
    
    @IBAction func denyClicked(_ sender: Any) {
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.module(.presence) else {
            return;
        }
        
        presenceModule.unsubscribed(by: jid);
        InvitationManager.instance.remove(invitation: invitation);
    }
    
    @IBAction func blockClicked(_ sender: Any) {
        denyAndBlock(report: nil);
    }
    
    @IBAction func reportSpam(_ sender: Any) {
        denyAndBlock(report: .init(cause: .spam));
    }
    
    @IBAction func reportAbuse(_ sender: Any) {
        denyAndBlock(report: .init(cause: .abuse));
    }
    
    @IBAction func blockServer(_ sender: Any) {
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }
        
        client.module(.presence).unsubscribed(by: jid);

        InvitationManager.instance.remove(invitation: invitation);
        client.module(.blockingCommand).block(jids: [JID(jid.domain)], completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // everything went ok!
                    InvitationManager.instance.removeAll(fromServers: [self.invitation.jid.domain], on: self.invitation.account);
                    let chatsToClose = DBChatStore.instance.chats(for: client).filter({ $0.jid.domain == self.invitation.jid.domain });
                    for toClose in chatsToClose {
                        _  = DBChatStore.instance.close(chat: toClose);
                    }
                    break;
                case .failure(let err):
                    let alert = Alert();
                    alert.messageText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to block %@", comment: "alert window title"), self.jid.domain);
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "alert window message"), err.localizedDescription);
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.run(completionHandler: { res in
                        // do we have anything to do here?
                    });
                    break;
                }
            }
        });
    }
    
    private func denyAndBlock(report: BlockingCommandModule.Report?) {
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }
        
        client.module(.presence).unsubscribed(by: jid);

        InvitationManager.instance.remove(invitation: invitation);
        client.module(.blockingCommand).block(jid: jid.withoutResource, report: report, completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // everything went ok!
                    if let chat = DBChatStore.instance.chat(for: client, with: self.jid.bareJid) {
                        _ = DBChatStore.instance.close(chat: chat);
                    }
                    break;
                case .failure(let err):
                    let alert = Alert();
                    alert.messageText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to block %@", comment: "alert window title"), self.jid.stringValue);
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "alert window message"), err.localizedDescription);
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.run(completionHandler: { res in
                        // do we have anything to do here?
                    });
                    break;
                }
            }
        });
    }
    
    @IBAction func refreshClicked(_ sender: Any) {
        self.refreshVCard();
    }
    
    func refreshVCard() {
        progressIndicator.startAnimation(self);
        VCardManager.instance.retrieveVCard(for: jid.bareJid, on: account, completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let vcard):
                    let displayName = vcard.displayName;
                    self.avatarView.name = displayName;
                    if let photo = vcard.photos.first, let dataStr = photo.binval, let data = Data(base64Encoded: dataStr), let image = NSImage(data: data) {
                        self.avatarView.image = image;
                    }
                    self.nameField.stringValue = displayName ?? self.jid.stringValue;
                    self.jidField.isHidden = displayName == nil;
                default:
                    break;
                }
                self.progressIndicator.stopAnimation(self);
            }
        })
    }
}

extension VCard {
    var displayName: String? {
        if let fn = self.fn, !fn.isEmpty {
            return fn;
        }
        if let givenName = self.givenName, !givenName.isEmpty {
            if let surname = self.surname {
                return "\(givenName) \(surname)";
            }
            return givenName;
        }
        if let nick = self.nicknames.first {
            return nick;
        }
        return nil;
    }
}
