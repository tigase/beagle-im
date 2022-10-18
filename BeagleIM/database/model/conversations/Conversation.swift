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
import Martin
import Combine

import Foundation
import TigaseSQLite3
import Martin
import Combine

public enum ConversationFeature {
    case omemo
    case httpFileUpload
}

public protocol Conversation: ConversationProtocol, ConversationKey, DisplayableIdWithKeyProtocol {
        
    var status: Presence.Show? { get }
    var statusPublisher: Published<Presence.Show?>.Publisher { get }
    
    var displayName: String { get }
    var displayNamePublisher: Published<String>.Publisher { get }
    
    var id: Int { get }
    var timestamp: Date { get }
    var timestampPublisher: Publishers.Map<Published<LastChatActivity>.Publisher,Date> { get }
    var unread: Int { get }
    var unreadPublisher: AnyPublisher<Int,Never> { get }
    var lastActivity: LastConversationActivity { get }
    var lastActivityPublisher: Published<LastConversationActivity>.Publisher { get }
    
    var notifications: ConversationNotification { get }
    
    var automaticallyFetchPreviews: Bool { get }
    
    var markersPublisher: AnyPublisher<[ChatMarker],Never> { get }
    
    var features: [ConversationFeature] { get }
    var featuresPublisher: AnyPublisher<[ConversationFeature],Never> { get }
    
    func mark(as markerType: ChatMarker.MarkerType, before: Date, by sender: ConversationEntrySender);
    func markAsRead(count: Int) -> Bool;
    func update(_ activity: LastConversationActivity, isUnread: Bool) -> Bool;
    
    func sendMessage(text: String, correctedMessageOriginId: String?) async throws;
    func prepareAttachment(url originalURL: URL) throws -> SharePreparedAttachment
    func sendAttachment(url: String, appendix: ChatAttachmentAppendix, originalUrl: URL?) async throws;
    func canSendChatMarker() -> Bool;
    func sendChatMarker(_ marker: Message.ChatMarkers, andDeliveryReceipt: Bool);
    
    func isLocal(sender: ConversationEntrySender) -> Bool;
}

public struct SharePreparedAttachment {
    let url: URL;
    let isTemporary: Bool;
    let prepareShareURL: ((URL) -> URL)?;
}

import MartinOMEMO

extension Conversation {
     
    
    func loadItems(_ type: ConversationLoadType) -> [ConversationEntry] {
        return DBChatHistoryStore.instance.history(for: self, queryType: type);
    }
    
    func retract(entry: ConversationEntry) async throws {
        guard context != nil else {
            throw XMPPError(condition: .remote_server_timeout);
        }
        guard let originId = DBChatHistoryStore.instance.originId(for: account, with: jid, id: entry.id) else {
            throw XMPPError(condition: .item_not_found);
        }
        let message = self.createMessageRetraction(forMessageWithId: originId);
        try await self.send(message: message);
        DBChatHistoryStore.instance.retractMessage(for: self, stanzaId: originId, sender: entry.sender, retractionStanzaId: message.id, retractionTimestamp: Date(), serverMsgId: nil, remoteMsgId: nil);
    }
}

public typealias LastConversationActivity = LastChatActivity

public struct LastChatActivity {
    let timestamp: Date;
    let sender: ConversationEntrySender;
    let payload: LastChatActivityType?;
    
    static func none(timestamp: Date) -> LastChatActivity {
        return .init(timestamp: timestamp, sender: .none, payload: nil);
    }
    
    static func from(timestamp: Date, itemType: ItemType?, data: String?, sender: ConversationEntrySender) -> LastChatActivity {
        let type = LastChatActivityType.from(itemType: itemType, data: data);
        return .init(timestamp: timestamp, sender: sender, payload: type);
    }
    
}

public enum LastChatActivityType {
    case message(message: String)
    case attachment
    case invitation
    case location
    case retraction

    static func from(itemType: ItemType?, data: String?) -> LastChatActivityType? {
        guard let itemType = itemType else {
            return nil
        }

        switch itemType {
        case .message:
            if let data = data {
                return .message(message: data);
            }
            return nil;
        case .location:
            return .location;
        case .invitation:
            return .invitation;
        case .attachment:
            return .attachment;
        case .linkPreview:
            return nil;
        case .retraction:
            return .retraction;
        }
    }
    
    static func from(_ payload: ConversationEntryPayload) -> LastChatActivityType? {
        switch payload {
        case .message(let message, _):
            return .message(message: message);
        case .attachment(_, _):
            return .attachment
        case .linkPreview(_):
            return nil;
        case .retraction:
            return .retraction;
        case .invitation(_, _):
            return .invitation;
        case .deleted:
            return nil;
        case .unreadMessages:
            return nil;
        case .marker(_, _):
            return nil;
        case .location(_):
            return .location;
        }
    }
}

extension LastChatActivityType {
    
    static func from(_ cursor: Cursor) -> LastChatActivityType? {
        guard let itemType = ItemType(rawValue: cursor.int(for: "item_type") ?? -1) else {
            return nil;
        }
        let encryption = DBChatHistoryStore.encryptionFrom(cursor: cursor);
        return from(itemType: itemType, data: encryption.message() ?? cursor.string(for: "data"));
    }
    
}

typealias ConversationEncryption = ChatEncryption

public struct ChatMarker: Hashable, Sendable {
    let sender: ConversationEntrySender;
    let timestamp: Date;
    let type: MarkerType;
        
    public enum MarkerType: Int, Comparable, Hashable, Sendable {
        case received = 0
        case displayed = 1

        public var label: String {
            switch self {
            case .received:
                return NSLocalizedString("Received", comment: "label for chat marker")
            case .displayed:
                return NSLocalizedString("Displayed", comment: "label for chat marker")
            }
        }
        
        public static func < (lhs: MarkerType, rhs: MarkerType) -> Bool {
            return lhs.rawValue < rhs.rawValue;
        }

        static func from(chatMarkers: Message.ChatMarkers) -> MarkerType {
            switch chatMarkers {
            case .received(_):
                return .received;
            case .displayed(_), .acknowledged(_):
                return .displayed;
            }
        }
    }
}

extension Conversation {
     
//    public func readTillTimestampPublisher(for jid: JID) -> Published<Date?>.Publisher {
//        return entry(for: jid).$timestamp;
//    }
//
//    public func markers(inRange range: ClosedRange<Date>) -> [Date] {
//        return chatMarkers.filter({ (arg0) -> Bool in
//            let (key, value) = arg0;
//            return key.account == self.account && key.conversationJID == self.jid && value.timestamp != nil && range.contains(value.timestamp!);
//        }).map { (arg0) -> Date in
//            let (_, value) = arg0
//            return value.timestamp!;
//        }
//    }
    
}
