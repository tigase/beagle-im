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
import Martin

class AccountDetailsViewController: NSViewController, AccountAware, NSTextFieldDelegate {
    
    var account: BareJID?;
    
    @IBOutlet var changePasswordButton: NSButton!;
    @IBOutlet weak var username: NSTextField!;
    @IBOutlet weak var nickname: NSTextField!;
    @IBOutlet weak var active: NSButton!;
    @IBOutlet weak var resourceType: NSPopUpButton!;
    @IBOutlet weak var resourceName: NSTextField!;
    @IBOutlet var host: NSTextField!;
    @IBOutlet var port: NSTextField!;
    @IBOutlet var useDirectTLS: NSButton!;
    @IBOutlet var disableTLS13: NSButton!;
    
    @IBOutlet var advGrid: NSGridView!;
    @IBOutlet var disclosureButton: NSButton!;
    @IBOutlet var showDisclosure: NSLayoutConstraint!;
    
    @IBOutlet var saveButton: NSButton!;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.refresh();
        
        port.formatter = PortValueFormatter();
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        showDisclosure(false);
        refreshControlStates();
    }
    
    func controlTextDidChange(_ obj: Notification) {
        refreshControlStates();
    }
    
    func refreshControlStates() {
        let hasCredentials = !username.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
        let canConnect = host.stringValue.isEmpty == port.stringValue.isEmpty;
        saveButton.isEnabled = hasCredentials && canConnect;
        useDirectTLS.isEnabled = !(port.stringValue.isEmpty || host.stringValue.isEmpty);
    }
    
    @IBAction func switchDisclosure(_ sender: Any) {
        showDisclosure(disclosureButton.state == .on);
    }
    
    func showDisclosure(_ value: Bool) {
        disclosureButton.state = value ? .on : .off;
        advGrid.isHidden = !value;
        if value {
            NSLayoutConstraint.activate([showDisclosure]);
        } else {
            NSLayoutConstraint.deactivate([showDisclosure]);
        }
    }
    
    func refresh() {
        username?.stringValue = account?.description ?? "";
        let acc = account == nil ? nil : AccountManager.account(for: account!);
        nickname?.stringValue = acc?.nickname ?? "";
        active?.state = (acc?.enabled ?? false) ? .on : .off;
        resourceType?.itemArray.forEach { (item) in
            item.state = .off;
        }
        if let rt = acc?.additional.resourceType {
            switch rt {
            case .automatic:
                resourceType?.selectItem(at: 1);
                resourceName?.stringValue = "BeagleIM";
            case .hostname:
                resourceType?.selectItem(at: 2);
                resourceName?.stringValue = "BeagleIM";
            case .manual(let resource):
                resourceType?.selectItem(at: 3);
                resourceName?.stringValue = resource;
            }
        } else {
            resourceType?.selectItem(at: 1);
        }
        resourceType?.selectedItem?.state = .on;
        resourceType?.title = resourceType?.titleOfSelectedItem ?? "";
        active.isEnabled = account != nil;
        changePasswordButton.isEnabled = account != nil;
        nickname.isEnabled = account != nil;
        resourceName.isEnabled = resourceType.indexOfSelectedItem == 3;
        
        host.stringValue = acc?.serverEndpoint?.host ?? "";
        if let portInt = acc?.serverEndpoint?.port {
            port.stringValue = String(portInt);
        } else {
            port.stringValue = "";
        }
        useDirectTLS.state = (acc?.serverEndpoint?.proto == .XMPPS) ? .on : .off;
        disableTLS13.state = (acc?.disableTLS13 ?? false) ? .on : .off;
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
        guard let jid = self.account else {
            // do not save if we cannot find the account
            return;
        }

        do {
            try AccountManager.modifyAccount(for: jid, { account in
                account.nickname = self.nickname.stringValue;
                account.enabled = self.active.state == .on;
                let idx = self.resourceType.indexOfSelectedItem;
                switch idx {
                case 2:
                    account.additional.resourceType = .hostname;
                case 3:
                    account.additional.resourceType = .manual(self.resourceName.stringValue.isEmpty ? "BeagleIM" : self.resourceName.stringValue);
                default:
                    account.additional.resourceType = .automatic;
                }
                
                if !(self.host.stringValue.isEmpty || self.port.stringValue.isEmpty), let portInt = Int(self.port.stringValue) {
                    account.serverEndpoint = .init(proto: self.useDirectTLS.state == .on ? .XMPPS : .XMPP, host: self.host.stringValue, port: portInt)
                }
                account.disableTLS13 = self.disableTLS13.state == .on;
                
            })
            dismiss(self);
        } catch {
            let alert = NSAlert(error: error);
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "ChangeAccountPassword" {
            if let changeAccountController = segue.destinationController as? ChangePasswordController {
                changeAccountController.account = self.account;
            }
        }
    }
    
    class Settings {
        var host: String?;
        var port: Int?;
        var useDirectTLS: Bool = false;
        var disableTLS13: Bool = false;
    }
}
