//
// ManageAffiliationsViewController.swift
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

class ManageAffiliationsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet var tableView: NSTableView!;
    @IBOutlet var searchField: NSTextField!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var room: DBChatStore.DBRoom!;
    
    fileprivate var affiliations: [MucModule.RoomAffiliation] = [];
    
    fileprivate var visibleAffiliations: [MucModule.RoomAffiliation] = [];
    
    fileprivate var changes: [JID: MucAffiliation] = [:];
    
    override func viewDidLoad() {
        self.tableView.dataSource = self;
        self.tableView.delegate = self;
        self.searchField.target = self;
        self.searchField.action = #selector(updateVisibleAffiliations);
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        guard let mucModule: MucModule = XmppService.instance.getClient(for: room.account)?.modulesManager.getModule(MucModule.ID) else {
            return;
        }
        
        let affiliations: [MucAffiliation] = [.member, .admin, .outcast, .owner];
        var count = affiliations.count;
        self.progressIndicator.startAnimation(nil);
        var errors = 0;
        affiliations.forEach { aff in
            mucModule.getRoomAffiliations(from: room, with: aff) { (affiliations, error) in
                DispatchQueue.main.async {
                    count = count - 1;
                    if count <= 0 {
                        self.progressIndicator.stopAnimation(nil);
                        if errors > 0 {
                            let alert = NSAlert();
                            alert.icon = NSImage(named: NSImage.cautionName);
                            alert.messageText = "Authorization error";
                            alert.informativeText = "You are not authorized to view memeber list of this room.";
                            alert.addButton(withTitle: "OK");
                            alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
                                self.close();
                            });
                        }
                    }
                }
                guard affiliations != nil else {
                    print("got error", error as Any);
                    errors = errors + 1;
                    return;
                }
                DispatchQueue.main.async {
                    self.affiliations.append(contentsOf: affiliations!);
                    self.updateVisibleAffiliations();
                }
            }
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return visibleAffiliations.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch tableColumn!.identifier.rawValue {
        case "ManageAffiliationsColumnJid":
            guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ManageAffiliationsColumnJidView"), owner: self) as? NSTableCellView else {
                return nil;
            }
            view.textField?.stringValue = visibleAffiliations[row].jid.stringValue;
            return view;
        case "ManageAffiliationsColumnAffiliation":
            guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ManageAffiliationsColumnAffiliationView"), owner: self) as? NSTableCellView else {
                return nil;
            }
            let affil = visibleAffiliations[row].affiliation;
            if let popUpButton = (view.subviews[0] as? NSPopUpButton) {
                popUpButton.removeAllItems();
                popUpButton.addItem(withTitle: "");
                popUpButton.addItems(withTitles: ["Owner", "Admin", "Member", "Outcast"]);
                switch affil {
                case .owner:
                    popUpButton.selectItem(at: 1);
                case .admin:
                    popUpButton.selectItem(at: 2);
                case .member:
                    popUpButton.selectItem(at: 3);
                case .outcast:
                    popUpButton.selectItem(at: 4);
                default:
                    popUpButton.selectItem(withTitle: "");
                }
                popUpButton.title = popUpButton.titleOfSelectedItem ?? "";
                popUpButton.tag = row;
                popUpButton.action = #selector(affiliationChangedForRow);
                popUpButton.target = self;
            }
            return view;
        default:
            return nil;
        }
    }
    
    @objc fileprivate func updateVisibleAffiliations() {
        self.affiliations.sort(by: { (a1, a2) -> Bool in
            return a1.jid.stringValue.compare(a2.jid.stringValue) == .orderedAscending
        });
        let searchString = self.searchField.stringValue;
        if !searchString.isEmpty {
            self.visibleAffiliations = self.affiliations.filter({ (item) -> Bool in
                return item.jid.stringValue.contains(searchString);
            });
        } else {
            self.visibleAffiliations = self.affiliations;
        }
        self.tableView.reloadData();
    }
    
    @objc func affiliationChangedForRow(_ popUpButton: NSPopUpButton) {
        popUpButton.title = popUpButton.titleOfSelectedItem ?? "";
        guard popUpButton.tag >= 0 else {
            return;
        }
        let item = visibleAffiliations[popUpButton.tag];
        let newAffil = affiliation(from: popUpButton);
        if item.affiliation != newAffil {
            guard let idx = affiliations.firstIndex(where: { it -> Bool in
                return it.jid == item.jid;
            }) else {
                return;
            }
            let newItem = MucModule.RoomAffiliation(jid: item.jid, affiliation: newAffil, nickname: item.nickname, role: item.role);
            visibleAffiliations[popUpButton.tag] = newItem;
            affiliations[idx] = newItem;
            changes[item.jid] = newAffil;
        }
    }
    
    fileprivate func affiliation(from popUpButton: NSPopUpButton) -> MucAffiliation {
        switch popUpButton.indexOfSelectedItem {
        case 1:
            return .owner;
        case 2:
            return .admin;
        case 3:
            return .member;
        case 4:
            return .outcast;
        default:
            return .none;
        }
    }
    
    @IBAction func addItemClicked(_ sender: NSButton) {
        let alert = NSAlert();
        alert.messageText = "Add member";
        alert.informativeText = "Please provide user JID and affiliation to this room.";
        
        alert.addButton(withTitle: "Add");
        alert.addButton(withTitle: "Cancel");
        
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 54));
        view.orientation = .vertical;
        
        let jidField = NSTextField(string: "");
        jidField.placeholderString = "Enter JID"
        jidField.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.addView(jidField, in: .bottom);
        
        let popUpButton = NSPopUpButton(frame: NSRect(x: 0, y:0, width: 200, height: 21), pullsDown: true);
        popUpButton.autoenablesItems = true;
        popUpButton.addItem(withTitle: "");
        popUpButton.addItems(withTitles: ["Owner", "Admin", "Member", "Outcast"]);
        popUpButton.selectItem(at: 3);
        popUpButton.title = popUpButton.titleOfSelectedItem ?? "";
        popUpButton.tag = -1;
        popUpButton.action = #selector(affiliationChangedForRow(_:));
        popUpButton.target = self;
        let label = NSTextField(labelWithString: "Affiliation:");
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        let row = NSStackView(views: [label, popUpButton]);
        view.addView(row, in: .bottom);
        
        alert.accessoryView = view;
        view.layout();
        
        alert.beginSheetModal(for: self.view.window!) { (response) in
            switch response {
            case .alertFirstButtonReturn:
                let jidStr = jidField.stringValue.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
                if !jidStr.isEmpty {
                    let newItem = MucModule.RoomAffiliation(jid: JID(jidStr), affiliation: self.affiliation(from: popUpButton));
                    self.changes[newItem.jid] = newItem.affiliation;
                    self.affiliations.append(newItem);
                    if !self.searchField.stringValue.isEmpty {
                        if !jidStr.contains(self.searchField.stringValue) {
                            self.searchField.stringValue = "";
                        }
                    }
                    self.updateVisibleAffiliations();
                }
            default:
                break;
            }
        }
    }
    
    @IBAction func removeItemClicked(_ sender: NSButton) {
        let row = tableView.selectedRow;
        guard row >= 0 else {
            return;
        }
        let item = visibleAffiliations.remove(at: row);
        affiliations.removeAll(where: { it -> Bool in
            return it.jid == item.jid;
        });
        changes[item.jid] = MucAffiliation.none;
        tableView.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade);
    }

    @IBAction func cancelClicked(_ sender: NSButton) {
        self.close();
    }
    
    @IBAction func saveClicked(_ sender: NSButton) {
        let changes = self.changes.map { (jid, affil) -> MucModule.RoomAffiliation in
            return MucModule.RoomAffiliation(jid: jid, affiliation: affil);
        };
        
        guard let mucModule: MucModule = XmppService.instance.getClient(for: room.account)?.modulesManager.getModule(MucModule.ID) else {
            return;
        }
        
        self.progressIndicator.startAnimation(nil);
        
        mucModule.setRoomAffiliations(to: room, changedAffiliations: changes) { (error) in
            guard error != nil else {
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(nil);
                    self.close();
                }
                return;
            }
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil);
                let alert = NSAlert();
                alert.icon = NSImage(named: NSImage.cautionName);
                alert.messageText = "Error occurred";
                alert.informativeText = ((error!) == ErrorCondition.forbidden) ? "You are not allowed to modify list of affiliations for this room." : "Server returned an error: \(error!)";
                alert.addButton(withTitle: "OK");
                alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
            }
        }
    }
    
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
}
