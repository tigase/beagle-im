//
// ConversationBase.swift
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
import AppKit
import Combine

public class ConversationBase: Martin.ConversationBase, Identifiable, Hashable, DisplayableIdWithKeyProtocol {
    
    public static func == (lhs: ConversationBase, rhs: ConversationBase) -> Bool {
        return lhs.id == rhs.id;
    }
    
    public let id: Int;
    public let dispatcher: QueueDispatcher;
    private let displayableId: DisplayableIdProtocol;

    public var displayName: String {
        return displayableId.displayName;
    }
    public var displayNamePublisher: Published<String>.Publisher {
        return displayableId.displayNamePublisher;
    }
    
    public var status: Presence.Show? {
        return displayableId.status;
    }
    public var statusPublisher: Published<Presence.Show?>.Publisher {
        return displayableId.statusPublisher;
    }
    
    public var avatarPublisher: AnyPublisher<NSImage?, Never> {
        return displayableId.avatarPublisher;
    }
    
    public var description: String? {
        return displayableId.description;
    }
    
    public var descriptionPublisher: Published<String?>.Publisher {
        return displayableId.descriptionPublisher;
    }
    
    @Published
    public private(set) var timestamp: Date;
    public var timestampPublisher: AnyPublisher<Date,Never> {
        return $timestamp.receive(on: DispatchQueue.main).eraseToAnyPublisher();
    }
    
    @Published
    public private(set) var lastActivity: LastChatActivity?;
    public var lastActivityPublisher: Published<LastChatActivity?>.Publisher {
        return $lastActivity;
    }
    
    @Published
    public private(set) var unread: Int;
    public var unreadPublisher: AnyPublisher<Int,Never> {
        return $unread.receive(on: DispatchQueue.main).eraseToAnyPublisher();
    }

    @Published
    public private(set) var markers: [ConversationEntrySender: ChatMarker] = [:];
    public var markersPublisher: AnyPublisher<[ChatMarker],Never> {
        return $markers.map({ Array($0.values) }).eraseToAnyPublisher();
    }
    
    @Published
    public private(set) var features: [ConversationFeature] = [];
    public var featuresPublisher: AnyPublisher<[ConversationFeature],Never> {
        return $features.eraseToAnyPublisher();
    }
    
    public init(dispatcher: QueueDispatcher, context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, displayableId: DisplayableIdProtocol) {
        self.id = id;
        self.timestamp = timestamp;
        self.dispatcher = dispatcher;
        self.lastActivity = lastActivity;
        self.unread = unread;
        self.displayableId = displayableId;
        super.init(context: context, jid: jid);
        for marker in DBChatMarkersStore.instance.markers(for: (self as! ConversationKey)) {
            if !self.isLocal(sender: marker.sender) {
                self.markers[marker.sender] = marker;
            }
        }
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id);
    }
    
    public func mark(as markerType: ChatMarker.MarkerType, before: Date, by sender: ConversationEntrySender) {
        guard !self.isLocal(sender: sender) else {
            return;
        }
        
        if let marker = markers[sender] {
            switch markerType {
            case .received:
                guard marker.timestamp < before else {
                    return;
                }
            case .displayed:
                guard marker.timestamp <= before else {
                    return;
                }
            }
        }
        markers[sender] = ChatMarker(sender: sender, timestamp: before, type: markerType);
    }
    
    public func markAsRead(count: Int) -> Bool {
        return dispatcher.sync(flags: .barrier) {
            guard unread > 0 else {
                return false;
            }
            unread = max(unread - count, 0);
            return true
        }
    }

    public func update(lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool {
        return dispatcher.sync(flags: .barrier) {
            if isUnread {
                unread = unread + 1;
            }
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) != .orderedDescending else {
                return isUnread;
            }
            
            if lastActivity != nil {
                self.lastActivity = lastActivity;
                self.timestamp = timestamp;
            }
            
            return true;
        }
    }
    
    public func refreshMarkers() {
        let toRemove = self.markers.keys.filter(isLocal(sender:));
        for sender in toRemove {
            self.markers.removeValue(forKey: sender);
        }
    }
    
    public func isLocal(sender: ConversationEntrySender) -> Bool {
        return false;
    }
    
    public func update(features: [ConversationFeature]) {
        self.features = features;
    }
}

public class ConversationBaseWithOptions<Options: ChatOptionsProtocol>: ConversationBase {
    
    private var _options: Options;
    public var options: Options {
        return dispatcher.sync {
            return _options;
        }
    }
    
    public var notifications: ConversationNotification {
        return options.notifications;
    }

    
    public init(dispatcher: QueueDispatcher, context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: Options, displayableId: DisplayableIdProtocol) {
        self._options = options;
        super.init(dispatcher: dispatcher, context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread:  unread, displayableId: displayableId);
    }
    
    public func updateOptions(_ fn: @escaping (inout Options)->Void) {
        dispatcher.async(flags: .barrier) {
            var options = self._options;
            fn(&options);
            if !options.equals(self._options) {
                DBChatStore.instance.update(options: options, for: self as! Conversation);
                self._options = options;
            }
        }
    }

}
