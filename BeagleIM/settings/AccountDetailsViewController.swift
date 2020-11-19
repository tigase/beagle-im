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
    
    var account: BareJID?;
    
    @IBOutlet var changePasswordButton: NSButton!;
    @IBOutlet weak var username: NSTextField!;
    @IBOutlet weak var nickname: NSTextField!;
    @IBOutlet weak var active: NSButton!;
    @IBOutlet weak var resourceType: NSPopUpButton!;
    @IBOutlet weak var resourceName: NSTextField!;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.refresh();
    }
    
    func refresh() {
        username?.stringValue = account?.stringValue ?? "";
        let acc = account == nil ? nil : AccountManager.getAccount(for: account!);
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
        active.isEnabled = account != nil;
        changePasswordButton.isEnabled = account != nil;
        nickname.isEnabled = account != nil;
        resourceName.isEnabled = resourceType.indexOfSelectedItem == 3;
    }
        
    @IBAction func resourceTypeChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem;
        resourceName.isEnabled = idx == 3;
        sender.title = resourceType.titleOfSelectedItem ?? "";
        sender.itemArray.forEach { (item) in
            item.state = .off;
        }
        sender.selectedItem?.state = .on;
    }

    @IBAction func cancel(_ sender: NSButton) {
        self.dismiss(self);
    }
    
    @IBAction func save(_ sender: NSButton) {
        guard let jid = self.account, var account = AccountManager.getAccount(for: jid) else {
            // do not save if we cannot find the account
            return;
        }
        account.nickname = nickname.stringValue;
        account.active = active.state == .on;
        let idx = resourceType.indexOfSelectedItem;
        account.resourceType = idx == 1 ? .automatic : (idx == 2 ? .hostname : .custom);
        account.resourceName = resourceName.stringValue;
        _ = AccountManager.save(account: account);
        self.dismiss(self);
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "ChangeAccountPassword" {
            if let changeAccountController = segue.destinationController as? ChangePasswordController {
                changeAccountController.account = self.account;
            }
        }
    }
}
