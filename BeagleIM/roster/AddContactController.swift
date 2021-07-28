//
// AddContactController.swift
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

class AddContactController: NSViewController, NSTextFieldDelegate {
    
    var accountSelector: NSPopUpButton!;
    var jidField: NSTextField!;
    var labelField: NSTextField!;
    var requestSubscriptionButton: NSButton!;
    var allowSubscriptionButton: NSButton!;
    var preauthToken: String?;
    
    @IBOutlet var imageView: NSImageView!;
    @IBOutlet var addButton: NSButton!;
    @IBOutlet var formView: FormView!;
    @IBOutlet var disclosureView: FormView!;
    @IBOutlet var disclosureButton: NSButton!;
    
    var disclosureConstraint: NSLayoutConstraint!;
    var formViewHeightConstraint: NSLayoutConstraint?;
    var windowHeightConstraint: NSLayoutConstraint?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        UserDefaults.standard.set(false, forKey: "NSConstraintBasedLayoutVisualizeMutuallyExclusiveConstraints")
        
        addButton.isEnabled = false;
        
        accountSelector = NSPopUpButton(title: NSLocalizedString("Select account", comment: "add roster item label"), target: self, action: #selector(accountSelectionChanged));
        accountSelector.menu = NSMenu(title: NSLocalizedString("Select account", comment: "add roster item label"));
        accountSelector.setContentHuggingPriority(.defaultLow, for: .horizontal);
        accountSelector.setContentHuggingPriority(.defaultHigh, for: .vertical);
        print("hugging:", accountSelector.contentHuggingPriority(for: .horizontal).rawValue);
        AccountManager.getAccounts().filter { account -> Bool in
            return XmppService.instance.getClient(for: account)?.state ?? .disconnected() == .connected()
            }.forEach { account in
            accountSelector.menu?.addItem(NSMenuItem(title: account.stringValue, action: nil, keyEquivalent: ""));
        }
        _ = formView.addRow(label: NSLocalizedString("Add to", comment: "add roster item label") + ":", field: accountSelector);
        formView.groupItems(from: accountSelector, to: accountSelector);
        
        jidField = formView.addRow(label: NSLocalizedString("XMPP JID", comment: "add roster item label") + ":", field: NSTextField(string: ""));
        jidField.setContentHuggingPriority(.defaultLow, for: .vertical);
        jidField.delegate = self;
        labelField = formView.addRow(label: NSLocalizedString("Contact name", comment: "add roster item label") + ":", field: NSTextField(string: ""));
        labelField.setContentHuggingPriority(.defaultLow, for: .vertical);
        //accountSelector.widthAnchor.constraint(equalTo: labelField.widthAnchor, multiplier: 1.0).isActive = true;
        formView.groupItems(from: jidField, to: labelField);
        
        requestSubscriptionButton = disclosureView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Request presence subscription", comment: "add roster item label"), target: nil, action: nil));
        allowSubscriptionButton = disclosureView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Allow presence subscription", comment: "add roster item label"), target: nil, action: nil));
        
        requestSubscriptionButton.state = .on;
        allowSubscriptionButton.state = .on;
        
        disclosureConstraint = disclosureView.heightAnchor.constraint(equalToConstant: 0);
        disclosureConstraint.isActive = true;
        disclosureView.isHidden = true;
        //accountSelector.widthAnchor.constraint(equalTo: requestSubscriptionButton.widthAnchor, multiplier: 1.0).isActive = true;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.verify();
    }
    
    func controlTextDidChange(_ obj: Notification) {
        verify();
    }
    
    @objc func accountSelectionChanged() {
        verify();
    }
    
    func verify() {
        var result = false;
        if accountSelector.selectedItem?.title != nil && !jidField.stringValue.isEmpty {
            result = true;
        }
        addButton.isEnabled = result;
    }
    
    @IBAction func disclosureClicked(_ sender: NSButton) {
        if formViewHeightConstraint == nil {
            formViewHeightConstraint = formView.heightAnchor.constraint(equalToConstant: formView.frame.height);
            formViewHeightConstraint?.isActive = true;
        }
        if windowHeightConstraint == nil {
            windowHeightConstraint = view.heightAnchor.constraint(equalToConstant: view.frame.height);
            windowHeightConstraint?.isActive = true;
        }
        NSAnimationContext.runAnimationGroup({ (context) in
            context.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut);
            context.duration = 0.2;
            self.disclosureView.animator().isHidden = (sender.state == .off);
            self.disclosureConstraint.animator().isActive = (sender.state == .off);
            self.windowHeightConstraint?.animator().isActive = (sender.state == .off);
        }, completionHandler: nil);
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.close();
    }
    
    @IBAction func addClicked(_ sender: NSButton) {
        guard let account = BareJID(accountSelector.selectedItem?.title) else {
            return;
        }
        let jid = JID(jidField.stringValue);
        let name = labelField.stringValue;
        
        let requrestSubscription = requestSubscriptionButton.state == .on;
        let allowSubscription = allowSubscriptionButton.state == .on;
        
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }
        
        client.module(.roster).addItem(jid: jid, name: name.isEmpty ? nil : name, groups: [], completionHandler: { result in
            switch result {
            case .success(_):
                let presenceModule = client.module(.presence);
                if requrestSubscription {
                    presenceModule.subscribe(to: jid, preauth: self.preauthToken);
                }
                if allowSubscription {
                    presenceModule.subscribed(by: jid);
                }
                self.close();
            case .failure(_):
                self.close();
            }
        });
    }
    
    fileprivate func close() {
        DispatchQueue.main.async {
            self.view.window?.sheetParent?.endSheet(self.view.window!);
        }
    }
}
