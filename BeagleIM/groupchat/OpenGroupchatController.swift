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
    @IBOutlet var componentJidField: NSTextField!;
    @IBOutlet var roomsTableView: NSTableView!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var nicknameField: NSTextField!;
    @IBOutlet var joinButton: NSButton!;
    
    fileprivate var accountHeightConstraint: NSLayoutConstraint!;
    fileprivate var nicknameHeightConstraint: NSLayoutConstraint!;
    
    var account: BareJID!;
    var password: String?;
    
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
    
    var componentJids: [BareJID] = [] {
        didSet {
            self.componentJidField.stringValue = componentJids.first?.stringValue ?? "";
            if let jid = componentJids.first {
                componentJid = jid;
            }
        }
    }
    
    var componentJid: BareJID? {
        didSet {
            guard oldValue == nil || componentJid == nil || ((oldValue!) != (componentJid!)) else {
                return;
            }
            
            guard componentJid != nil else {
                self.allItems = [];
                return;
            }
            
            guard account != nil else {
                return;
            }
            
            refreshRooms(at: componentJid!);
        }
    }
    
    override func viewDidLoad() {
        self.searchField.delegate = self;
        self.componentJidField.delegate = self;
        self.nicknameField.delegate = self;
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
            joinButton.isEnabled = !nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
        }
        if componentJid == nil {
            self.findMucComponent(at: account);
        } else {
            self.refreshRooms(at: componentJid!);
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
        joinButton.isEnabled = !nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
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
        case nicknameField:
            joinButton.isEnabled = !nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
        default:
            break;
        }
    }
    
    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return;
        }
        
        switch field {
        case componentJidField:
            let mucJidStr = componentJidField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            self.componentJid = mucJidStr.isEmpty ? nil : BareJID(mucJidStr);
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
                guard let mucDomain = self.componentJid?.domain else {
                    return;
                }
                self.join(jid: BareJID(localPart: roomName, domain: mucDomain));
                return;
            }
            self.openRoom(for: item);
            return;
        }
    
        let roomItem = self.items[selected];
        
        self.openRoom(for: roomItem);
    }
    
    func openRoom(for roomItem: DiscoveryModule.Item) {
        join(jid: roomItem.jid.bareJid)
    }
    
    func join(jid: BareJID) {
        guard let type = componentType else {
            return;
        }
        
        switch type {
        case .mix:
            joinChannel(channel: jid);
        case .muc:
            joinRoom(room: jid);
        }
    }
    
    func joinChannel(channel: BareJID) {
        guard let mixModule: MixModule = XmppService.instance.getClient(for: account)?.module(.mix) else {
            return;
        }
        
        let nickname = self.nicknameField.stringValue;
        mixModule.join(channel: channel, withNick: nickname, completionHandler: { result in
            switch result {
            case .success( _):
                // we have joined, so all what we need to do is close this window
                DispatchQueue.main.async {
                    self.close();
                }
            case .failure(let error):
                switch error {
                case .item_not_found:
                    // there is no such channel, we need to create a new one..
                    mixModule.create(channel: channel.localPart, at: BareJID(channel.domain), completionHandler: { result in
                        switch result {
                        case .success(let channel):
                            mixModule.join(channel: channel, withNick: nickname, completionHandler: { result in
                                switch result {
                                case .success( _):
                                    // we have joined, so all what we need to do is close this window
                                    DispatchQueue.main.async {
                                        self.close();
                                    }
                                case .failure(let error):
                                    DispatchQueue.main.async {
                                        let alert = NSAlert();
                                        alert.messageText = "Could not join";
                                        alert.informativeText = "The channel \(channel) was created but it was not possible to join it. The server returned an error: \(error.message ?? error.description)";
                                        alert.addButton(withTitle: "OK")
                                        alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                                            self.close();
                                        });
                                    }
                                }
                            });
                        case .failure(let errorCondition):
                            DispatchQueue.main.async {
                                let alert = NSAlert();
                                alert.messageText = "Could not create";
                                alert.informativeText = "It was not possible to create a channel. The server returned an error: \(errorCondition.message ?? errorCondition.description)";
                                alert.addButton(withTitle: "OK")
                                alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                                    self.close();
                                });
                            }
                        }
                    })
                default:
                    DispatchQueue.main.async {
                        let alert = NSAlert();
                        alert.messageText = "Could not join";
                        alert.informativeText = "It was not possible to join a channel. The server returned an error: \(error.message ?? error.description)";
                        alert.addButton(withTitle: "OK")
                        alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                            self.close();
                        });
                    }
                }
            }
        });
    }
    
    func joinRoom(room: BareJID) {
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }
        
        let nickname = self.nicknameField.stringValue;
        client.module(.disco).getInfo(for: JID(room), node: nil, completionHandler: { result in
            switch result {
            case .success(let info):
                let requiresPassword = info.features.contains("muc_passwordprotected");
                if !requiresPassword || (requiresPassword && self.password != nil) {
                    _ = client.module(.muc).join(roomName: room.localPart!, mucServer: room.domain, nickname: nickname);
                    PEPBookmarksModule.updateOrAdd(for: self.account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nickname, password: self.password));
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
                                _ = client.module(.muc).join(roomName: room.localPart!, mucServer: room.domain, nickname: nickname, password: password);
                                
                                PEPBookmarksModule.updateOrAdd(for: self.account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nickname, password: password));
                                self.close();
                            }
                        })
                    }
                }
            case .failure(let error):
                guard error != .item_not_found else {
                    DispatchQueue.main.async {
                        self.close();
                    }
                    return;
                }
                DispatchQueue.main.async {
                    guard let configRoomController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConfigureRoomViewController")) as? ConfigureRoomViewController else {
                        return;
                    }
                    
                    let window = NSWindow(contentViewController: configRoomController);
                    configRoomController.account = self.account;
                    configRoomController.mucComponent = self.componentJid!;
                    configRoomController.roomJid = room;
                    configRoomController.nickname = nickname;
                    self.view.window?.beginSheet(window, completionHandler: { result in
                        self.close();
                    });
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
        guard let discoModule = XmppService.instance.getClient(for: account)?.module(.disco) else {
            return;
        }
        
        self.componentJids = [];
        self.allItems = [];
        progressIndicator.startAnimation(nil);
        
        discoModule.getItems(for: JID(account.domain), completionHandler: { result in
            switch result {
            case .success(let items):
                var mucJids: [BareJID] = [];

                let group = DispatchGroup();
                
                group.enter();
                group.notify(queue: DispatchQueue.main, execute: {
                    self.progressIndicator.stopAnimation(nil);
                    self.componentJids = mucJids.sorted(by: { (j1, j2) -> Bool in
                        return j2.stringValue.compare(j2.stringValue) == .orderedAscending;
                    });
                })

                for item in items.items {
                    group.enter();
                    discoModule.getInfo(for: item.jid, node: item.node, completionHandler: { result in
                        switch result {
                        case .success(let info):
                            if info.features.contains("http://jabber.org/protocol/muc") {
                                DispatchQueue.main.async {
                                    mucJids.append(item.jid.bareJid);
                                }
                            }
                        case .failure(_):
                            break;
                        }
                        group.leave();
                    });
                }
                group.leave();
            case .failure(_):
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(nil);
                }
            }
        });
    }
    
    var componentType: ComponentType?;
    
    fileprivate func refreshRooms(at mucJid: BareJID) {
        guard let discoModule = XmppService.instance.getClient(for: account)?.module(.disco) else {
            return;
        }
        
        self.allItems = [];
        progressIndicator.startAnimation(nil);
        
        self.componentType = nil;
        var foundItems: [DiscoveryModule.Item] = [];
        
        let group = DispatchGroup();
        group.enter();
        discoModule.getItems(for: JID(mucJid), completionHandler: { result in
            switch result {
            case .success(let items):
                let sortedItems = items.items.sorted(by: { (i1, i2) -> Bool in
                    let n1 = i1.name ?? i1.jid.localPart ?? "";
                    let n2 = i2.name ?? i2.jid.localPart ?? "";
                    return n1.compare(n2) == ComparisonResult.orderedAscending;
                })
                DispatchQueue.main.async {
                    foundItems = sortedItems;
                }
            case .failure(_):
                break;
            }
            group.leave();
        });
        
        group.enter();
        discoModule.getInfo(for: JID(mucJid), node: nil, completionHandler: { result in
            switch result {
            case .success(let info):
                DispatchQueue.main.async {
                    self.componentType = ComponentType.from(identities: info.identities, features: info.features);
                }
            case .failure(_):
                break;
            }
            group.leave();
        });
        
        group.notify(queue: DispatchQueue.main, execute: {
            if self.componentType == nil {
                self.allItems = [];
            } else {
                self.allItems = foundItems;
            }
            self.progressIndicator.stopAnimation(nil);
        })
    }
 
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
    
    enum ComponentType {
        case muc
        case mix
        
        static func from(identities: [DiscoveryModule.Identity], features: [String]) -> ComponentType? {
            if identities.first(where: { $0.category == "conference" && $0.type == "mix" }) != nil && features.contains(MixModule.CORE_XMLNS) {
                return .mix;
            }
            if identities.first(where: { $0.category == "conference" }) != nil && features.contains("http://jabber.org/protocol/muc") {
                return .muc;
            }
            return nil;
        }
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
