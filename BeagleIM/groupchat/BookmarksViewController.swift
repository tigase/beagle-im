//
// BookmarksViewController.swift
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
import Combine

class BookmarksViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {

    @IBOutlet var tableView: NSTableView!;
    @IBOutlet var joinButton: NSButton!;
    
    var items: [Item] = [] {
        didSet {
            tableView.reloadData();
        }
    }
    private var clientCancellable: AnyCancellable?;
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        let menu = NSMenu();
        menu.delegate = self;
        tableView.menu = menu;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        clientCancellable =  XmppService.instance.$connectedClients.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] clients in
            guard let that = self else {
                return;
            }
            
            that.cancellables.removeAll();
            that.items = [];
            
            for client in clients {
                let account = client.userBareJid;
                client.module(.pepBookmarks).$currentBookmarks.receive(on: DispatchQueue.main).sink(receiveValue: { bookmarks in
                    guard let that = self else {
                        return;
                    }
                    that.items = (that.items.filter({ $0.account != account }) + bookmarks.items.compactMap({ $0 as? Bookmarks.Conference }).map({ Item(account: account, conference: $0) })).sorted(by: { b1, b2 in b1.displayName.lowercased() < b2.displayName.lowercased() });
                    }).store(in: &that.cancellables)
            }
        });
    }
    
    override func viewDidDisappear() {
        clientCancellable = nil;
        cancellables.removeAll();
        items.removeAll();
        super.viewDidDisappear();
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "BookmarkTableViewCell"), owner: nil) as? BookmarkTableViewCell else {
            return nil;
        }
        view.item = items[row];
        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        self.joinButton.isEnabled = tableView.selectedRow >= 0 && tableView.selectedRow < items.count;
    }
    
    @IBAction func cancelClicked(_ sender: Any) {
        self.view.window?.close();
    }
    
    @IBAction func joinClicked(_ sender: Any) {
        let item = items[tableView.selectedRow];
        
        guard let conversation = DBChatStore.instance.conversation(for: item.account, with: item.conference.jid.bareJid) else {
            guard let controller = NSStoryboard(name: "MIX", bundle: nil).instantiateController(withIdentifier: "EnterChannelViewController") as? EnterChannelViewController else {
                return;
            }
            
            _ = controller.view;
            controller.account = item.account;
            controller.channelJid = item.conference.jid.bareJid;
            controller.channelName = item.conference.name;
            controller.componentType = .muc;
            controller.suggestedNickname = item.conference.nick;
            controller.password = item.conference.password;
            controller.isPasswordVisible = true;
            controller.isBookmarkVisible = false;
            
            let windowController = NSWindowController(window: NSWindow(contentViewController: controller));
            self.view.window?.beginSheet(windowController.window!, completionHandler: { result in
                switch result {
                case .OK:
                    self.view.window?.close();
                default:
                    break;
                }
            });
            return;
        }
        
        NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: conversation);
        self.view.window?.close();
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.removeAll();

        let item = items[tableView.clickedRow];
        if item.conference.autojoin {
            menu.addItem(withTitle: NSLocalizedString("Disable autojoin", comment: "menu item label"), action: #selector(disableAutojoin(_:)), keyEquivalent: "");
        } else {
            menu.addItem(withTitle: NSLocalizedString("Enable autojoin", comment: "menu item label"), action: #selector(enableAutojoin(_:)), keyEquivalent: "");
        }
        menu.addItem(withTitle: NSLocalizedString("Delete", comment: "menu item label"), action: #selector(removeBookmark(_:)), keyEquivalent: "");
    }
    
    @objc func removeBookmark(_ sender: Any) {
        guard tableView.clickedRow >= 0 else {
            return;
        }
        
        let item = items[tableView.clickedRow];

        guard let client = XmppService.instance.getClient(for: item.account) else {
            return;
        }
        
        Task {
            try await client.module(.pepBookmarks).remove(bookmark: item.conference);
        }
    }
    
    @objc func enableAutojoin(_ sender: Any) {
        guard tableView.clickedRow >= 0 else {
            return;
        }
        
        let item = items[tableView.clickedRow];
        
        guard let client = XmppService.instance.getClient(for: item.account) else {
            return;
        }
        
        Task {
            try await client.module(.pepBookmarks).addOrUpdate(bookmark: item.conference.with(autojoin: true));
        }
    }
    
    @objc func disableAutojoin(_ sender: Any) {
        guard tableView.clickedRow >= 0 else {
            return;
        }
        
        let item = items[tableView.clickedRow];
        
        guard let client = XmppService.instance.getClient(for: item.account) else {
            return;
        }
        
        Task {
            try await client.module(.pepBookmarks).addOrUpdate(bookmark: item.conference.with(autojoin: false));
        }
    }
    
    struct Item {
        
        var account: BareJID;
        var conference: Bookmarks.Conference;
     
        var displayName: String {
            return conference.name ?? conference.jid.localPart ?? conference.jid.description;
        }
    }
}

class BookmarkTableViewCell: NSTableCellView {
    
    @IBOutlet var avatar: AvatarView!;
    @IBOutlet var nameLabel: NSTextField!;
    @IBOutlet var jidLabel: NSTextField!;
    
    var item: BookmarksViewController.Item? {
        didSet {
            avatar.avatar = (item != nil ? AvatarManager.instance.avatar(for: item!.conference.jid.bareJid, on: item!.account) : nil) ?? AvatarManager.instance.defaultGroupchatAvatar;
            nameLabel.stringValue = item?.displayName ?? "";
            jidLabel.stringValue = item?.conference.jid.description ?? "";
        }
    }
    
}
