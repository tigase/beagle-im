//
// ChatEntry.swift
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

import Foundation
import TigaseSwift

class ChatEntry: ChatViewItemProtocol {
    
    let id: Int;
    let timestamp: Date;
    let account: BareJID;
    let jid: BareJID;
    let state: MessageState;

    // for MUC only but any chat may be a MUC chat...
    let authorNickname: String?;
    let authorJid: BareJID?;
    let recipientNickname: String?;

    // for MIX - id of participant
    let participantId: String?;
    
    let error: String?;

    let encryption: MessageEncryption;
    let encryptionFingerprint: String?;

    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, authorNickname: String?, authorJid: BareJID?, recipientNickname: String?, participantId: String?, encryption: MessageEncryption, encryptionFingerprint: String?, error: String?) {
        self.id = id;
        self.timestamp = timestamp;
        self.account = account;
        self.jid = jid;
        self.state = state;
        self.authorNickname = authorNickname;
        self.authorJid = authorJid;
        self.recipientNickname = recipientNickname;
        self.participantId = participantId;
        self.encryption = encryption;
        self.encryptionFingerprint = encryptionFingerprint;
        self.error = error;
    }

    func isMergeable(with chatItem: ChatViewItemProtocol) -> Bool {
        guard let item = chatItem as? ChatEntry else {
            return false;
        }
        return self.account == item.account && self.jid == item.jid && self.state.direction == item.state.direction && self.authorNickname == item.authorNickname && self.authorJid == item.authorJid && self.recipientNickname == item.recipientNickname && self.participantId == item.participantId && abs(self.timestamp.timeIntervalSince(item.timestamp)) < allowedTimeDiff() && self.encryption == item.encryption && self.encryptionFingerprint == item.encryptionFingerprint;
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
