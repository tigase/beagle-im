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

public enum ConversationEntrySender: Hashable {
    
    case none
    case me(nickname: String)
    case buddy(nickname: String)
    case occupant(nickname: String, jid: BareJID?)
    case participant(id: String, nickname: String, jid: BareJID?)
    
    var nickname: String? {
        switch self {
        case .me(let nickname):
            return nickname;
        case .buddy(let nickname), .occupant(let nickname, _), .participant(_, let nickname,  _):
            return nickname;
        case .none:
            return nil;
        }
    }
    
    func avatar(for key: ConversationKey) -> Avatar? {
        switch self {
        case .me:
            return AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: key.account, mucNickname: nil));
        case  .buddy(_):
            return AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: key.jid, mucNickname: nil));
        case .occupant(let nickname, let jid):
            if let jid = jid {
                return AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: jid, mucNickname: nil));
            } else {
                return AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: key.jid, mucNickname: nickname));
            }
        case .participant(let participantId, _, let jid):
            if let jid = jid {
                return AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: jid, mucNickname: nil));
            } else {
                return AvatarManager.instance.avatarPublisher(for: .init(account: key.account, jid: BareJID(localPart: "\(participantId)#\(key.jid.localPart ?? "")", domain: key.jid.domain), mucNickname: nil));
            }
        case .none:
            return nil;
        }
    }
    
    var isGroupchat: Bool {
        switch self {
        case .none, .buddy(_), .me(_):
            return false;
        default:
            return true;
        }
    }
    
    static func me(conversation: ConversationKey) -> ConversationEntrySender {
        return .me(nickname: AccountManager.getAccount(for: conversation.account)?.nickname ?? conversation.account.stringValue);
    }
    
    static func buddy(conversation: ConversationKey) -> ConversationEntrySender {
        if let conv = conversation as? Conversation {
            return .buddy(nickname: conv.displayName);
        } else {
            return .buddy(nickname: DBRosterStore.instance.item(for: conversation.account, jid: JID(conversation.jid))?.name ?? conversation.jid.stringValue);
        }
    }
}
