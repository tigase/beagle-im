//
// ConversationKey.swift
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

public protocol ConversationKey: CustomDebugStringConvertible, Sendable {

    var account: BareJID { get }
    var jid: BareJID { get }
        
}

public struct ConversationKeyItem: ConversationKey {
    
    public let account: BareJID;
    public let jid: BareJID;
    
    public var debugDescription: String {
        return "ConversationKeyItem(account: \(account), jid: \(jid))";
    }
    
    init(account: BareJID, jid: BareJID) {
        self.account = account;
        self.jid = jid;
    }
    
}
