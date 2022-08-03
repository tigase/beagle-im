//
// JoinGroupchatViewController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class JoinGroupchatViewController: NSViewController, NSTextFieldDelegate {
    
    static func open(on window: NSWindow, account: BareJID, roomJid: BareJID, isPasswordRequired: Bool) {
        guard let windowController = NSStoryboard(name: "ServiceDiscovery", bundle: nil).instantiateController(withIdentifier: "JoinGroupchatWindowController") as? NSWindowController, let viewController = windowController.contentViewController as? JoinGroupchatViewController else {
            return;
        }
        
        viewController.account = account;
        viewController.roomJid = roomJid;
        viewController.isPasswordRequired = isPasswordRequired;
        
        window.beginSheet(windowController.window!, completionHandler: nil);
    }
    
    @IBOutlet var infoLabel: NSTextField!;
    @IBOutlet var nicknameField: NSTextField!;
    @IBOutlet var passwordField: NSSecureTextField!;
    @IBOutlet var joinButton: NSButton!;

    @IBOutlet var passwordFieldHeightConstraint: NSLayoutConstraint!;
    @IBOutlet var nicknamePasswordFieldsSpaceConstraint: NSLayoutConstraint!;
    var noPasswordConstraint: NSLayoutConstraint?;
    
    var account: BareJID?;
    var roomJid: BareJID?;
    var isPasswordRequired: Bool = false;
    
    override func viewWillAppear() {
        let passwordPart = self.isPasswordRequired ? (" " + NSLocalizedString("and password", comment: "join groupchat part")) : "";
        self.infoLabel.stringValue = String.localizedStringWithFormat(NSLocalizedString("Please enter nickname %@ to enter to join groupchat at %@.", comment: "join groupchat info label"), passwordPart, roomJid!.stringValue);
        
        nicknameField.stringValue = AccountManager.getAccount(for: self.account!)?.nickname ?? "";
        passwordField.isHidden = !isPasswordRequired;
        
        if !isPasswordRequired {
            self.passwordFieldHeightConstraint.isActive = false;
            self.nicknamePasswordFieldsSpaceConstraint.isActive = false;
            if noPasswordConstraint == nil {
                self.noPasswordConstraint = joinButton.topAnchor.constraint(equalTo: self.nicknameField.bottomAnchor, constant: nicknamePasswordFieldsSpaceConstraint.constant);
            }
            noPasswordConstraint?.isActive = true;
        } else {
            noPasswordConstraint?.isActive = false;
            self.passwordFieldHeightConstraint.isActive = true;
            self.nicknamePasswordFieldsSpaceConstraint.isActive = true;
        }
        
        joinButton.isEnabled = !self.nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
    }
    
    func controlTextDidChange(_ obj: Notification) {
        joinButton.isEnabled = !self.nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.close();
    }
    
    @IBAction func joinClicked(_ sender: NSButton) {
        let nickname = nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        guard !nickname.isEmpty, let roomName = self.roomJid?.localPart, let mucServer = self.roomJid?.domain else {
            return;
        }
        
        guard let mucModule = XmppService.instance.getClient(for: self.account!)?.module(.muc) else {
            return;
        }
        
        _ = mucModule.join(roomName: roomName, mucServer: mucServer, nickname: nickname, password: isPasswordRequired ? self.passwordField.stringValue : nil);
        
        self.close();
    }
    
    fileprivate func close() {
        self.view.window?.close();
    }
}
