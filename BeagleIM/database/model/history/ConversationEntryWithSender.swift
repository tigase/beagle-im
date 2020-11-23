//
// ConversationEntryWithSender.swift
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

class ConversationEntryWithSender: ConversationEntry {
    let state: ConversationEntryState;
    let sender: ConversationEntrySender;
    let encryption: ConversationEntryEncryption;
    let recipient: ConversationEntryRecipient;
    
    var avatar: NSImage? {
        return sender.avatar(for: self, direction: state.direction);
    }
    
    var nickname: String {
        return sender.nickname;
    }
    
    @available(*, deprecated, message: "Will be removed!")
    var account: BareJID {
        return conversation.account;
    }
    @available(*, deprecated, message: "Will be removed!")
    var jid: BareJID {
        return conversation.jid;
    }
    
    init(id: Int, conversation: ConversationKey, timestamp: Date, state: ConversationEntryState, sender: ConversationEntrySender, recipient: ConversationEntryRecipient, encryption: ConversationEntryEncryption) {
        self.state = state;
        self.sender = sender;
        self.recipient = recipient;
        self.encryption = encryption;
        super.init(id: id, conversation: conversation, timestamp: timestamp);
    }
    
    override func isMergeable() -> Bool {
        return true;
    }

    override func isMergeable(with it: ConversationEntry) -> Bool {
        guard super.isMergeable(with: it) else {
            return false;
        }
        guard let item = it as? ConversationEntryWithSender else {
            return false;
        }
        // make sure that entries are from the same conversation (just in case)
        guard conversation.account == item.conversation.account && conversation.jid == item.conversation.jid else {
            return false;
        }
        //
        guard state.direction == item.state.direction else {
            return false;
        }
        guard item.sender == sender, item.recipient == recipient else {
            return false;
        }
        
        guard encryption == encryption else {
            return false;
        }
        
        return abs(timestamp.timeIntervalSince(item.timestamp)) < allowedTimeDiff();
    }
    
    func allowedTimeDiff() -> TimeInterval {
        switch Settings.messageGrouping.string() ?? "smart" {
        case "none":
            return -1.0;
        case "always":
            return 60.0 * 60.0 * 24.0;
        default:
            return 30.0;
        }
    }
}
