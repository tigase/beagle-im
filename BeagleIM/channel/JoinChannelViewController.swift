//
// JoinChannelViewController.swift
//
// BeagleIM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import AppKit
import Martin

class JoinChannelViewController: BaseJoinChannelViewController, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {

    @IBOutlet var channelsTableView: NSTableView!;
    @IBOutlet var channelNameField: NSTextField!;

    override var components: [BaseJoinChannelViewController.Component] {
        didSet {
            refreshRooms();
        }
    }
    private var allItems: [DiscoveryModule.Item] = [] {
        didSet {
            updateItems();
        }
    }
    private var items: [DiscoveryModule.Item] = [] {
        didSet {
            channelsTableView.reloadData();
        }
    }
    var nickname: String?;
    var password: String?;
    private var remoteQuery: String? = nil;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        refreshRooms();
    }

    override func canSubmit() -> Bool {
        return super.canSubmit() && channelsTableView.selectedRow >= 0;
    }
    
    override func submitClicked(_ sender: NSButton) {
        if channelsTableView.selectedRow >= 0, let account = self.account, let window = self.view.window {
            let item = self.items[channelsTableView.selectedRow];
            
            guard let component = self.components.first(where: { $0.jid.domain == item.jid.domain }), let account = self.account else {
                return;
            }

            guard let controller = NSStoryboard(name: "MIX", bundle: nil).instantiateController(withIdentifier: "EnterChannelViewController") as? EnterChannelViewController else {
                return;
            }
            
            _ = controller.view;
            controller.account = account;
            controller.channelJid = item.jid.bareJid;
            controller.channelName = item.name;
            controller.componentType = component.type;
            controller.suggestedNickname = nickname;
            controller.password = password;
            controller.isPasswordVisible = password == nil;
            
            let windowController = NSWindowController(window: NSWindow(contentViewController: controller));
            window.beginSheet(windowController.window!, completionHandler: { result in
                switch result {
                case .OK, .abort:
                    self.close();
                default:
                    break;
                }
            });
        }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else {
            return;
        }
        
        switch field {
        case channelNameField:
            updateItems();
            self.remoteQuery = field.stringValue;
            if self.remoteQuery?.isEmpty ?? false {
                self.remoteQuery = nil;
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: { [weak self, weak field] in
                guard let that = self, let remoteQuery = that.remoteQuery, let account = that.account, let field = field, !field.stringValue.isEmpty, remoteQuery == field.stringValue else {
                    return;
                }
                that.remoteQuery = nil;
                let text = field.stringValue;
                guard let client = XmppService.instance.getClient(for: account) else {
                    return;
                }

                var allItems: [DiscoveryModule.Item] = [];
                let group = DispatchGroup();
                for component in that.components {
                    group.enter();
                    let channelJid = JID(BareJID(localPart: text, domain: component.jid.domain));
                    client.module(.disco).info(for: channelJid, node: nil, completionHandler: { result in
                         switch result {
                         case .success(let info):
                             DispatchQueue.main.async {
                                allItems.append(DiscoveryModule.Item(jid: channelJid, name: info.identities.first?.name));
                             }
                         case .failure(_):
                             break;
                         }
                         group.leave();
                     });
                }
                group.notify(queue: DispatchQueue.main, execute: {
                    DispatchQueue.main.async {
                        guard let that = self else {
                            return;
                        }
                        var changed = false;
                        for item in allItems {
                            if that.allItems.first(where: { $0.jid == item.jid }) == nil {
                                that.allItems.append(item);
                                changed = true;
                            }
                        }
                        if changed {
                            that.updateItems();
                        }
                    }
                })
            });

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
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        updateSubmitState();
    }

    private func updateItems() {
        let val = channelNameField.stringValue;
        if val.isEmpty {
            self.items = allItems;
        } else {
            if val.contains("@") {
                self.items = allItems.filter({ (item) -> Bool in
                    return (item.name ?? "").contains(val) || item.jid.description.contains(val);
                });
            } else {
                self.items = allItems.filter({ (item) -> Bool in
                    return (item.name ?? "").contains(val) || (item.jid.localPart ?? "").contains(val);
                });
            }
            if let idx = self.items.firstIndex(where: { val == $0.jid.localPart }) {
                self.channelsTableView.selectRowIndexes(IndexSet(integer: idx), byExtendingSelection: false);
            }
        }
    }
    
    private func refreshRooms() {
        guard let account = self.account else {
            self.allItems = [];
            return;
        }
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }

        var allItems = [DiscoveryModule.Item]();
        self.operationStarted();
        let group = DispatchGroup();
        group.enter();
        for component in components {
            group.enter();
            client.module(.disco).items(for: component.jid, completionHandler: { result in
                switch result {
                case .success(let items):
                    DispatchQueue.main.async {
                        allItems.append(contentsOf: items.items);
                    }
                case .failure(_):
                    break;
                }
                group.leave();
            });
        }
        group.leave();
        group.notify(queue: DispatchQueue.main, execute: {
            self.operationFinished();
            self.allItems = allItems;
        })
    }
}

class MucRoomView: NSTableCellView {
    
    @IBOutlet var label: NSTextField!;
    @IBOutlet var jidLabel: NSTextField!;
    
    func set(item: DiscoveryModule.Item) {
        label.stringValue = item.name ?? item.jid.localPart!;
        jidLabel.stringValue = item.jid.description;
    }
}
