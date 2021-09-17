//
// BlockedViewController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class BlockedViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    @IBOutlet var searchField: NSSearchField!
    @IBOutlet var tableView: NSTableView!
    @IBOutlet var unblockButton: NSButton!
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var items: [Item] = [];
    var allItems: [Item] = [];
    
    override func viewWillAppear() {
        super.viewWillAppear();
        let clients = XmppService.instance.clients.values.filter({ (client) -> Bool in
            return client.state == .connected();
        });
        var items: [Item] = [];
        if !clients.isEmpty {
            self.progressIndicator.startAnimation(nil);
            let group = DispatchGroup();
            for client in clients {
                group.enter();
                DispatchQueue.global().async {
                    let account = client.userBareJid;
                    client.module(.blockingCommand).retrieveBlockedJids(completionHandler: { result in
                        DispatchQueue.main.async {
                            switch result {
                            case .success(let jids):
                                items.append(contentsOf: jids.map({ jid -> Item in
                                    return Item(account: account, jid: jid);
                                }));
                            case .failure(_):
                                break;
                            }
                        }
                        group.leave();
                    });
                }
            }
            group.notify(queue: DispatchQueue.main, execute: {
                self.allItems = items.sorted();
                self.updateItems();
                self.progressIndicator.stopAnimation(nil);
            })
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = items[row];
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "BlockedTableCellView"), owner: self) as? BlockedTableCellView else {
            return nil;
        }
        view.update(with: item);
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        unblockButton.isEnabled = !tableView.selectedRowIndexes.isEmpty;
    }
    
    @IBAction func updateFilter(_ sender: NSSearchField) {
        updateItems();
    }
    
    func updateItems() {
        let val = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased();
        self.items = self.allItems.filter({ it in
            return val.isEmpty || it.jid.stringValue.lowercased().contains(val) || it.account.stringValue.lowercased().contains(val);
        });
        tableView.reloadData();
    }
    
    @IBAction func unblockClicked(_ sender: Any) {
        let selected = tableView.selectedRowIndexes.map { (row) -> Item in
            return self.items[row];
        };
        guard !selected.isEmpty else {
            return;
        }
        
        progressIndicator.startAnimation(nil);
        
        let group = DispatchGroup();
        
        let map = Dictionary(grouping: selected, by: { $0.account });
        map.forEach { (entry) in
            guard let blockingModule: BlockingCommandModule = XmppService.instance.getClient(for: entry.key)?.module(.blockingCommand) else {
                return;
            }
            group.enter()
            blockingModule.unblock(jids: entry.value.map({ (it) -> JID in
                return it.jid;
            }), completionHandler: { result in
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        let indexes = entry.value.map { it -> Int in
                            return self.items.firstIndex { (it2) -> Bool in
                                return it2 == it;
                                }!;
                        }
                        self.allItems.removeAll(where: { it -> Bool in
                            return entry.value.contains(it);
                        })
                        self.items.removeAll(where: { it -> Bool in
                            return entry.value.contains(it);
                        })
                        self.tableView.removeRows(at: IndexSet(indexes), withAnimation: .effectFade);
                    }
                case .failure(_):
                    break;
                }
                group.leave();
            });
        }
        
        group.notify(queue: DispatchQueue.main, execute: { [weak self] in
            self?.progressIndicator.stopAnimation(nil);
        })
    }
    
    
    struct Item: Equatable, Comparable {
        static func < (i1: BlockedViewController.Item, i2: BlockedViewController.Item) -> Bool {
            switch i1.jid.stringValue.compare(i2.jid.stringValue) {
            case.orderedAscending:
                return true;
            case .orderedDescending:
                return false;
            case .orderedSame:
                return i1.account.stringValue.compare(i2.account.stringValue) == .orderedAscending;
            }
        }
        
        let account: BareJID;
        let jid: JID;
    }
    
}

class BlockedTableCellView: NSTableCellView {
    
    @IBOutlet var jidLabel: NSTextField!
    @IBOutlet var accountLabel: NSTextField!
    
    func update(with item: BlockedViewController.Item) {
        jidLabel.stringValue = item.jid.stringValue;
        accountLabel.stringValue = String.localizedStringWithFormat(NSLocalizedString("using %@", comment: "settings"), item.account.stringValue);
    }
}
