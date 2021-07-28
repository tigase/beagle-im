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
import Combine

class AccountsListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet var tableView: NSTableView?;
    
    @IBOutlet var editButton: NSPopUpButton!;
    @IBOutlet var removeButton: NSButton!;
    @IBOutlet var setDefaultButton: NSButton!;
    
    var accounts: [BareJID] = [];
    var currentAccount: BareJID? {
        didSet {
            updateButtonsForCurrentAccount();
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        AccountManager.accountEventsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] event in
            self?.accountChanged();
        }).store(in: &cancellables);
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.refreshAccounts();
    }
    
    func refreshAccounts() {
        accounts = AccountManager.getAccounts();
        self.currentAccount = nil;
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
        view.set(account: accounts[row]);
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard (tableView?.selectedRow ?? -1) >= 0 else {
            self.currentAccount = nil;
            return;
        }
        self.currentAccount = accounts[tableView!.selectedRow];
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return AccountRowView();
    }
        
    func accountChanged() {
        let selectedRow = self.tableView?.selectedRow;
        self.refreshAccounts();
        if selectedRow != nil {
            self.tableView?.selectRowIndexes(IndexSet(integer: selectedRow!), byExtendingSelection: false);
        }
    }
    
    func updateButtonsForCurrentAccount() {
        self.removeButton.isEnabled = currentAccount != nil;
        self.editButton.isEnabled = currentAccount != nil;
        self.setDefaultButton.isEnabled = currentAccount != nil;
        
        if let account = currentAccount {
            let connected = XmppService.instance.getClient(for: account)?.state == .connected();
            let items = self.editButton.menu?.items ?? [];
            for i in 0..<items.count {
                items[i].isEnabled = i < 3 || connected;
                if items[i].action == #selector(changeAccountVCardClicked(_:)) {
                    items[i].isHidden = Settings.showAdvancedXmppFeatures;
                }
                if items[i].hasSubmenu {
                    items[i].isHidden = !Settings.showAdvancedXmppFeatures;
                }
            }
        }
    }
    
    @IBAction func addAccountClicked(_ sender: NSButton) {
        let addAccountController = self.storyboard!.instantiateController(withIdentifier: "AddAccountController") as! NSViewController;
        self.presentAsSheet(addAccountController);
    }

    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let aware = segue.destinationController as? AccountAware {
            aware.account = self.currentAccount;
        }
        if segue.identifier == "showEditAccountPrivateVCard", let controller = segue.destinationController as? VCardEditorViewController {
            controller.isPrivate = true;
        }
    }
    
    @IBAction func setDefaultClicked(_ sender: NSButton) {
        guard let account = self.currentAccount else {
            return;
        }
        AccountManager.defaultAccount = account;
        let selectedRow = self.tableView?.selectedRow;
        self.refreshAccounts();
        if selectedRow != nil {
            self.tableView?.selectRowIndexes(IndexSet(integer: selectedRow!), byExtendingSelection: false);
        }
    }

    @IBAction func editAccountDetailsClicked(_ sender: NSMenuItem) {
        performSegue(withIdentifier: "showEditAccountConnectionDetails", sender: self);
    }

    @IBAction func changeAccountPasswordClicked(_ sender: NSMenuItem) {
        performSegue(withIdentifier: "showChangeAccountPassword", sender: self);
    }

    @IBAction func changeAccountVCardClicked(_ sender: NSMenuItem) {
        performSegue(withIdentifier: "showEditAccountVCard", sender: self);
    }

    @IBAction func changeAccountPrivateVCardClicked(_ sender: NSMenuItem) {
        performSegue(withIdentifier: "showEditAccountPrivateVCard", sender: self);
    }

    @IBAction func changeAccountOmemoClicked(_ sender: NSMenuItem) {
        performSegue(withIdentifier: "showEditAccountOmemoSettings", sender: self);
    }

    @IBAction func changeAccountMamClicked(_ sender: NSMenuItem) {
        performSegue(withIdentifier: "showEditAccountMamSettings", sender: self);
    }


    @IBAction func removeAccountClicked(_ sender: NSButton) {
        let selectedRow = tableView!.selectedRow
        guard selectedRow >= 0 && selectedRow < self.accounts.count else {
            return;
        }
        
        let jid = accounts[selectedRow];
        
        let alert = NSAlert();
        alert.messageText = NSLocalizedString("Account removal", comment: "alert window title");
        alert.informativeText = NSLocalizedString("Should the account be removed from the server as well?", comment: "alert window message");
        alert.addButton(withTitle: NSLocalizedString("Remove from server", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("Remove from application", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        alert.beginSheetModal(for: self.view.window!) { (response) in
            switch response {
            case .alertFirstButtonReturn:
                // remove from the server
                guard let client = XmppService.instance.getClient(for: jid), client.isConnected else {
                    let alert = NSAlert();
                    alert.messageText = NSLocalizedString("Account removal failure", comment: "alert window title");
                    alert.informativeText = NSLocalizedString("Account needs to be active and connected to remove the acocunt from the server", comment: "alert window message");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    return;
                }
                
                let regModule = client.modulesManager.register(InBandRegistrationModule());
                regModule.unregister(completionHander: { (result) in
                    DispatchQueue.main.async {
                        if let account = AccountManager.getAccount(for: jid) {
                            do {
                                try AccountManager.delete(account: account);
                            } catch {
                                let alert = NSAlert(error: error);
                                alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                            }
                        }
                    }
                })
                break;
            case .alertSecondButtonReturn:
                // remove from the application
                if let account = AccountManager.getAccount(for: jid) {
                    do {
                        try AccountManager.delete(account: account);
                    } catch {
                        let alert = NSAlert(error: error);
                        alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    }
                }
            default:
                // cancel
                break;
            }
        }
    }
        
}

class AccountRowView: NSTableRowView {
    override var isSelected: Bool {
        didSet {
            if let accountView = self.subviews.last as? AccountCellView {
                accountView.isSelected = isSelected;
            }
        }
    }
    
    override func addSubview(_ view: NSView) {
        super.addSubview(view);
        if let accountView = view  as? AccountCellView {
            accountView.isSelected = isSelected;
            accountView.isEmphasized = isEmphasized;
        }
    }
    
    override var isEmphasized: Bool {
        didSet {
            if let accountView = self.subviews.last as? AccountCellView {
                accountView.isEmphasized = isEmphasized;
            }
        }
    }
}

class AccountCellView: NSTableCellView {
    
    @IBOutlet var enabledCheckbox: NSButton!;
    @IBOutlet var avatar: AvatarViewWithStatus! {
        didSet {
            refreshBackgroundSelectionColor();
        }
    }
    @IBOutlet var defaultLabel: NSTextField!;
    @IBOutlet var nickname: NSTextField!;
    @IBOutlet var jid: NSTextField!;
     
    private var cancellables: Set<AnyCancellable> = [];
    
    private var accountJid: BareJID?;
    private var avatarObj: Avatar? {
        didSet {
            avatarObj?.avatarPublisher.receive(on: DispatchQueue.main).assign(to: \.avatar, on: avatar).store(in: &cancellables);
        }
    }
    
    var isSelected: Bool = false {
        didSet {
            refreshBackgroundSelectionColor();
        }
    }
    
    var isEmphasized: Bool = false {
        didSet {
            refreshBackgroundSelectionColor();
        }
    }
    
    private func refreshBackgroundSelectionColor() {
        avatar?.backgroundColor = isSelected ? (isEmphasized ? NSColor.alternateSelectedControlColor : NSColor.selectedControlColor) : NSColor.controlBackgroundColor;

    }

    func set(account accountJid: BareJID) {
        cancellables.removeAll();
        self.accountJid = accountJid;
        avatarObj = AvatarManager.instance.avatarPublisher(for: .init(account: accountJid, jid: accountJid, mucNickname: nil));
        let acc = AccountManager.getAccount(for: accountJid);
        switch acc?.state.value {
        case .connected:
            avatar.status = .online;
        case .connecting:
            avatar.status = .away;
        default:
            avatar.status = nil;
        }
        acc?.state.map({ state -> Presence.Show? in
            switch state {
            case .connected:
                return .online;
            case .connecting:
                return .away;
            default:
                return nil;
            }
        }).receive(on: DispatchQueue.main).assign(to: \.status, on: avatar).store(in: &cancellables);
        enabledCheckbox.state = (acc?.active ?? false) ? .on : .off;
        nickname.stringValue = acc?.nickname ?? "";
        jid.stringValue = accountJid.stringValue
        defaultLabel.isHidden = accountJid != AccountManager.defaultAccount;
    }
    
    @IBAction func enabledSwitched(_ sender: NSButton) {
        if let accountJid = self.accountJid, var account = AccountManager.getAccount(for: accountJid) {
            account.active = sender.state == .on;
            do {
                try AccountManager.save(account: account);
            } catch {
                sender.state = sender.state == .on ? .off : .on;
            }
        }
    }

}

protocol AccountAware: AnyObject {
    
    var account: BareJID? { get set }
    
}
