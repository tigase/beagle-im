//
// InvitationItem.swift
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

import Foundation
import Martin

class InvitationItem: ChatsListItemProtocol, ChatsListContactItemProtocol, Identifiable, Equatable, Hashable {
    
    static func == (lhs: InvitationItem, rhs: InvitationItem) -> Bool {
        return lhs.type == rhs.type && lhs.account == rhs.account && lhs.jid == rhs.jid;
    }
    
    var id: String {
        return self.name + ":" + account.description + ":" + jid.description;
    }
    
    var name: String {
        return type.name;
    }
    let type: InvitationItemType;
    let account: BareJID;
    let jid: JID;
    let object: Any?;
    let order: Int;
    
    init(type: InvitationItemType, account: BareJID, jid: JID, object: Any?, order: Int) {
        self.type = type;
        self.jid = jid;
        self.account = account;
        self.object = object;
        self.order = order;
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(type);
        hasher.combine(jid);
        hasher.combine(account);
    }
}

enum InvitationItemType {
    case presenceSubscription
    case mucInvitation
    
    var name: String {
        switch self {
        case .presenceSubscription:
            return NSLocalizedString("Presence subscription", comment: "Chats list invitation type");
        case .mucInvitation:
            return NSLocalizedString("Groupchat invitation", comment: "Chats list invitation type");
        }
    }
    
    var isPersistent: Bool {
        switch self {
        case .presenceSubscription:
            return false;
        case .mucInvitation:
            return true;
        }
    }
    
}
