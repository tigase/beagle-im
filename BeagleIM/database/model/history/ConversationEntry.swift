//
// ConversationEntry.swift
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
import Martin
import CoreLocation

extension Date: @unchecked Sendable {
    
}

public enum ConversationEntryPayload: Hashable, Sendable {
    case message(message: String, correctionTimestamp: Date?)
    case attachment(url: String, appendix: ChatAttachmentAppendix)
    case linkPreview(url: String)
    case retraction
    case invitation(message: String?, appendix: ChatInvitationAppendix)
    case deleted
    case unreadMessages
    case marker(type: ChatMarker.MarkerType, senders: [ConversationEntrySender])
    case location(location: CLLocationCoordinate2D)
}

public final class ConversationEntry: Hashable, Sendable {
    
    public static func == (lhs: ConversationEntry, rhs: ConversationEntry) -> Bool {
        lhs.id == rhs.id && lhs.timestamp == rhs.timestamp && lhs.payload == rhs.payload && lhs.sender == rhs.sender && lhs.state == rhs.state && lhs.options == rhs.options;
    }
    
    let id: Int;
    let conversation: ConversationKey;
    let timestamp: Date;
    let state: ConversationEntryState;
    let sender: ConversationEntrySender;
    
    let payload: ConversationEntryPayload
    let options: ConversationEntry.Options;
    
    init(id: Int, conversation: ConversationKey, timestamp: Date, state: ConversationEntryState, sender: ConversationEntrySender, payload: ConversationEntryPayload, options: ConversationEntry.Options) {
        self.id = id;
        self.conversation = conversation;
        self.timestamp = timestamp;
        self.state = state;
        self.sender = sender;
        self.payload = payload;
        self.options = options;
    }
    
    func isMergeable() -> Bool {
        switch payload {
        case .message(let message, _):
            return !message.starts(with: "/me ");
        default:
            return false;
        }
    }

    func isMergeable(with item: ConversationEntry) -> Bool {
        // check if entries can be mergable (some are not mergable)
        guard isMergeable() && item.isMergeable() else {
            return false;
        }

        guard sender == item.sender else {
            return false;
        }
        
        guard self.options.encryption == item.options.encryption else {
            return false;
        }
        // check encryption state and sender and direction as well..
        // maybe we should use state (direction) as nil if not set??
        // we could move 'encryption' to 'ChatMessageAppendix' in .message()
        
        return abs(timestamp.timeIntervalSince(item.timestamp)) < allowedTimeDiff();
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id);
        hasher.combine(timestamp);
        hasher.combine(sender);
        hasher.combine(state);
        hasher.combine(payload);
        hasher.combine(options);
    }
 
    func allowedTimeDiff() -> TimeInterval {
        // FIXME: add this setting
//        switch settings.messageGrouping {
//        case .none:
//            return -1.0;
//        case .always:
//            return 60.0 * 60.0 * 24.0;
//        case .smart:
            return 30.0;
//        }
    }

}

extension ConversationEntry {
    
    struct Options: Hashable, Sendable {
        let recipient: ConversationEntryRecipient;
        let encryption: ConversationEntryEncryption;
        let isMarkable: Bool;
        
        static let none = Options(recipient: .none, encryption: .none, isMarkable: false);
    }
    
}

public protocol ConversationEntryRelated {

    var order: ConversationEntry.Order { get }

}

extension ConversationEntry {

    public enum Order: Sendable {
        case first
        case last
    }
    
}

extension ConversationEntry: Comparable {
    
    public static func < (it1: ConversationEntry, it2: ConversationEntry) -> Bool {
        let unsent1 = it1.state.isUnsent;
        let unsent2 = it2.state.isUnsent;
        
        if unsent1 == unsent2 {
            let result = it1.timestamp.compare(it2.timestamp);
            guard result == .orderedSame else {
                return result == .orderedAscending ? false : true;
            }
            if it1.id == it2.id || (it1.id == -1 || it2.id == -1) {
                if let i1 = it1 as? ConversationEntryRelated {
                    switch i1.order {
                    case .first:
                        return false;
                    case .last:
                        return true;
                    }
                }
                if let i2 = it2 as? ConversationEntryRelated {
                    switch i2.order {
                    case .first:
                        return true;
                    case .last:
                        return false;
                    }
                }
            }
            // this does not work well if id is -1..
            return it1.id < it2.id ? false : true;
        } else {
            if unsent1 {
                return false;
            }
            return true;
        }
    }
    
}
