//
// Channel.swift
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

public class Channel: ChannelBase, Conversation, Identifiable, LastMessageTimestampAware {
    
    public let id: Int
    public private(set) var timestamp: Date
    public private(set) var lastActivity: LastChatActivity?
    public private(set) var unread: Int
    public var name: String? {
        return options.name;
    }
    
    public var displayName: String {
        return name ?? jid.stringValue;
    }
    
    public var description: String? {
        return options.description;
    }
    public var options: ChannelOptions;
    
    public var notifications: ConversationNotification {
        return options.notifications;
    }
    
    public var automaticallyFetchPreviews: Bool {
        return true;
    }
    
    public var channelJid: BareJID {
        return jid.bareJid;
    }
    
    public override var nickname: String? {
        get {
            return options.nick;
        }
        set {
            // nothing to do..
        }
    }
    
    public override var state: ChannelState {
        get {
            return options.state;
        }
        set {
            // nothing to do..
        }
    }
    
    public var lastMessageTimestamp: Date? {
        return timestamp;
    }

    init(context: Context, channelJid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: ChannelOptions) {
        self.id = id;
        self.unread = unread;
        self.lastActivity = lastActivity;
        self.timestamp = timestamp;
        self.options = options;
        super.init(context: context, channelJid: channelJid, participantId: options.participantId, nickname: options.nick, state: options.state);
    }
    
    public func markAsRead(count: Int) -> Bool {
        guard unread > 0 else {
            return false;
        }
        unread = max(unread - count, 0);
        return true
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

    public func sendMessage(text: String, correctedMessageOriginId: String?) {
        let message = self.createMessage(text: text);
        message.lastMessageCorrectionId = correctedMessageOriginId;
        self.send(message: message, completionHandler: nil);
    }
    
    public func prepareAttachment(url originalURL: URL, completionHandler: (Result<(URL, Bool, ((URL) -> URL)?), ShareError>) -> Void) {
        completionHandler(.success((originalURL, false, nil)));
    }
    
    public func sendAttachment(url uploadedUrl: String, appendix: ChatAttachmentAppendix, originalUrl: URL?, completionHandler: (() -> Void)?) {
        guard ((self.context as? XMPPClient)?.state ?? .disconnected) == .connected, self.state == .joined else {
            completionHandler?();
            return;
        }
        
        let message = self.createMessage(text: uploadedUrl);
        message.oob = uploadedUrl;
        send(message: message, completionHandler: nil)
        completionHandler?();
    }
}

public struct ChannelOptions: Codable, ChatOptionsProtocol {
    
    var participantId: String;
    var nick: String?;
    var name: String?;
    var description: String?;
    var state: ChannelState;
    public var notifications: ConversationNotification = .always;
    
    public init(participantId: String, nick: String?, state: ChannelState) {
        self.participantId = participantId;
        self.nick = nick;
        self.state = state;
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        participantId = try container.decode(String.self, forKey: .participantId);
        state = try container.decodeIfPresent(Int.self, forKey: .state).map({ ChannelState(rawValue: $0) ?? .joined }) ?? .joined;
        nick = try container.decodeIfPresent(String.self, forKey: .nick);
        name = try container.decodeIfPresent(String.self, forKey: .name);
        description = try container.decodeIfPresent(String.self, forKey: .description);
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .always;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(participantId, forKey: .participantId);
        try container.encode(state.rawValue, forKey: .state);
        try container.encodeIfPresent(nick, forKey: .nick);
        try container.encodeIfPresent(name, forKey: .name);
        try container.encodeIfPresent(description, forKey: .description);
        if notifications != .always {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case participantId = "participantId"
        case nick = "nick";
        case state = "state"
        case notifications = "notifications";
        case name = "name";
        case description = "desc";
    }
}
