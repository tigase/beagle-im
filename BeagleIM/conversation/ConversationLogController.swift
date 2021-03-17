//
// ConversationLogController.swift
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

class ConversationLogController: AbstractConversationLogController, NSTableViewDelegate {
    
    weak var contextMenuDelegate: ConversationLogContextMenuDelegate?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        if #available(macOS 11.0, *) {
            self.tableView.style = .fullWidth;
        }
        self.tableView.delegate = self;
    }
    
    override func prepareContextMenu(_ menu: NSMenu, forRow row: Int) {
        super.prepareContextMenu(menu, forRow: row);
        self.contextMenuDelegate?.prepareConversationLogContextMenu(dataSource: self.dataSource, menu: menu, forRow: row);
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = dataSource.getItem(at: row) else {
            return nil;
        }
        
        let prevItem = row >= 0 && (row + 1) < dataSource.count ? dataSource.getItem(at: row + 1) : nil;
        let continuation = prevItem != nil && item.isMergeable(with: prevItem!);

        switch item {
        case is ConversationMessageSystem:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageSystemCellView"), owner: nil) as? ChatMessageSystemCellView {
                cell.message.attributedString = NSAttributedString(string: "Unread messages", attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]);
                return cell;
            }
            return nil;
        case let item as ConversationMessageRetracted:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                cell.id = item.id;
                cell.set(retraction: item);

                return cell;
            }
            return nil;
        case let item as ConversationMessage:
            if item.message.starts(with: "/me ") {
                if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMeSystemCellView"), owner: nil) as? ChatMeMessageCellView {
                    cell.set(item: item);
                    return cell;
                }
                return nil;
            } else {
                if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                    cell.id = item.id;
                    cell.set(message: item);

                    return cell;
                }
                return nil;
            }
        case let item as ConversationLinkPreview:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatLinkPreviewCellView"), owner: nil) as? ChatLinkPreviewCellView {
                cell.set(item: item);
                return cell;
            }
            return nil;
        case let item as ConversationAttachment:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatAttachmentContinuationCellView" : "ChatAttachmentCellView"), owner: nil) as? ChatAttachmentCellView {
                cell.set(item: item);
                return cell;
            }
            return nil;
        case let item as ConversationInvitation:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatInvitationCellView"), owner: nil) as? ChatInvitationCellView {
                cell.set(invitation: item);
                return cell;
            }
            return nil;
        case let item as ConversationMarker:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMarkerCellView"), owner: nil) as? ChatMarkerCellView {
                cell.set(marker: item);
                return cell;
            }
            return nil;
        default:
            return nil;
        }
    }
}

class ConversationMarker: ConversationEntry, ConversationEntryRelated {
    
    let sender: ConversationEntrySender;
    let order: ConversationEntry.Order = .last;
    let marker: ChatMarker.MarkerType;
    
    init(markedMessageId: Int, conversationKey: ConversationKey, timestamp: Date, sender: ConversationEntrySender, marker: ChatMarker.MarkerType) {
        self.sender = sender;
        self.marker = marker;
        super.init(id: markedMessageId, conversation: conversationKey, timestamp: timestamp);
    }
    
    override func isEqual(entry: ConversationEntry) -> Bool {
        guard let e = entry as? ConversationMarker else {
            return false;
        }
        return e.marker == marker;
    }
    
    override func hash(into hasher: inout Hasher) {
        hasher.combine(marker);
    }
}

protocol ConversationLogContextMenuDelegate: class {
    
    func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int);
    
}
