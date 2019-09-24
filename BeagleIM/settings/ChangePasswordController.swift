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

class ChangePasswordController: NSViewController, NSTextFieldDelegate {
    
    var account: BareJID?;
    
    @IBOutlet var message: NSTextField!;

    @IBOutlet var newPassword: NSSecureTextField!;
    @IBOutlet var newPasswordConfirm: NSSecureTextField!;
    
    @IBOutlet var changeOnServer: NSButton!;
    
    @IBOutlet var changeButton: NSButton!;
    
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    override func viewWillAppear() {
        self.changeButton.isEnabled = false;
        self.message.stringValue = "To change password for account \(self.account?.stringValue ?? "") please fill out this form:";
        if let account = self.account {
            let connected = (XmppService.instance.getClient(for: account)?.state ?? .disconnected) == .connected;
            changeOnServer.isEnabled = connected;
            changeOnServer.state = connected ? .on : .off;
        } else {
            changeOnServer.isEnabled = false;
            changeOnServer.state = .off;
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        changeButton.isEnabled = (!self.newPassword.stringValue.isEmpty) && self.newPassword.stringValue == self.newPasswordConfirm.stringValue;
    }
    
    @IBAction func closeClicked(_ sender: NSButton) {
        close();
    }
    
    @IBAction func changeClicked(_ sender: NSButton) {
        guard let account = self.account else {
            return;
        }
        let password = newPassword.stringValue;
        guard !password.isEmpty && password == newPasswordConfirm.stringValue else {
            return;
        }
        
        if self.changeOnServer.state == .on {
            guard let client = XmppService.instance.getClient(for: account), let register: InBandRegistrationModule = client.modulesManager.getModule(InBandRegistrationModule.ID) else {
                return;
            }
            progressIndicator.startAnimation(self);
            
            register.changePassword(newPassword: password, completionHandler: { result in
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(self);
                    switch result {
                    case .success(let newPassword):
                        print("password changed!");
                        self.changePassword(for: account, newPassword: newPassword);
                    case .failure(let err):
                        print("password change failed: \(err)");
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.messageText = "Password change failed";
                        alert.informativeText = "Server returned following error: \(err.rawValue)";
                        alert.addButton(withTitle: "OK")
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
        guard let acc = AccountManager.getAccount(for: account) else {
            return;
        }
        acc.password = newPassword;
        _ = AccountManager.save(account: acc);
        let alert = NSAlert();
        alert.icon = NSImage(named: NSImage.infoName);
        alert.messageText = "Password changed";
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: self.view.window!, completionHandler: { (modalResp) in
            self.close();
        });
    }
    
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
}
