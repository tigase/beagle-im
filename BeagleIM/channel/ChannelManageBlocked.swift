//
// ChannelManageBlocked.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift

class ChannelManageBlocked: NSViewController, NSTableViewDelegate, NSTableViewDataSource, ChannelAwareProtocol {
    
    @IBOutlet var tableView: NSTableView!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var channel: Channel!;
    
    private var banned: [BareJID] = [];
    private var actionInProgress: Bool = false {
        didSet {
            if actionInProgress {
                progressIndicator.startAnimation(self);
            } else {
                progressIndicator.stopAnimation(self);
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        if let mixModule = channel.context?.module(.mix) {
            actionInProgress = true;
            mixModule.retrieveBanned(for: channel.channelJid, completionHandler: { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let banned):
                            self.actionInProgress = false;
                            self.banned = banned.sorted(by: { $0.stringValue < $1.stringValue });
                            self.tableView?.reloadData();
                    case .failure(let errorCondition):
                            self.actionInProgress = false;
                    }
                }
            });
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return banned.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if tableColumn?.identifier.rawValue == "BlockedDeleteTableColumn" {
            let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "BlockedDeleteColumn"), owner: nil) as? NSTableCellView;
            return view;
        }
    
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "BlockedJidColumn"), owner: nil) as? NSTableCellView;
        view?.textField?.stringValue = banned[row].stringValue;
        return view;
    }
    
    @IBAction func addBlockedClicked(_ sender: NSButton) {
        guard !actionInProgress else {
            return;
        }
        askForJid(title: NSLocalizedString("Ban access", comment: "alert windiw title"), completionHandler: { jid in
            if let mixModule = self.channel.context?.module(.mix) {
                self.actionInProgress = true;
                mixModule.denyAccess(to: self.channel.channelJid, for: jid, value: true, completionHandler: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(_):
                            var banned = self.banned;
                            if !banned.contains(jid) {
                                banned.append(jid);
                                self.banned = banned.sorted(by: { $0.stringValue < $1.stringValue });
                                self.tableView?.insertRows(at: IndexSet(integer: self.banned.firstIndex(of: jid) ?? 0), withAnimation: .effectFade);
                            }
                        case .failure(_):
                            break;
                        }
                        self.actionInProgress = false;
                    }
                })
            }
        })
    }
    
    @IBAction func deleteClicked(_ sender: NSButton) {
        guard !actionInProgress else {
            return;
        }
        
        let row = tableView.row(for: sender);
        if row >= 0 {
            let item = banned[row];
            if let mixModule = self.channel.context?.module(.mix) {
                actionInProgress = true;
                mixModule.denyAccess(to: channel.channelJid, for: item, value: false, completionHandler: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(_):
                            self.banned.remove(at: row);
                            self.tableView?.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade);
                        case .failure(_):
                            break;
                        }
                        self.actionInProgress = false;
                    }
                })
            }
        }
    }
    
    private func askForJid(title: String, completionHandler: @escaping (BareJID)->Void) {
        let alert = NSAlert();
        alert.alertStyle = .informational;
        alert.icon = NSImage(named: NSImage.userName);
        alert.messageText = title;
        alert.informativeText = NSLocalizedString("Enter a JID of user you want to ban.", comment: "alert window message");
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 7 + NSFont.systemFontSize));
        alert.accessoryView = field;
        alert.addButton(withTitle: NSLocalizedString("Ban", comment: "Button"));
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
    
}
