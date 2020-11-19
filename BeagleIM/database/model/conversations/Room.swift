//
// Room.swift
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

public class Room: RoomBase, Conversation, Identifiable {
        
    public let id: Int;
 
    public private(set) var timestamp: Date;
    public private(set) var lastActivity: LastChatActivity?;
    public var subject: String? = nil;
    public private(set) var unread: Int;
    public var name: String? = nil;
    public var options: RoomOptions = RoomOptions();

    public var displayName: String {
        return name ?? jid.stringValue;
    }
    
    public var notifications: ConversationNotification {
        return options.notifications;
    }
    
    public var automaticallyFetchPreviews: Bool {
        return true;
    }
    
    public var roomJid: BareJID {
        return jid.bareJid;
    }

    init(context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: RoomOptions, name: String?, nickname: String, password: String?) {
        self.id = id;
        self.timestamp = timestamp;
        self.lastActivity = lastActivity;
        self.unread = unread;
        self.name = name;
        self.options = options;
        super.init(context: context, jid: jid, nickname: nickname, password: password, dispatcher: QueueDispatcher(label: "RoomQueue", attributes: [.concurrent]));
    }

    public func updateRoom(name: String?) {
        self.name = name;
    }

    public func updateLastActivity(_ lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool {
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
    
    public func markAsRead(count: Int) -> Bool {
        guard unread > 0 else {
            return false;
        }
        unread = max(unread - count, 0);
        return true
    }

    public func modifyOptions(_ fn: @escaping (inout RoomOptions) -> Void, completionHandler: (() -> Void)?) {
        DispatchQueue.main.async {
            var options = self.options;
            fn(&options);
            DBChatStore.instance.updateOptions(for: self.account, jid: self.jid, options: options, completionHandler: completionHandler);
        }
    }
    
}

public struct RoomOptions: Codable, ChatOptionsProtocol {
    
    public var notifications: ConversationNotification = .mention;
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .mention;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if notifications != .mention {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case notifications = "notifications";
    }
}
