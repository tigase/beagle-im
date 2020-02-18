//
//  InvitationItem.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 17/02/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

class InvitationItem: ChatsListItemProtocol, Equatable {
    
    static func == (lhs: InvitationItem, rhs: InvitationItem) -> Bool {
        return lhs.type == rhs.type && lhs.account == rhs.account && lhs.jid == rhs.jid;
    }
    
    var id: String {
        return self.name + ":" + account.stringValue + ":" + jid.stringValue;
    }
    
    var name: String {
        return type.name;
    }
    let type: InvitationItemType;
    let account: BareJID;
    let jid: JID;
    let object: Any?;
    
    init(type: InvitationItemType, account: BareJID, jid: JID, object: Any?) {
        self.type = type;
        self.jid = jid;
        self.account = account;
        self.object = object;
    }
    
}

enum InvitationItemType {
    case presenceSubscription
    case mucInvitation
    
    var name: String {
        switch self {
        case .presenceSubscription:
            return "Presence subscription";
        case .mucInvitation:
            return "Groupchat invitation";
        }
    }
}
