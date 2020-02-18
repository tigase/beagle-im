//
// ChatMessageCellView.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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

class ChatMessageCellView: BaseChatMessageCellView {

    @IBOutlet var avatar: AvatarView!
    @IBOutlet var senderName: NSTextField!
    @IBOutlet var timestamp: NSTextField!
    
    func set(avatar: NSImage?) {
        self.avatar?.image = avatar;
    }
 
    func set(senderName: String, attributedSenderName: NSAttributedString? = nil) {
        if attributedSenderName == nil {
            self.senderName.stringValue = senderName;
        } else {
            self.senderName.attributedStringValue = attributedSenderName!;
        }
        self.avatar?.name = senderName;
    }
        
    override func set(message item: ChatMessage, nickname: String? = nil, keywords: [String]? = nil) {
        var timestampStr: NSMutableAttributedString? = nil;

        switch item.encryption {
        case .decrypted, .notForThisDevice, .decryptionFailed:
            let secured = NSMutableAttributedString(string: "\u{1F512}");
            if timestampStr != nil {
                timestampStr?.append(secured);
            } else {
                timestampStr = secured;
            }
        default:
            break;
        }
        
        if timestampStr != nil {
            timestampStr!.append(item.state == .outgoing_unsent ? NSAttributedString(string: " Unsent") : NSMutableAttributedString(string: " " + formatTimestamp(item.timestamp)));
            self.timestamp.attributedStringValue = timestampStr!;
        } else {
            self.timestamp.attributedStringValue = item.state == .outgoing_unsent ? NSAttributedString(string: "Unsent") : NSMutableAttributedString(string: formatTimestamp(item.timestamp));
        }
        super.set(message: item, nickname: nickname, keywords: keywords);
    }
    
}
