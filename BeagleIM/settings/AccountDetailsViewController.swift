//
//  AccountDetailsViewController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 04/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
        }
    }
    
    @IBOutlet weak var username: NSTextField!;
    @IBOutlet weak var password: NSSecureTextField!;
    @IBOutlet weak var nickname: NSTextField!;
    @IBOutlet weak var active: NSButton!;
    
    @IBAction func passwordChanged(_ sender: NSSecureTextFieldCell) {
        save();
    }
    
    @IBAction func nicknameChanged(_ sender: NSTextField) {
        save();
    }
    
    @IBAction func activeStateChanged(_ sender: NSButton) {
        save();
    }

    func save() {
        let account = AccountManager.getAccount(for: self.account!)!;
        account.password = password.stringValue;
        account.nickname = nickname.stringValue;
        account.active = active.state == .on;
        _ = AccountManager.save(account: account);
    }
}
