//
// AccountDetailsViewController.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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

class AccountDetailsViewController: NSViewController, AccountAware {
    
    var account: BareJID? {
        didSet {
            username?.stringValue = account?.stringValue ?? "";
            let acc = account == nil ? nil : AccountManager.getAccount(for: account!);
            password?.stringValue = acc?.password ?? "";
            nickname?.stringValue = acc?.nickname ?? "";
            active?.state = (acc?.active ?? false) ? .on : .off;
            resourceType?.itemArray.forEach { (item) in
                item.state = .off;
            }
            if let rt = acc?.resourceType {
                switch rt {
                case .automatic:
                    resourceType?.selectItem(at: 1);
                case .hostname:
                    resourceType?.selectItem(at: 2);
                case .custom:
                    resourceType?.selectItem(at: 3);
                }
            } else {
                resourceType?.selectItem(at: 1);
            }
            resourceType?.selectedItem?.state = .on;
            resourceType?.title = resourceType?.titleOfSelectedItem ?? "";
            resourceName?.stringValue = acc?.resourceName ?? "BeagleIM";
        }
    }
    
    @IBOutlet weak var username: NSTextField!;
    @IBOutlet weak var password: NSSecureTextField!;
    @IBOutlet weak var nickname: NSTextField!;
    @IBOutlet weak var active: NSButton!;
    @IBOutlet weak var resourceType: NSPopUpButton!;
    @IBOutlet weak var resourceName: NSTextField!;
    
    @IBAction func passwordChanged(_ sender: NSSecureTextFieldCell) {
        save();
    }
    
    @IBAction func nicknameChanged(_ sender: NSTextField) {
        save();
    }
    
    @IBAction func activeStateChanged(_ sender: NSButton) {
        save();
    }
    
    @IBAction func resourceTypeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem;
        resourceName.isEnabled = idx == 3;
        sender.title = resourceType.titleOfSelectedItem ?? "";
        sender.itemArray.forEach { (item) in
            item.state = .off;
        }
        sender.selectedItem?.state = .on;
        save();
    }

    @IBAction func resourceNameChanged(_ sender: NSTextField) {
        save();
    }
    
    func save() {
        guard let jid = self.account, let account = AccountManager.getAccount(for: jid) else {
            // do not save if we cannot find the account
            return;
        }
        account.password = password.stringValue;
        account.nickname = nickname.stringValue;
        account.active = active.state == .on;
        let idx = resourceType.indexOfSelectedItem;
        account.resourceType = idx == 1 ? .automatic : (idx == 2 ? .hostname : .custom);
        account.resourceName = resourceName.stringValue;
        _ = AccountManager.save(account: account);
    }
    
}
