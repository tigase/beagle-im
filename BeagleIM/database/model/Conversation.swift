//
// Conversation.swift
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
import TigaseSwift

public protocol Conversation: ConversationProtocol {
    
    var id: Int { get }
    var timestamp: Date { get }
    var unread: Int { get }
    var lastActivity: LastConversationActivity? { get }
    
    var notifications: ConversationNotification { get }

    func markAsRead(count: Int) -> Bool;
    func updateLastActivity(_ lastActivity: LastConversationActivity?, timestamp: Date, isUnread: Bool) -> Bool;
}

enum ConversationType: Int {
    case chat = 0
    case room = 1
    case channel = 2
}

public typealias LastConversationActivity = LastChatActivity

public enum LastChatActivity {
    case message(String, direction: MessageDirection, sender: String?)
    case attachment(String, direction: MessageDirection, sender: String?)
    case invitation(String, direction: MessageDirection, sender: String?)
    
    static func from(itemType: ItemType?, data: String?, direction: MessageDirection, sender: String?) -> LastChatActivity? {
        guard itemType != nil else {
            return nil;
        }
        switch itemType! {
        case .message:
            return data == nil ? nil : .message(data!, direction: direction, sender: sender);
        case .invitation:
            return data == nil ? nil : .invitation(data!, direction: direction, sender: sender);
        case .attachment:
            return data == nil ? nil : .attachment(data!, direction: direction, sender: sender);
        case .linkPreview:
            return nil;
        case .messageRetracted, .attachmentRetracted:
            // TODO: Should we notify user that last message was retracted??
            return nil;
        }
    }
}

typealias ConversationEncryption = ChatEncryption

public enum ChatEncryption: String {
    case none = "none";
    case omemo = "omemo";
}

public protocol ChatOptionsProtocol {
    
    var notifications: ConversationNotification { get }
    
}

public enum ConversationNotification: String {
    case none
    case mention
    case always
}
