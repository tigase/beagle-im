//
// Chat.swift
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

public class Chat: ChatBase, Conversation, Identifiable {
    
    public let id: Int;
    public private(set) var lastActivity: LastConversationActivity?;
    public private(set) var unread: Int;
    public private(set) var timestamp: Date;
    public var options: ChatOptions;
    
    var localChatState: ChatState = .active;
    private(set) var remoteChatState: ChatState? = nil;
    
    public var displayName: String {
        return context?.module(.roster).store.get(for: jid)?.name ?? jid.stringValue;
    }
    
    public var notifications: ConversationNotification {
        return options.notifications;
    }

    public var automaticallyFetchPreviews: Bool {
        return context?.module(.roster).store.get(for: jid) != nil;
    }

    
    init(context: Context, jid: JID, id: Int, timestamp: Date, lastActivity: LastConversationActivity?, unread: Int, options: ChatOptions) {
        self.id = id;
        self.timestamp = timestamp;
        self.lastActivity = lastActivity;
        self.unread = unread;
        self.options = options;
        super.init(context: context, jid: jid);
    }
    
    public func updateLastActivity(_ lastActivity: LastConversationActivity?, timestamp: Date, isUnread: Bool) -> Bool {
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
    
    func modifyOptions(_ fn: @escaping (inout ChatOptions) -> Void, completionHandler: (() -> Void)?) {
        DispatchQueue.main.async {
            var options = self.options;
            fn(&options);
            DBChatStore.instance.updateOptions(for: self.account, jid: self.jid, options: options, completionHandler: completionHandler);
        }
    }
    
    func changeChatState(state: ChatState) -> Message? {
        guard localChatState != state else {
            return nil;
        }
        self.localChatState = state;
        if (remoteChatState != nil) {
            let msg = Message();
            msg.to = jid;
            msg.type = StanzaType.chat;
            msg.chatState = state;
            return msg;
        }
        return nil;
    }
    
    private var remoteChatStateTimer: Foundation.Timer?;
    
    func update(remoteChatState state: ChatState?) -> Bool {
        // proper handle when we have the same state!!
        let prevState = remoteChatState;
        if prevState == .composing {
            remoteChatStateTimer?.invalidate();
            remoteChatStateTimer = nil;
        }
        self.remoteChatState = state;
        
        if state == .composing {
            DispatchQueue.main.async {
                self.remoteChatStateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false, block: { [weak self] timer in
                guard let that = self else {
                    return;
                }
                if that.remoteChatState == .composing {
                    that.remoteChatState = .active;
                    that.remoteChatStateTimer = nil;
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: that);
                }
            });
            }
        }
        return remoteChatState != prevState;
    }
    
    public override func createMessage(text: String, id: String, type: StanzaType) -> Message {
        let msg = super.createMessage(text: text, id: id, type: type);
        msg.chatState = .active;
        self.localChatState = .active;
        return msg;
    }
    
}

typealias ConversationOptionsProtocol = ChatOptionsProtocol

public struct ChatOptions: Codable, ConversationOptionsProtocol {
    
    var encryption: ChatEncryption?;
    public var notifications: ConversationNotification = .always;
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        if let val = try container.decodeIfPresent(String.self, forKey: .encryption) {
            encryption = ChatEncryption(rawValue: val);
        }
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .always;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if encryption != nil {
            try container.encode(encryption!.rawValue, forKey: .encryption);
        }
        if notifications != .always {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case encryption = "encrypt"
        case notifications = "notifications";
    }
}
