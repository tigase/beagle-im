//
// Open1On1ChatController.swift
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

class Open1On1ChatController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
 
    @IBOutlet var accountField: NSPopUpButton!
    @IBOutlet var searchField: NSTextField!;
    @IBOutlet var contactsView: NSTableView!;
    
    fileprivate var accountHeightConstraint: NSLayoutConstraint!;
    fileprivate var rows: [Item] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        accountHeightConstraint = accountField.heightAnchor.constraint(equalToConstant: 0);
        self.showDisclosure(false);
        self.accountField.addItem(withTitle: "");
        AccountManager.getAccounts().filter { account -> Bool in
            return XmppService.instance.getClient(for: account) != nil
            }.forEach { (account) in
                self.accountField.addItem(withTitle: account.stringValue);
        }
        if let defAccount = AccountManager.defaultAccount {
            self.accountField.selectItem(withTitle: defAccount.stringValue);
            self.accountField.title = self.accountField.titleOfSelectedItem ?? "";
        } else {
            self.accountField.selectItem(at: 1);
            self.accountField.title = self.accountField.itemTitle(at: 1);
        }
        updateItems();
    }
    
    @IBAction func cancelButtonCliecked(_ sender: NSButton) {
        self.close();
    }
    
    @IBAction func openButtonClicked(_ sender: NSButton) {
        guard !self.searchField.stringValue.isEmpty else {
            return;
        }

        guard let account = BareJID(accountField.titleOfSelectedItem) else {
            return;
        }
        
        let jid = BareJID(self.searchField.stringValue)
        
        guard let client = XmppService.instance.getClient(for: account) else {
            self.close();
            return;
        }
        
        let created = client.module(.message).chatManager.chat(for: client, with: jid) == nil;
        if let chat = client.module(.message).chatManager.createChat(for: client, with: jid) {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: chat)
                
                guard created && DBRosterStore.instance.item(for: account, jid: JID(jid)) == nil && Settings.askToAddContactOnChatOpening else {
                    return;
                }
                
                // we are opening a chat with someone not in our roster
                let addContact = NSStoryboard(name: "Roster", bundle: nil).instantiateController(withIdentifier: "AddContactController") as! AddContactController;
                addContact.showDoNotAskAgain = true;
                
                _ = addContact.view;
                if let idx = addContact.accountSelector.itemTitles.firstIndex(of: account.stringValue) {
                    addContact.accountSelector.selectItem(at: idx);
                }
                addContact.jidField.stringValue = jid.stringValue

                if let window = (NSApplication.shared.delegate as? AppDelegate)?.mainWindowController?.window {
                    window.contentViewController?.presentAsSheet(addContact);
                }
                addContact.verify();
            }
        }
        self.close();
    }
    
    @IBAction func disclosureChangedState(_ sender: NSButton) {
        showDisclosure(sender.state == .on);
    }
    
    func showDisclosure(_ state: Bool) {
        accountField.isHidden = !state;
        accountHeightConstraint.isActive = !state;
        updateItems();
    }
    
    func controlTextDidChange(_ obj: Notification) {
        guard let textField = obj.object as? NSTextField else {
            return;
        }
        guard searchField == textField else {
            return;
        }
        
        print("changed value of search field", searchField.stringValue);
        self.updateItems();
    }
    
    func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!)
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count;
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return rows[row];
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return Open1On1ChatRowView(frame: NSRect.zero);
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("Open1On1ChatItemView"), owner: nil) as? Open1On1ChatItemView else {
            return nil;
        }
        
        let item = self.tableView(tableView, objectValueFor: tableColumn, row: row) as! Item;
        view.update(from: item);
        view.layout();
        
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        let item = self.rows[self.contactsView.selectedRow];
        guard let client = XmppService.instance.getClient(for: item.account) else {
            self.close();
            return;
        }
        
        let chat = client.module(.message).chatManager.createChat(for: client, with: item.jid);
        NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: chat)
        // need to handle autoselection of chat on opening it!
        self.close();
    }
    
    fileprivate func updateItems() {
        var rows: [Item] = [];
        let accountFilter: BareJID? = (!self.accountField.isHidden) ? BareJID(self.accountField.titleOfSelectedItem) : nil;
        XmppService.instance.clients.forEach { (account, client) in
            guard accountFilter == nil || account == accountFilter else {
                return;
            }
            
            rows.append(contentsOf: DBRosterStore.instance.items(for: client).map({ Item(jid: $0.jid.bareJid, account: account, name: $0.name)}));
        }
        
        let query = searchField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased();
        if !query.isEmpty {
            rows = rows.filter { (item) -> Bool in
                return item.jid.stringValue.lowercased().contains(query) || (item.name?.lowercased() ?? "").contains(query);
            };
        }
        self.rows = rows.sorted { (i1, i2) -> Bool in
                let n1 = i1.name ?? i1.jid.stringValue;
                let n2 = i2.name ?? i2.jid.stringValue;
                return n1.compare(n2) == .orderedAscending;
        }
        self.contactsView.reloadData();
    }
    
    @IBAction func accountSelectionChanged(_ sender: Any) {
        self.updateItems();
    }
    
    class Item {
        
        let jid: BareJID;
        let account: BareJID;
        let name: String?;
        
        init(jid: BareJID, account: BareJID, name: String?) {
            self.jid = jid;
            self.account = account;
            self.name = name;
        }
    }
}

class Open1On1ChatRowView: NSTableRowView {
    
}

class Open1On1ChatItemView: NSTableCellView {
    @IBOutlet var avatar: AvatarViewWithStatus!
    @IBOutlet var name: NSTextField!
    @IBOutlet var jid: NSTextField!
    @IBOutlet var account: NSTextField!
        
    private var contact: Contact? {
        didSet {
            cancellables.removeAll();
            contact?.displayNamePublisher.assign(to: \.stringValue, on: name).store(in: &cancellables);
            self.jid.stringValue = contact?.jid.stringValue ?? "";
            self.account.stringValue = String.localizedStringWithFormat(NSLocalizedString("using %@", comment: "marks used account"), contact?.account.stringValue ?? "");
            self.avatar.displayableId = contact;
        }
    }
    private var cancellables: Set<AnyCancellable> = [];
    
    func update(from item: Open1On1ChatController.Item) {
        self.avatar.backgroundColor = NSColor.textBackgroundColor;
        
        self.contact = ContactManager.instance.contact(for: .init(account: item.account, jid: item.jid, type: .buddy));
    }
    
}
