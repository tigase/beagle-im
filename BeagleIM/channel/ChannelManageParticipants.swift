//
// ChannelManageParticipants.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

// TODO: Remove this controller. It should not be needed in the future.
@available(*, unavailable)
class ChannelManagerParticipants: NSViewController, ChannelAwareProtocol, NSTabViewDelegate, NSTableViewDelegate, NSTableViewDataSource {
    
    @IBOutlet var tabView: NSTabView!;
    @IBOutlet var allowedTableView: NSTableView?;
    @IBOutlet var bannedTableView: NSTableView?;
    @IBOutlet var progressIndicator: NSProgressIndicator!;

    @IBOutlet var allowedRemoveButton: NSButton?;
    @IBOutlet var blockedRemoveButton: NSButton!;
    
    var channel: Channel!;
    
    private var allowed: [BareJID]? = nil;
    private var banned: [BareJID] = [];
    
    override func viewWillAppear() {
        if let mixModule = channel.context?.module(.mix) {
            progressIndicator.startAnimation(self);
            let group = DispatchGroup();
            group.enter();
            mixModule.retrieveBanned(for: channel.channelJid, completionHandler: { result in
                switch result {
                case .success(let banned):
                    DispatchQueue.main.async {
                        self.banned = banned.sorted(by: { $0.stringValue < $1.stringValue });
                        self.bannedTableView?.reloadData();
                    }
                case .failure(let errorCondition):
                    if errorCondition != .item_not_found {
                        DispatchQueue.main.async {
                            // show alert..
                        }
                    }
                }
                group.leave();
            });
            group.enter();
            mixModule.retrieveAllowed(for: channel.channelJid, completionHandler: { result in
                switch result {
                case .success(let allowed):
                    DispatchQueue.main.async {
                        self.allowed = allowed.sorted(by: { $0.stringValue < $1.stringValue });
                        self.allowedTableView?.reloadData();
                    }
                case .failure(_):
                    DispatchQueue.main.async {
                        self.tabView.removeTabViewItem(self.tabView.tabViewItem(at: 0));
                    }
                }
                group.leave();
            });
            group.notify(queue: DispatchQueue.main, execute: {
                self.progressIndicator.stopAnimation(self);
            });
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        switch tableView {
        case allowedTableView:
            return allowed?.count ?? 0;
        case bannedTableView:
            return banned.count;
        default:
            return 0;
        }
    }
    
    func item(tableView: NSTableView, row: Int) -> BareJID {
        switch tableView {
        case allowedTableView:
            return allowed![row];
        case bannedTableView:
            return banned[row];
        default:
            return BareJID("ERROR");
        }
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = self.item(tableView: tableView, row: row);
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ManageBannedParticipantsTableCellView"), owner: nil) as? NSTableCellView;
        view?.textField?.stringValue = item.stringValue;
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        allowedRemoveButton?.isEnabled = (allowedTableView?.selectedRow ?? -1) >= 0;
        blockedRemoveButton.isEnabled = (bannedTableView?.selectedRow ?? -1) >= 0;
    }
    
    func tabView(_ tabView: NSTabView, shouldSelect tabViewItem: NSTabViewItem?) -> Bool {
        if (tabViewItem?.identifier as? String) == "ParticipantsAllowedTab" && self.allowed == nil {
            return false;
        }
        return true;
    }
    
    private func askForJid(title: String, completionHandler: @escaping (BareJID)->Void) {
        let alert = NSAlert();
        alert.alertStyle = .informational;
        alert.icon = NSImage(named: NSImage.userName);
        alert.messageText = title;
        alert.informativeText = NSLocalizedString("Enter a JID of user you want to add to the list.", comment: "alert window message");
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 7 + NSFont.systemFontSize));
        alert.accessoryView = field;
        alert.addButton(withTitle: NSLocalizedString("Add", comment: "Button"));
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
            switch response {
            case .alertFirstButtonReturn:
                let string = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
                guard !string.isEmpty else {
                    return;
                }
                completionHandler(BareJID(string));
            default:
                break;
            }
        })
    }
    
    @IBAction func addAllowedClicked(_ sender: NSButton) {
        askForJid(title: NSLocalizedString("Allow access", comment: "alert window title"), completionHandler: { jid in
            if let mixModule = self.channel.context?.module(.mix) {
                self.progressIndicator.startAnimation(self);
                mixModule.allowAccess(to: self.channel.channelJid, for: jid, value: true, completionHandler: { result in
                    switch result {
                    case .success(_):
                        DispatchQueue.main.async {
                            guard var allowed = self.allowed, !allowed.contains(jid) else {
                                return;
                            }
                            allowed.append(jid);
                            self.allowed = allowed.sorted(by: { $0.stringValue < $1.stringValue });
                            self.allowedTableView?.insertRows(at: IndexSet(integer: self.allowed?.firstIndex(of: jid) ?? 0), withAnimation: .effectFade);
                        }
                    case .failure(_):
                        break;
                    }
                    DispatchQueue.main.async {
                        self.progressIndicator.stopAnimation(self);
                    }
                })
            }
        })
    }
    
    @IBAction func removeAllowedClicked(_ sender: NSButton) {
        let row = allowedTableView?.selectedRow ?? -1;
        guard row >= 0, let item = allowed?[row] else {
            return;
        }
        if let mixModule = self.channel.context?.module(.mix) {
            progressIndicator.startAnimation(self);
            mixModule.allowAccess(to: channel.channelJid, for: item, value: false, completionHandler: { result in
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        self.allowed = self.allowed?.filter({ $0 != item });
                        self.allowedTableView?.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade);
                    }
                case .failure(_):
                    break;
                }
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(self);
                }
            })
        }
    }
    
    @IBAction func addBannedClicked(_ sender: NSButton) {
        askForJid(title: NSLocalizedString("Ban access", comment: "alert windiw title"), completionHandler: { jid in
            if let mixModule = self.channel.context?.module(.mix) {
                self.progressIndicator.startAnimation(self);
                mixModule.denyAccess(to: self.channel.channelJid, for: jid, value: true, completionHandler: { result in
                    switch result {
                    case .success(_):
                        DispatchQueue.main.async {
                            var banned = self.banned;
                            guard !banned.contains(jid) else {
                                return;
                            }
                            banned.append(jid);
                            self.banned = banned.sorted(by: { $0.stringValue < $1.stringValue });
                            self.bannedTableView?.insertRows(at: IndexSet(integer: self.banned.firstIndex(of: jid) ?? 0), withAnimation: .effectFade);
                        }
                    case .failure(_):
                        break;
                    }
                    DispatchQueue.main.async {
                        self.progressIndicator.stopAnimation(self);
                    }
                })
            }
        })
    }
    
    @IBAction func removeBannedClicked(_ sender: NSButton) {
        let row = bannedTableView?.selectedRow ?? -1;
        guard row >= 0 else {
            return;
        }
        let item = banned[row];
        if let mixModule = self.channel.context?.module(.mix) {
            progressIndicator.startAnimation(self);
            mixModule.denyAccess(to: channel.channelJid, for: item, value: false, completionHandler: { result in
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        self.banned = self.banned.filter({ $0 != item });
                        self.bannedTableView?.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade);
                    }
                case .failure(_):
                    break;
                }
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(self);
                }
            })
        }
    }
}
