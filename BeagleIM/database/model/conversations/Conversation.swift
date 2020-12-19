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
import TigaseSQLite3
import TigaseSwift
import Combine

public protocol Conversation: ConversationProtocol, ConversationKey, DisplayableIdProtocol {
    
    var status: Presence.Show? { get }
    var statusPublisher: Published<Presence.Show?>.Publisher { get }
    
    var displayName: String { get }
    var displayNamePublisher: Published<String>.Publisher { get }
    
    var id: Int { get }
    var timestamp: Date { get }
    var unread: Int { get }
    var unreadPublisher: Published<Int>.Publisher { get }
    var lastActivity: LastConversationActivity? { get }
    
    var notifications: ConversationNotification { get }
    
    var automaticallyFetchPreviews: Bool { get }
    
    func markAsRead(count: Int) -> Bool;
    func update(lastActivity: LastConversationActivity?, timestamp: Date, isUnread: Bool) -> Bool;
    
    func sendMessage(text: String, correctedMessageOriginId: String?);
    func prepareAttachment(url: URL, completionHandler: @escaping (Result<(URL,Bool,((URL)->URL)?),ShareError>)->Void);
    func sendAttachment(url: String, appendix: ChatAttachmentAppendix, originalUrl: URL?, completionHandler: (()->Void)?);
}

import TigaseSwiftOMEMO

extension Conversation {
     
    
    func loadItems(_ type: ConversationLoadType) -> [ConversationEntry] {
        return DBChatHistoryStore.instance.history(for: self, queryType: type);
    }
    
    func retract(entry: ConversationEntryWithSender) {
        guard let context = context else {
            return;
        }
        DBChatHistoryStore.instance.originId(for: account, with: jid, id: entry.id, completionHandler: { originId in
            let message = self.createMessageRetraction(forMessageWithId: originId);
            self.send(message: message, completionHandler: nil);
            DBChatHistoryStore.instance.retractMessage(for: self, stanzaId: originId, sender: entry.sender, retractionStanzaId: message.id, retractionTimestamp: Date(), serverMsgId: nil, remoteMsgId: nil);
        })
    }
}

public enum ConversationType: Int {
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

public protocol ChatOptionsProtocol: DatabaseConvertibleStringValue {
    
    var notifications: ConversationNotification { get }
    
    func equals(_ options: ChatOptionsProtocol) -> Bool
}

public enum ConversationNotification: String {
    case none
    case mention
    case always
}
