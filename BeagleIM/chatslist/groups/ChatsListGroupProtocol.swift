//
// ChatListGroupProtocol.swift
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

protocol ChatsListGroupProtocol {
    
    var name: String { get }
    
    var count: Int { get }
    
    var canOpenChat: Bool { get }
    
    func getItem(at: Int) -> ChatsListItemProtocol?;
    
    func forChat(_ chat: Conversation, execute: @escaping (ConversationItem)->Void);
    
    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ConversationItem)->Void);
}

protocol ChatsListItemProtocol {
    var name: String { get }
}
