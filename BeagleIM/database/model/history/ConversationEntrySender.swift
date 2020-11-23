//
// ConversationEntrySender.swift
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

enum ConversationEntrySender: Equatable {
    
    case buddy(nickname: String)
    case occupant(nickname: String, jid: BareJID?)
    case participant(id: String, nickname: String, jid: BareJID?)
    
    var nickname: String {
        switch self {
        case .buddy(let nickname), .occupant(let nickname, _), .participant(_, let nickname,  _):
            return nickname;
        }
    }
    
    func avatar(for entry: ConversationEntry, direction: MessageDirection) -> NSImage? {
        switch direction {
        case .outgoing:
            return AvatarManager.instance.avatar(for: entry.conversation.account, on: entry.conversation.account);
        case .incoming:
            switch self {
            case  .buddy(_):
                return AvatarManager.instance.avatar(for: entry.conversation.jid, on: entry.conversation.account)
            case .occupant(let nickname, let jid):
                if let jid = jid {
                    return AvatarManager.instance.avatar(for: jid, on: entry.conversation.account);
                } else if let room = entry.conversation as? Room, let photoHash = room.occupant(nickname: nickname)?.presence.vcardTempPhoto {
                    return AvatarManager.instance.avatar(withHash: photoHash);
                } else {
                    return nil;
                }
            case .participant(let participantId, _, let jid):
                if let jid = jid {
                    return AvatarManager.instance.avatar(for: jid, on: entry.conversation.account);
                } else {
                    return AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(entry.conversation.jid.localPart!)", domain: entry.conversation.jid.domain), on: entry.conversation.account);
                }
            }
        }
    }
    
    var isGroupchat: Bool {
        switch self {
        case .buddy(_):
            return false;
        default:
            return true;
        }
    }
    
    static func me(conversation: ConversationKey) -> ConversationEntrySender {
        return .buddy(nickname: AccountManager.getAccount(for: conversation.account)?.nickname ?? conversation.account.stringValue)
    }
    
    static func buddy(conversation: ConversationKey) -> ConversationEntrySender {
        if let conv = conversation as? Conversation {
            return .buddy(nickname: conv.displayName);
        } else {
            return .buddy(nickname: XmppService.instance.getClient(for: conversation.account)?.module(.roster).store.get(for: JID(conversation.jid))?.name ?? conversation.jid.stringValue);
        }
    }
}
