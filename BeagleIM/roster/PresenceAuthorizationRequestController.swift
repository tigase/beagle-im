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
import TigaseSwift

class PresenceAuthorizationRequestController: NSViewController {

    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var nameField: NSTextField!;
    @IBOutlet var jidField: NSTextField!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var blockButton: NSButton!;
    
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
        refreshVCard();
        
        let blockingModule: BlockingCommandModule? = XmppService.instance.getClient(for: account)?.modulesManager.getModule(BlockingCommandModule.ID);
        blockButton.isHidden = !(blockingModule?.isAvailable ?? false);
    }
    
    @IBAction func allowClicked(_ sender: Any) {
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID) else {
            return;
        }
            
        presenceModule.subscribed(by: jid);
            
        if Settings.requestPresenceSubscription.bool() {
            presenceModule.subscribe(to: jid);
        }
        InvitationManager.instance.remove(invitation: invitation);
    }
    
    @IBAction func denyClicked(_ sender: Any) {
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID) else {
            return;
        }
        
        presenceModule.unsubscribed(by: jid);
        InvitationManager.instance.remove(invitation: invitation);
    }
    
    @IBAction func blockClicked(_ sender: Any) {
        guard let blockingModule: BlockingCommandModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(BlockingCommandModule.ID) else {
            return;
        }
        if let presenceModule: PresenceModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID) {
            presenceModule.unsubscribed(by: jid);
        }

        InvitationManager.instance.remove(invitation: invitation);
        blockingModule.block(jids: [jid.withoutResource], completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    // everything went ok!
                    break;
                case .failure(let err):
                    let alert = Alert();
                    alert.messageText = "It was not possible to block \(self.jid.stringValue)";
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
