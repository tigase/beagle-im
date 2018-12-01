//
// AccountsListController.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
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
        view.avatar?.image = AvatarManager.instance.avatar(for: accounts[row], on: accounts[row]);
        view.label?.textColor = tableView.isRowSelected(row) ? NSColor.selectedTextColor : NSColor.textColor;
        view.label?.stringValue = accounts[row].stringValue;
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (tableView?.selectedRow ?? -1) >= 0 else {
            return;
        }
        let account: BareJID = accounts[tableView!.selectedRow];
        tabViewController?.tabViewItems.forEach({ (controller) in
            (controller.viewController as? AccountAware)?.account = account;
        })
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

protocol AccountAware: class {
    
    var account: BareJID? { get set }
    
}
