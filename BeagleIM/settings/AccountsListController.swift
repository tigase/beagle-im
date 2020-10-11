//
// AccountsListController.swift
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
        NotificationCenter.default.addObserver(self, selector: #selector(accountStatusChanged), name: XmppService.ACCOUNT_STATUS_CHANGED, object: nil)
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
        DispatchQueue.main.async {
            if self.accounts.isEmpty {
                let addAccountController = self.storyboard!.instantiateController(withIdentifier: "AddAccountController") as! NSViewController;
                self.presentAsSheet(addAccountController);
            }
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return accounts.count;
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return accounts[row];
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("AccountCellView"), owner: self) as! AccountCellView;
        view.avatar?.update(for: accounts[row], on: accounts[row]);
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
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return AccountRowView();
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
    
    @objc func accountStatusChanged(_ notification: Notification) {
        guard let account = notification.object as? BareJID else {
            return;
        }
        DispatchQueue.main.async {
            guard let idx = self.accounts.firstIndex(of: account) else {
                return;
            }
            self.tableView?.reloadData(forRowIndexes: IndexSet(integer: idx), columnIndexes: IndexSet(integer: 0));
        }
    }
    
    @IBAction func actionButtonCliecked(_ sender: NSSegmentedCell) {
        switch sender.selectedSegment {
        case 0:
            // add account
            let addAccountController = self.storyboard!.instantiateController(withIdentifier: "AddAccountController") as! NSViewController;
            self.presentAsSheet(addAccountController);
            break;
        case 1:
            // remove account
            let selectedRow = tableView!.selectedRow
            guard selectedRow >= 0 && selectedRow < self.accounts.count else {
                return;
            }
            
            let jid = accounts[selectedRow];
            
            let alert = NSAlert();
            alert.messageText = "Account removal";
            alert.informativeText = "Should the account be removed from the server as well?";
            alert.addButton(withTitle: "Remove from server")
            alert.addButton(withTitle: "Remove from application")
            alert.addButton(withTitle: "Cancel");
            alert.beginSheetModal(for: self.view.window!) { (response) in
                switch response {
                case .alertFirstButtonReturn:
                    // remove from the server
                    guard let client = XmppService.instance.getClient(for: jid), client.state == .connected else {
                        let alert = NSAlert();
                        alert.messageText = "Account removal failure";
                        alert.informativeText = "Account needs to be active and connected to remove the acocunt from the server";
                        alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                        return;
                    }
                    
                    let regModule = client.modulesManager.register(InBandRegistrationModule());
                    regModule.unregister({ (result) in
                        if let account = AccountManager.getAccount(for: jid) {
                            _ = AccountManager.delete(account: account);
                        }
                    })
                    break;
                case .alertSecondButtonReturn:
                    // remove from the application
                    if let account = AccountManager.getAccount(for: jid) {
                        _ = AccountManager.delete(account: account);
                    }
                default:
                    // cancel
                    break;
                }
            }
            break;
        default:
            break;
        }
    }
    
}

class AccountRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet {
            if let accountView = self.subviews.last as? AccountCellView {
                if isSelected {
                    accountView.selectedBackgroundColor = isEmphasized ? NSColor.alternateSelectedControlColor : NSColor.secondarySelectedControlColor;
                } else {
                    accountView.selectedBackgroundColor = nil;
                }
            }
        }
    }
    
    override var isEmphasized: Bool {
        didSet {
            if let accountView = self.subviews.last as? AccountCellView {
                if isSelected {
                    accountView.selectedBackgroundColor = isEmphasized ? NSColor.alternateSelectedControlColor : NSColor.secondarySelectedControlColor;
                } else {
                    accountView.selectedBackgroundColor = nil;
                }
            }
        }
    }
}

class AccountCellView: NSTableCellView {
    
    @IBOutlet weak var avatar: AvatarViewWithStatus?;
    @IBOutlet weak var label: NSTextField?;
 
    var selectedBackgroundColor: NSColor? {
        didSet {
            avatar?.backgroundColor = selectedBackgroundColor ?? backgroundColor;
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
            avatar?.backgroundColor = selectedBackgroundColor ?? backgroundColor;
        }
    }
}

protocol AccountAware: class {
    
    var account: BareJID? { get set }
    
}
