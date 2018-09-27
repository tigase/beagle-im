//
//  AddAccountController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 05.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class AddAccountController: NSViewController, NSTextFieldDelegate {
    
    @IBOutlet var logInButton: NSButton!;
    @IBOutlet var stackView: NSStackView!
    
    var usernameField: NSTextField!;
    var passwordField: NSSecureTextField!;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        usernameField = addRow(label: "Username", field: NSTextField(string: ""));
        usernameField.placeholderString = "user@domain.com";
        usernameField.delegate = self;
        passwordField = addRow(label: "Password", field: NSSecureTextField(string: ""));
        passwordField.placeholderString = "Required";
        passwordField.delegate = self;
    }
    
    func controlTextDidChange(_ obj: Notification) {
        logInButton.isEnabled = !(usernameField.stringValue.isEmpty || passwordField.stringValue.isEmpty);
    }
    
    @IBAction func cancelClicked(_ button: NSButton) {
        self.view.window?.sheetParent?.endSheet(self.view.window!)
    }
    
    @IBAction func logInClicked(_ button: NSButton) {
        let jid = BareJID(usernameField.stringValue);
        let account = AccountManager.Account(name: jid);
        account.password = passwordField.stringValue;
        _ = AccountManager.save(account: account);
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
    
    func addRow<T: NSView>(label text: String, field: T) -> T {
        let label = createLabel(text: text);
        let row = RowView(views: [label, field]);
        self.stackView.addView(row, in: .bottom);
        return field;
    }
    
    func createLabel(text: String) -> NSTextField {
        let label = NSTextField(string: text);
        label.isEditable = false;
        label.isBordered = false;
        label.drawsBackground = false;
        label.widthAnchor.constraint(equalToConstant: 120).isActive = true;
        label.alignment = .right;
        return label;
    }
    
    class RowView: NSStackView {
    }
}
