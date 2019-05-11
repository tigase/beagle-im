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

class Open1On1ChatController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
 
    @IBOutlet var accountField: NSPopUpButton!
    @IBOutlet var searchField: NSTextField!;
    @IBOutlet var contactsView: NSTableView!;
    
    fileprivate var accountHeightConstraint: NSLayoutConstraint!;
    fileprivate var rows: [Item] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
        updateItems();
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
    }
    
    @IBAction func cancelButtonCliecked(_ sender: NSButton) {
        self.close();
    }
    
    @IBAction func openButtonClicked(_ sender: NSButton) {
        guard !self.searchField.stringValue.isEmpty else {
            return;
        }
        
        let jid = JID(self.searchField.stringValue)
        
        guard let messageModule: MessageModule = XmppService.instance.getClient(for: BareJID(accountField.titleOfSelectedItem!))?.modulesManager.getModule(MessageModule.ID) else {
            self.close();
            return;
        }
        
        _ = messageModule.createChat(with: jid);
        self.close();
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let jid = e.presence.from?.bareJid else {
            return;
        }
        
        DispatchQueue.main.async {
            guard let idx = self.rows.firstIndex(where: { (item) -> Bool in
                return item.account == account && item.jid == jid
            }) else {
                return;
            }
            
            self.contactsView.reloadData(forRowIndexes: IndexSet(integer: idx), columnIndexes: IndexSet(integer: 0));
        }
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
        guard let messageModule: MessageModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(MessageModule.ID) else {
            self.close();
            return;
        }
        
        let chat = messageModule.chatManager.getChatOrCreate(with: JID(item.jid), thread: nil);
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
            guard let roster = (RosterModule.getRosterStore(client.sessionObject) as? DBRosterStoreWrapper) else {
                return;
            }
            
            roster.getJids().forEach({ (jid) in
                let name = roster.get(for: jid)?.name;
                
                rows.append(Item(jid: jid.bareJid, account: account, name: name));
            })
        }
        
        let query = searchField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
        if !query.isEmpty {
            rows = rows.filter { (item) -> Bool in
                return item.jid.stringValue.contains(query) || (item.name ?? "").contains(query);
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
    
    func update(from item: Open1On1ChatController.Item) {
        self.avatar.backgroundColor = NSColor.textBackgroundColor;
        self.jid.stringValue = item.jid.stringValue;
        self.name.stringValue = item.name ?? "";
        self.account.stringValue = "using \(item.account)";
        self.avatar.update(for: item.jid, on: item.account);
    }
    
}
