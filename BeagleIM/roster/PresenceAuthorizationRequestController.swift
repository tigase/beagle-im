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
        
        nameField.stringValue = jid.description;
        jidField.stringValue = jid.description;
        jidField.isHidden = true;
        refreshVCard();
        
        let blockingModule: BlockingCommandModule? = XmppService.instance.getClient(for: account)?.module(.blockingCommand);
        blockingPullDownButton.isHidden = !(blockingModule?.isAvailable ?? false);
        blockingPullDownButton.menu?.item(at: 0)?.isEnabled = true;
        blockingPullDownButton.menu?.item(at: 1)?.isEnabled = true;
        blockingPullDownButton.menu?.item(at: 2)?.isEnabled = blockingModule?.isReportingSupported ?? false;
        blockingPullDownButton.menu?.item(at: 3)?.isEnabled = blockingModule?.isReportingSupported ?? false;
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
    
    private func denyAndBlock(report: BlockingCommandModule.Report?) {
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }
        
        client.module(.presence).unsubscribed(by: jid);

        InvitationManager.instance.remove(invitation: invitation);
        client.module(.blockingCommand).block(jid: jid.withoutResource(), report: report, completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // everything went ok!
                    break;
                case .failure(let err):
                    let alert = Alert();
                    alert.messageText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to block %@", comment: "alert window title"), self.jid.description);
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
        Task {
            if let vcard = try? await VCardManager.instance.retrieveVCard(for: jid.withoutResource(), on: account) {
                await MainActor.run(body: {
                    let displayName = vcard.displayName;
                    self.avatarView.name = displayName;
                    if let photo = vcard.photos.first, let dataStr = photo.binval, let data = Data(base64Encoded: dataStr), let image = NSImage(data: data) {
                        self.avatarView.image = image;
                    }
                    self.nameField.stringValue = displayName ?? self.jid.description;
                    self.jidField.isHidden = displayName == nil;
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(self);
            })
        }
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
