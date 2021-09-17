//
// JoinChannelView.swift
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

class JoinChannelView: NSView, OpenChannelViewControllerTabView, NSTableViewDelegate, NSTableViewDataSource, NSTextFieldDelegate {

    @IBOutlet var channelsTableView: NSTableView!;
    @IBOutlet var channelNameField: NSTextField!;
    
    var account: BareJID?
    
    private var isVisible = false;
    private var refreshNeeded = false;
    var components: [OpenChannelViewController.Component] = [] {
        didSet {
            if isVisible {
                refreshRooms();
            } else {
                refreshNeeded = true;
            }
        }
    }
    
    var delegate: OpenChannelViewControllerTabViewDelegate?
    
    func viewWillAppear() {
        isVisible = true;
        delegate?.updateSubmitState();
        if refreshNeeded {
            refreshNeeded = false;
            refreshRooms();
        }
    }
    
    func viewDidDisappear() {
        isVisible = false;
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
    
    func canSubmit() -> Bool {
        return account != nil && channelsTableView.selectedRow >= 0;
    }
    
    func disclosureChanged(state: Bool) {
        // nothing to do.. for now
    }
    
    func cancelClicked(completionHandler: (() -> Void)?) {
        completionHandler?();
    }
    
    func submitClicked(completionHandler: ((Bool) -> Void)?) {
        if let delegate = self.delegate, channelsTableView.selectedRow >= 0 {
            let item = self.items[channelsTableView.selectedRow];
            delegate.askForNickname(completionHandler: { nickname in
                self.join(channel: item, nickname: nickname, password: nil, completionHandler: completionHandler!);
            })
        } else {
            completionHandler?(false);
        }
    }
    
    private func join(channel: DiscoveryModule.Item, nickname: String, password: String?, completionHandler: @escaping (Bool)->Void) {
        guard let component = self.components.first(where: { $0.jid.domain == channel.jid.domain }), let account = self.account else {
            completionHandler(false);
            return;
        }
        guard let client = XmppService.instance.getClient(for: account) else {
            completionHandler(false);
            return;
        }
        switch component.type {
        case .muc:
            client.module(.disco).getInfo(for: channel.jid, node: nil, completionHandler: { [weak self] result in
                switch result {
                case .success(let info):
                    if info.features.contains("muc_passwordprotected") && password == nil {
                        DispatchQueue.main.async {
                            guard let window = self?.window else {
                                return;
                            }
                            let alert = NSAlert();
                            alert.messageText = NSLocalizedString("Enter password for room", comment: "alert window title");
                            alert.informativeText = NSLocalizedString("This room is password protected. You need to provide correct password to join this room.", comment: "alert window message");
                            let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 21));
                            passwordField.setContentHuggingPriority(.defaultLow, for: .horizontal);
                            alert.accessoryView = passwordField;
                            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button")).tag = NSApplication.ModalResponse.OK.rawValue;
                            alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
                            alert.beginSheetModal(for: window, completionHandler: { (response) in
                                let password = passwordField.stringValue;
                                if password.isEmpty || response != .OK {
                                    completionHandler(false);
                                } else {
                                    self?.join(channel: channel, nickname: nickname, password: password, completionHandler: completionHandler);
                                }
                            })
                        }
                    } else {
                        let room = channel.jid;
                        let result = client.module(.muc).join(roomName: room.localPart!, mucServer: room.domain, nickname: nickname, password: password);
                        result.handle({ r in
                            switch r {
                            case .success(let roomResult):
                                switch roomResult {
                                case .created(let room), .joined(let room):
                                    (room as! Room).features = Set(info.features.compactMap({ Room.Feature(rawValue: $0) }));
                                }
                            case .failure(_):
                                break;
                            }
                        })
                        PEPBookmarksModule.updateOrAdd(for: account, bookmark: Bookmarks.Conference(name: room.localPart!, jid: JID(room), autojoin: true, nick: nickname, password: password));
                        DispatchQueue.main.async {
                            completionHandler(true);
                        }
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        guard let window = self?.window else {
                            return;
                        }
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Could not join", comment: "alert window title");
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a room. The server returned an error: %@", comment: "alert window message"), error.message ?? error.description);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: { (response) in
                            completionHandler(false);
                        });
                    }
                }
            });
        case .mix:
            client.module(.mix).join(channel: channel.jid.bareJid, withNick: nickname, completionHandler: { result in
                switch result {
                case .success(_):
                    if let channel = DBChatStore.instance.channel(for: client, with: channel.jid.bareJid) {
                        client.module(.disco).getItems(for: JID(channel.jid), completionHandler: { result in
                            switch result {
                            case .success(let info):
                                channel.updateOptions({ options in
                                    options.features = Set(info.items.compactMap({ $0.node }).compactMap({ Channel.Feature(rawValue: $0) }));
                                })
                            case .failure(_):
                                break;
                            }
                        });
                    }
                    // we have joined, so all what we need to do is close this window
                    DispatchQueue.main.async {
                        completionHandler(true);
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Could not join", comment: "alert window title");
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert window title"), error.message ?? error.description);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: self.window!, completionHandler: { (response) in
                            completionHandler(false);
                        });
                    }
                }
            });
        }
    }
    
    private var remoteQuery: String? = nil;
    
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
                    client.module(.disco).getInfo(for: channelJid, node: nil, completionHandler: { result in
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
        delegate?.updateSubmitState();
    }

    private func updateItems() {
        let val = channelNameField.stringValue;
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
    
    private func refreshRooms() {
        guard let account = self.account else {
            self.allItems = [];
            return;
        }
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }

        var allItems = [DiscoveryModule.Item]();
        self.delegate?.operationStarted();
        let group = DispatchGroup();
        group.enter();
        for component in components {
            group.enter();
            client.module(.disco).getItems(for: component.jid, completionHandler: { result in
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
            self.delegate?.operationFinished();
            self.allItems = allItems;
        })
    }
    
}
