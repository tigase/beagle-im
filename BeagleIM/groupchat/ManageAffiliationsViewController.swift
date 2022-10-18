//
// ManageAffiliationsViewController.swift
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
import Martin

class ManageAffiliationsViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet var tableView: NSTableView!;
    @IBOutlet var searchField: NSTextField!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var room: Room!;
    
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
        
        guard let mucModule = room.context?.module(.muc) else {
            return;
        }
        
        let affiliations: [MucAffiliation] = [.member, .admin, .outcast, .owner];
        self.progressIndicator.startAnimation(nil);

        Task {
            do {
                let results = try await affiliations.asyncMapReduce({ aff in
                    return try await mucModule.roomAffiliations(from: room, with: aff);
                })
                await MainActor.run(body: {
                    self.affiliations.append(contentsOf: results);
                    self.updateVisibleAffiliations();
                })
            } catch {
                await MainActor.run(body: {
                    if let window = self.view.window {
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.messageText = NSLocalizedString("Authorization error", comment: "alert window title");
                        alert.informativeText = NSLocalizedString("You are not authorized to view memeber list of this room.", comment: "alert window message");
                        _ = alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: { result in
                            self.close();
                        });
                    }
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(nil);
            })
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
            view.textField?.stringValue = visibleAffiliations[row].jid.description;
            return view;
        case "ManageAffiliationsColumnAffiliation":
            guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ManageAffiliationsColumnAffiliationView"), owner: self) as? NSTableCellView else {
                return nil;
            }
            let affil = visibleAffiliations[row].affiliation;
            if let popUpButton = (view.subviews[0] as? NSPopUpButton) {
                popUpButton.removeAllItems();
                popUpButton.addItem(withTitle: "");
                popUpButton.addItems(withTitles: [NSLocalizedString("Owner", comment: "popup item"), NSLocalizedString("Admin", comment: "popup item"), NSLocalizedString("Member", comment: "popup item"), NSLocalizedString("Outcast", comment: "popup item")]);
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
            return a1.jid.description.compare(a2.jid.description) == .orderedAscending
        });
        let searchString = self.searchField.stringValue;
        if !searchString.isEmpty {
            self.visibleAffiliations = self.affiliations.filter({ (item) -> Bool in
                return item.jid.description.contains(searchString);
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
        alert.messageText = NSLocalizedString("Add member", comment: "alert window title");
        alert.informativeText = NSLocalizedString("Please provide user JID and affiliation to this room.", comment: "alert window message");
        
        alert.addButton(withTitle: NSLocalizedString("Add", comment: "Button"));
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 54));
        view.orientation = .vertical;
        
        let jidField = NSTextField(string: "");
        jidField.placeholderString = NSLocalizedString("Enter JID", comment: "add member entry field placeholder");
        jidField.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.addView(jidField, in: .bottom);
        
        let popUpButton = NSPopUpButton(frame: NSRect(x: 0, y:0, width: 200, height: 21), pullsDown: true);
        popUpButton.autoenablesItems = true;
        popUpButton.addItem(withTitle: "");
        popUpButton.addItems(withTitles: [NSLocalizedString("Owner", comment: "popup item"), NSLocalizedString("Admin", comment: "popup item"), NSLocalizedString("Member", comment: "popup item"), NSLocalizedString("Outcast", comment: "popup item")]);
        popUpButton.selectItem(at: 3);
        popUpButton.title = popUpButton.titleOfSelectedItem ?? "";
        popUpButton.tag = -1;
        popUpButton.action = #selector(affiliationChangedForRow(_:));
        popUpButton.target = self;
        let label = NSTextField(labelWithString: NSLocalizedString("Affiliation", comment: "add member view field label") + ":");
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
        
        guard let mucModule = room.context?.module(.muc) else {
            return;
        }
        
        self.progressIndicator.startAnimation(nil);
        
        Task {
            do {
                _ = try await mucModule.roomAffiliations(changes, to: room);
            } catch {
                await MainActor.run(body: {
                    let alert = NSAlert();
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                    alert.informativeText = ((error as? XMPPError)?.condition == .forbidden) ? NSLocalizedString("You are not allowed to modify list of affiliations for this room.", comment: "alert window message") : String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "alert window message"), error.localizedDescription);
                    _ = alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(nil);
            })
        }
    }
    
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
}
