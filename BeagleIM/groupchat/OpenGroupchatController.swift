//
// OpenGroupchatController.swift
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

class OpenGroupchatController: NSViewController, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet var accountField: NSPopUpButton!;
    @IBOutlet var searchField: NSTextField!;
    @IBOutlet var mucJidField: NSTextField!;
    @IBOutlet var roomsTableView: NSTableView!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var nicknameField: NSTextField!;
    
    fileprivate var accountHeightConstraint: NSLayoutConstraint!;
    fileprivate var nicknameHeightConstraint: NSLayoutConstraint!;
    
    var account: BareJID!;
    
    var allItems: [DiscoveryModule.Item] = [] {
        didSet {
            updateItems();
        }
    }
    
    var items: [DiscoveryModule.Item] = [] {
        didSet {
            roomsTableView.reloadData();
        }
    }
    
    var mucJids: [BareJID] = [] {
        didSet {
            self.mucJidField.stringValue = mucJids.first?.stringValue ?? "";
            if let jid = mucJids.first {
                mucJid = jid;
            }
        }
    }
    
    var mucJid: BareJID? {
        didSet {
            guard oldValue == nil || mucJid == nil || ((oldValue!) != (mucJid!)) else {
                return;
            }
            
            guard mucJid != nil else {
                self.allItems = [];
                return;
            }
            
            guard account != nil else {
                return;
            }
            
            refreshRooms(at: mucJid!);
        }
    }
    
    override func viewDidLoad() {
        self.searchField.delegate = self;
        self.mucJidField.delegate = self;
        self.roomsTableView.dataSource = self;
        self.roomsTableView.delegate = self;
        
        super.viewDidLoad();
        
        accountHeightConstraint = accountField.heightAnchor.constraint(equalToConstant: 0);
        nicknameHeightConstraint = nicknameField.heightAnchor.constraint(equalToConstant: 0);
        
        showDisclosure(false);
    }
    
    override func viewWillAppear() {
        self.accountField.addItem(withTitle: "");
        AccountManager.getAccounts().filter { account -> Bool in
            return XmppService.instance.getClient(for: account) != nil
            }.forEach { (account) in
            self.accountField.addItem(withTitle: account.stringValue);
        }
        if self.account == nil {
            self.account = AccountManager.defaultAccount;
        }
        if self.account != nil {
            self.accountField.selectItem(withTitle: self.account.stringValue);
            self.accountField.title = self.account.stringValue;
        } else {
            self.accountField.selectItem(at: 1);
            self.accountField.title = self.accountField.itemTitle(at: 1);
            self.account = BareJID(self.accountField.itemTitle(at: 1));
        }
        if nicknameField.stringValue.isEmpty {
            nicknameField.stringValue = AccountManager.getAccount(for: account)?.nickname ?? "";
            if nicknameField.stringValue.isEmpty {
                showDisclosure(true);
            }
        }
        if mucJid == nil {
            self.findMucComponent(at: account);
        } else {
            self.refreshRooms(at: mucJid!);
        }
    }
    
    @IBAction func disclosureChangedState(_ sender: NSButton) {
        showDisclosure(sender.state == .on);
    }
    
    func showDisclosure(_ state: Bool) {
        accountField.isHidden = !state;
        accountHeightConstraint.isActive = !state;
        nicknameField.isHidden = !state;
        nicknameHeightConstraint.isActive = !state;
    }
    
    @IBAction func accountSelectionChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else {
            return;
        }
        self.accountField.title = title;
        self.account = BareJID(title);
        self.nicknameField.stringValue = AccountManager.getAccount(for: account)?.nickname ?? "";
        if nicknameField.stringValue.isEmpty {
            showDisclosure(true);
        }
        self.findMucComponent(at: account);
    }
    
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return;
        }
        
        switch field {
        case searchField:
            updateItems();
            break;
        default:
            break;
        }
    }
    
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return;
        }
        
        switch field {
        case mucJidField:
            let mucJidStr = mucJidField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            self.mucJid = mucJidStr.isEmpty ? nil : BareJID(mucJidStr);
            field.resignFirstResponder();
        case searchField:
            break;
        default:
            break;
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "mucRoomView"), owner: self) as? MucRoomView else {
            return nil;
        }
        
        view.set(item: items[row]);
        
        return view;
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }
    
    @IBAction func joinClicked(_ sender: NSButton) {
        let selected = roomsTableView.selectedRow;
        guard selected >= 0 else {
            let roomName = self.searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
            guard !roomName.isEmpty else {
                return;
            }
            guard let item = self.items.first(where: { item -> Bool in
                return roomName == (item.jid.localPart ?? "")
            }) else {
                guard let mucDomain = self.mucJid?.domain else {
                    return;
                }
                self.join(room: BareJID(localPart: roomName, domain: mucDomain));
                return;
            }
            self.openRoom(for: item);
            return;
        }
    
        let roomItem = self.items[selected];
        
        self.openRoom(for: roomItem);
    }
    
    func openRoom(for roomItem: DiscoveryModule.Item) {
        join(room: roomItem.jid.bareJid)
    }
    
    func join(room: BareJID) {
        guard let discoModule: DiscoveryModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        let nickname = self.nicknameField.stringValue;
        
        discoModule.getInfo(for: JID(room), node: nil, onInfoReceived: { node, identities, features in
            let requiresPassword = features.firstIndex(of: "muc_passwordprotected") != nil;
            if !requiresPassword {
                guard let mucModule: MucModule = XmppService.instance.getClient(for: self.account)?.modulesManager.getModule(MucModule.ID) else {
                    return;
                }
                _ = mucModule.join(roomName: room.localPart!, mucServer: room.domain, nickname: nickname);
                PEPBookmarksModule.updateOrAdd(for: self.account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nickname, password: nil));
                DispatchQueue.main.async {
                    self.close();
                }
            } else {
                DispatchQueue.main.async {
                    let alert = NSAlert();
                    alert.messageText = "Enter password for room";
                    alert.informativeText = "This room is password protected. You need to provide correct password to join this room.";
                    let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 21));
                    passwordField.setContentHuggingPriority(.defaultLow, for: .horizontal);
                    alert.accessoryView = passwordField;
                    alert.addButton(withTitle: "OK").tag = NSApplication.ModalResponse.OK.rawValue;
                    alert.addButton(withTitle: "Cancel");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        let password = passwordField.stringValue;
                        if password.isEmpty || response != .OK {
                            self.close();
                        } else {
                            guard let mucModule: MucModule = XmppService.instance.getClient(for: self.account)?.modulesManager.getModule(MucModule.ID) else {
                                return;
                            }
                            _ = mucModule.join(roomName: room.localPart!, mucServer: room.domain, nickname: nickname, password: password);
                            
                            PEPBookmarksModule.updateOrAdd(for: self.account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nickname, password: password));
                            self.close();
                        }
                    })
                }
            }
        }, onError: { (errorCondition) in
            if errorCondition != nil && errorCondition! == ErrorCondition.item_not_found {
                DispatchQueue.main.async {
                    guard let configRoomController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConfigureRoomViewController")) as? ConfigureRoomViewController else {
                        return;
                    }
                    
                    let window = NSWindow(contentViewController: configRoomController);
                    configRoomController.account = self.account;
                    configRoomController.mucComponent = self.mucJid!;
                    configRoomController.roomJid = room;
                    self.view.window?.beginSheet(window, completionHandler: { result in
                        if result == .OK {
                            self.join(room: room)
                        }
                        self.close();
                    });
                }
            } else {
                DispatchQueue.main.async {
                    self.close();
                }
            }
        });
    }
    
    func updateItems() {
        let val = searchField.stringValue;
        if val.isEmpty {
            self.items = allItems;
        } else {
            if val.contains("@") {
                self.items = allItems.filter({ (item) -> Bool in
                    return (item.name ?? "").contains(val) || item.jid.stringValue.contains(val);
                });
            } else {
                self.items = allItems.filter({ (item) -> Bool in
                    return (item.name ?? "").contains(val) || (item.jid.localPart ?? "").contains(val);
                });
            }
        }
    }
    
    fileprivate func findMucComponent(at account: BareJID) {
        guard let discoModule: DiscoveryModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        self.mucJids = [];
        self.allItems = [];
        progressIndicator.startAnimation(nil);
        
        discoModule.getItems(for: JID(account.domain), onItemsReceived: { (node, items) in
            var mucJids: [BareJID] = [];
            var counter = items.count;
            let finisher = {
                counter = counter - 1;
                if (counter <= 0) {
                    self.progressIndicator.stopAnimation(nil);
                    self.mucJids = mucJids.sorted(by: { (j1, j2) -> Bool in
                        return j2.stringValue.compare(j2.stringValue) == .orderedAscending;
                    });
                }
            };
            
            items.forEach({ item in
                discoModule.getInfo(for: item.jid, node: item.node, onInfoReceived: { node, identities, features in
                    DispatchQueue.main.async {
                        let idx = features.firstIndex(of: "http://jabber.org/protocol/muc");
                        if idx != nil {
                            mucJids.append(item.jid.bareJid);
                        }
                        finisher();
                    }
                }, onError: { (errorCondition) in
                    DispatchQueue.main.async {
                        finisher();
                    }
                });
            });
            if items.isEmpty {
                DispatchQueue.main.async {
                    finisher();
                }
            }
        }, onError: { (errorCondition) in
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil);
            }
        });
    }
    
    fileprivate func refreshRooms(at mucJid: BareJID) {
        guard let discoModule: DiscoveryModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        self.allItems = [];
        progressIndicator.startAnimation(nil);
        
        discoModule.getItems(for: JID(mucJid), onItemsReceived: { (node, items) in
            let sortedItems = items.sorted(by: { (i1, i2) -> Bool in
                let n1 = i1.name ?? i1.jid.localPart!;
                let n2 = i2.name ?? i2.jid.localPart!;
                return n1.compare(n2) == ComparisonResult.orderedAscending;
            })
            DispatchQueue.main.async {
                self.allItems = sortedItems;
                self.progressIndicator.stopAnimation(nil);
            }
        }) { (errorCondition) in
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil);
            }
        };
    }
 
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
}

class MucRoomView: NSTableCellView {
    
    @IBOutlet var label: NSTextField!;
    @IBOutlet var jidLabel: NSTextField!;
    
    func set(item: DiscoveryModule.Item) {
        label.stringValue = item.name ?? item.jid.localPart!;
        jidLabel.stringValue = item.jid.stringValue;
    }
}
