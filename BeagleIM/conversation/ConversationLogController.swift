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
    
    private func getPreviousEntry(before row: Int) -> ConversationEntry? {
        guard row >= 0 && (row + 1) < dataSource.count else {
            return nil;
        }
        return dataSource.getItem(at: row + 1);
    }
    
    private func isContinuation(at row: Int, for entry: ConversationEntry) -> Bool {
        guard let prevEntry = getPreviousEntry(before: row) else {
            return false;
        }
        switch prevEntry.payload {
        case .messageRetracted, .message(_, _), .attachment(_, _):
            return entry.isMergeable(with: prevEntry);
        case .marker(_, _), .linkPreview(_):
            return isContinuation(at: row + 1, for: entry);
        default:
            return false;
        }
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = dataSource.getItem(at: row) else {
            return nil;
        }

        switch item.payload {
        case .unreadMessages:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageSystemCellView"), owner: nil) as? ChatMessageSystemCellView {
                cell.message.attributedString = NSAttributedString(string: "Unread messages", attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]);
                return cell;
            }
            return nil;
        case .messageRetracted:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: isContinuation(at: row, for: item) ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                cell.id = item.id;
                cell.setRetracted(item: item);

                return cell;
            }
            return nil;
        case .message(let message, let correctionTimestamp):
            if message.starts(with: "/me ") {
                if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMeSystemCellView"), owner: nil) as? ChatMeMessageCellView {
                    cell.set(item: item, message: message);
                    return cell;
                }
                return nil;
            } else {
                if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: isContinuation(at: row, for: item) ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                    cell.id = item.id;
                    cell.set(item: item, message: message, correctionTimestamp: correctionTimestamp);

                    return cell;
                }
                return nil;
            }
        case .linkPreview(let url):
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatLinkPreviewCellView"), owner: nil) as? ChatLinkPreviewCellView {
                cell.set(item: item, url: url);
                return cell;
            }
            return nil;
        case .attachment(let url, let appendix):
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: isContinuation(at: row, for: item) ? "ChatAttachmentContinuationCellView" : "ChatAttachmentCellView"), owner: nil) as? ChatAttachmentCellView {
                cell.set(item: item, url: url, appendix: appendix);
                return cell;
            }
            return nil;
        case .invitation(let message, let appendix):
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatInvitationCellView"), owner: nil) as? ChatInvitationCellView {
                cell.set(item: item, message: message, appendix: appendix);
                return cell;
            }
            return nil;
        case .marker(let type, let senders):
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMarkerCellView"), owner: nil) as? ChatMarkerCellView {
                cell.set(item: item, type: type, senders: senders);
                return cell;
            }
            return nil;
        default:
            return nil;
        }
    }
}

protocol ConversationLogContextMenuDelegate: AnyObject {
    
    func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int);
    
}
