//
// ChangePasswordController.swift
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
import TigaseSwift

class ChangePasswordController: NSViewController, NSTextFieldDelegate, AccountAware {
    
    var account: BareJID?;
    
    @IBOutlet var message: NSTextField!;

    @IBOutlet var newPassword: NSSecureTextField!;
    @IBOutlet var newPasswordConfirm: NSSecureTextField?;
    
    @IBOutlet var changeOnServer: NSButton?;
    
    @IBOutlet var changeButton: NSButton!;
    
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    override func viewWillAppear() {
        self.changeButton.isEnabled = false;
        self.message.stringValue = String.localizedStringWithFormat(NSLocalizedString("To change password for account %$ please fill out this form:", comment: "settings"), self.account?.stringValue ?? "");
        if let account = self.account {
            let connected = (XmppService.instance.getClient(for: account)?.state ?? .disconnected()) == .connected();
            if connected {
                changeOnServer?.isEnabled = connected;
                changeOnServer?.state = .on;
            } else {
                changeOnServer?.removeFromSuperview();
                newPasswordConfirm?.removeFromSuperview();
                changeOnServer = nil;
                newPasswordConfirm = nil;
                newPassword.bottomAnchor.constraint(equalTo: changeButton.topAnchor, constant: -8).isActive = true;
            }
        } else {
            changeOnServer?.isEnabled = false;
            changeOnServer?.state = .off;
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        changeButton.isEnabled = (!self.newPassword.stringValue.isEmpty) && (self.newPasswordConfirm == nil || (self.newPassword.stringValue == self.newPasswordConfirm?.stringValue));
    }
    
    @IBAction func closeClicked(_ sender: NSButton) {
        close();
    }
    
    @IBAction func changeClicked(_ sender: NSButton) {
        guard let account = self.account else {
            return;
        }
        let password = newPassword.stringValue;
        guard !password.isEmpty && (newPasswordConfirm == nil || password == newPasswordConfirm?.stringValue) else {
            return;
        }
        
        if self.changeOnServer?.state == .on {
            guard let client = XmppService.instance.getClient(for: account) else {
                return;
            }
            progressIndicator.startAnimation(self);
            
            client.module(.inBandRegistration).changePassword(newPassword: password, completionHandler: { result in
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(self);
                    switch result {
                    case .success(let newPassword):
                        self.changePassword(for: account, newPassword: newPassword);
                    case .failure(let err):
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.messageText = NSLocalizedString("Password change failed", comment: "settings");
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Server returned following error: %$", comment: "settings"), err.message ?? err.description);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"))
                        alert.beginSheetModal(for: self.view.window!, completionHandler: { (modalResp) in
                            self.close();
                        });
                    }
                }
            });
        } else {
            changePassword(for: account, newPassword: password);
        }
    }
    
    fileprivate func changePassword(for account: BareJID, newPassword: String) {
        guard var acc = AccountManager.getAccount(for: account) else {
            return;
        }

        acc.password = newPassword;
        do {
            try AccountManager.save(account: acc);

            if self.changeOnServer?.state == .on {
                let alert = NSAlert();
                alert.icon = NSImage(named: NSImage.infoName);
                alert.messageText = NSLocalizedString("Password changed", comment: "settings");
                alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                alert.beginSheetModal(for: self.view.window!, completionHandler: { (modalResp) in
                    self.close();
                });
            } else {
                self.close();
            }
        } catch {
            let alert = NSAlert(error: error);
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
        }

    }
    
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
}
