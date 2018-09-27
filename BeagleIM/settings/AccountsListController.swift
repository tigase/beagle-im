//
//  AccountsListController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 05.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class AccountsListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet var tableView: NSTableView?;
    @IBOutlet var defaultAccountField: NSPopUpButton!;
    
    var tabViewController: NSTabViewController? {
        return self.children.last as? NSTabViewController;
    }
    
    var accounts: [BareJID] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: AccountManager.ACCOUNT_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.refreshAccounts();
    }
    
    func refreshAccounts() {
        accounts = AccountManager.getAccounts();
        defaultAccountField.removeAllItems();
        accounts.forEach { jid in
            defaultAccountField.addItem(withTitle: jid.stringValue);
        }
        defaultAccountField.title = Settings.defaultAccount.bareJid()?.stringValue ?? "";
        defaultAccountField.selectItem(withTitle: Settings.defaultAccount.bareJid()?.stringValue ?? "");
        self.tableView?.reloadData();
        self.tableView?.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false);
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return accounts.count;
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return accounts[row];
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("AccountCellView"), owner: self) as! AccountCellView;
        view.label?.textColor = tableView.isRowSelected(row) ? NSColor.selectedTextColor : NSColor.textColor;
        view.label?.stringValue = accounts[row].stringValue;
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (tableView?.selectedRow ?? -1) >= 0 else {
            return;
        }
        let account = accounts[tableView!.selectedRow];
        if let detailsView = tabViewController?.tabViewItems[0].view as? AccountDetailsView {
            detailsView.account = account;
        }
    }
    
    @IBAction func defaultAccountChanged(_ sender: NSPopUpButton) {
        DispatchQueue.main.async {
            Settings.defaultAccount.set(bareJid: BareJID(sender.titleOfSelectedItem ?? ""));
            self.defaultAccountField.title = Settings.defaultAccount.bareJid()?.stringValue ?? "";
        }
    }
    
    @objc func accountChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            let selectedRow = self.tableView?.selectedRow;
            self.refreshAccounts();
            if selectedRow != nil {
                self.tableView?.selectRowIndexes(IndexSet(integer: selectedRow!), byExtendingSelection: false);
            }
        }
    }
    
    @IBAction func actionButtonCliecked(_ sender: NSSegmentedCell) {
        switch sender.selectedSegment {
        case 0:
            // add account
            let addAccountController = self.storyboard!.instantiateController(withIdentifier: "AddAccountController") as! NSViewController;
            let window = NSWindow(contentViewController: addAccountController);
            self.view.window!.beginSheet(window, completionHandler: nil);
            break;
        case 1:
            // remove account
            let selectedRow = tableView!.selectedRow
            guard selectedRow >= 0 && selectedRow < self.accounts.count else {
                return;
            }
            if let account = AccountManager.getAccount(for: accounts[selectedRow]) {
                _ = AccountManager.delete(account: account);
            }
            
            break;
        default:
            break;
        }
    }
    
}

class AccountCellView: NSTableCellView {
    
    @IBOutlet weak var avatar: AvatarView?;
    @IBOutlet weak var label: NSTextField?;
    
}

class AccountDetailsView: NSView {
    
    var account: BareJID? {
        didSet {
            username?.stringValue = account!.stringValue;
            let acc = AccountManager.getAccount(for: account!);
            password?.stringValue = acc?.password ?? "";
            nickname?.stringValue = acc?.nickname ?? "";
            active?.state = (acc?.active ?? false) ? .on : .off;
        }
    }
    
    @IBOutlet weak var username: NSTextField?;
    @IBOutlet weak var password: NSSecureTextField?;
    @IBOutlet weak var nickname: NSTextField?;
    @IBOutlet weak var active: NSButton?;
    
    @IBAction func passwordChanged(_ sender: NSSecureTextFieldCell) {
        let account = AccountManager.getAccount(for: self.account!)!;
        account.password = sender.stringValue;
        _ = AccountManager.save(account: account);
    }

    @IBAction func nicknameChanged(_ sender: NSTextField) {
        let account = AccountManager.getAccount(for: self.account!)!;
        account.nickname = sender.stringValue;
        _ = AccountManager.save(account: account);
    }
    
    @IBAction func activeStateChanged(_ sender: NSButton) {
        let account = AccountManager.getAccount(for: self.account!)!;
        account.active = sender.state == .on;
        _ = AccountManager.save(account: account);
    }
    
}
