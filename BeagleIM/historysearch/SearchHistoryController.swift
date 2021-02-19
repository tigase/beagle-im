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
    @IBOutlet var goToButton: NSButton!;
    
    var items: [ConversationEntry] = [] {
        didSet {
            self.tableView.reloadData();
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        // FIXME: THIS IS NO LONGER TRUE
        let item = self.items[row] as! ConversationMessage;
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageCellView"), owner: self) as? ChatMessageCellView else {
            return nil;
        }
        view.id = item.id;
        
//        view.set(avatar: item.avatar);
//        view.set(senderName: item.nickname);
        
        view.set(message: item);

        view.message.isSelectable = false;
        view.message.isEditable = false;

        return view;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        goToButton.isEnabled = tableView.selectedRow >= 0;
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return TableRowView();
    }
    
    @IBAction func search(_ sender: Any) {
        goToButton.isEnabled = false;
        guard !searchField.stringValue.isEmpty else {
            return;
        }
        DBChatHistoryStore.instance.searchHistory(search: searchField.stringValue) { (items) in
            DispatchQueue.main.async {
                self.items = items.filter({ it -> Bool in it is ConversationMessage });
            }
        }
    }
    
    @IBAction func goToChatClicked(_ sender: Any) {
        openChat(forRow: tableView.selectedRow);
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        self.view.window?.sheetParent?.endSheet(self.view.window!)
    }
    
    @IBAction func openInChat(_ sender: Any) {
        let row = self.tableView.clickedRow;
        openChat(forRow: row);
    }
    
    func openChat(forRow row: Int) {
        guard row < items.count else {
            return;
        }
        let item = items[row];

        guard let client = XmppService.instance.getClient(for: item.conversation.account) else {
            let alert = NSAlert();
            alert.messageText = "Account is disabled";
            alert.informativeText = "It is not possible to open a chat when the account related to the chat is disabled!";
            alert.addButton(withTitle: "OK");
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
            return;
        }

        if DBChatStore.instance.conversation(for: item.conversation.account, with: item.conversation.jid) == nil {
            _ = client.module(.message).chatManager.createChat(for: client, with: item.conversation.jid);
        }

        self.view.window?.sheetParent?.endSheet(self.view.window!)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: nil, userInfo: ["account": item.conversation.account, "jid": item.conversation.jid, "messageId": item.id]);
        }
    }
    
    fileprivate func buddyName(for item: ConversationMessage) -> String {
        return item.nickname;
    }
    
    class TableRowView: NSTableRowView {
        
        override var isEmphasized: Bool {
            didSet {
                for view in subviews {
                    if let cell = view as? ChatMessageSelectableCellView {
                        cell.isEmphasized = isEmphasized;
                    }
                }
            }
        }
        
        override var isSelected: Bool {
            didSet {
                for view in subviews {
                    if let cell = view as? ChatMessageSelectableCellView {
                        cell.isSelected = isSelected;
                    }
                }
            }
        }
        
    }
 }
