//
// SearchHistoryController.swift
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

class SearchHistoryController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
 
    @IBOutlet var searchField: NSSearchField!
    @IBOutlet var tableView: NSTableView!;
    
    var items: [ChatViewItemProtocol] = [] {
        didSet {
            self.tableView.reloadData();
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let item = self.items[row] as! ChatMessage;
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageCellView"), owner: self) as? ChatMessageCellView else {
            return nil;
        }
        view.id = item.id;
        
        let senderJid = item.state.direction == .incoming ? (item.authorJid ?? item.jid) : item.account;
        
        view.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
        view.set(senderName: item.authorNickname ?? (item.state.direction == .incoming ? self.buddyName(for: item) : "Me"));
        
        view.set(message: item);

        view.message.isSelectable = false;
        view.message.isEditable = false;

        return view;
    }
    
    @IBAction func search(_ sender: Any) {
        guard !searchField.stringValue.isEmpty else {
            return;
        }
        DBChatHistoryStore.instance.searchHistory(search: searchField.stringValue) { (items) in
            DispatchQueue.main.async {
                self.items = items;
            }
        }
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        self.view.window?.sheetParent?.endSheet(self.view.window!)
    }
    
    @IBAction func openInChat(_ sender: Any) {
        let row = self.tableView.clickedRow;
        guard row < items.count else {
            return;
        }
        let item = items[row];

        guard let client = XmppService.instance.getClient(for: item.account) else {
            let alert = NSAlert();
            alert.messageText = "Account is disabled";
            alert.informativeText = "It is not possible to open a chat when the account related to the chat is disabled!";
            alert.addButton(withTitle: "OK");
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
            return;
        }

        if DBChatStore.instance.getChat(for: item.account, with: item.jid) == nil {
            if let messageModule: MessageModule = client.modulesManager.getModule(MessageModule.ID) {
                _ = messageModule.chatManager.createChat(with: JID(item.jid), thread: nil);
            }
        }

        self.view.window?.sheetParent?.endSheet(self.view.window!)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: nil, userInfo: ["account": item.account, "jid": item.jid, "messageId": item.id]);
        }
    }
    
    fileprivate func buddyName(for item: ChatMessage) -> String {
        if let sessionObject = XmppService.instance.getClient(for: item.account)?.sessionObject {
            return RosterModule.getRosterStore(sessionObject).get(for: JID(item.jid))?.name ?? item.jid.stringValue;
        } else {
            return item.jid.stringValue;
        }
    }
 }
