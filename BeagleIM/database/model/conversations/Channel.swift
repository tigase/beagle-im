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

public class Channel: ConversationBase<ChannelOptions>, ChannelProtocol, Conversation, LastMessageTimestampAware {
    
    open override var defaultMessageType: StanzaType {
        return .groupchat;
    }

    private var _permissions: Set<ChannelPermission>?;
    public var permissions: Set<ChannelPermission>? {
        return dispatcher.sync {
            return _permissions;
        }
    }

    private let participantsStore: MixParticipantsProtocol = MixParticipantsBase();
    
    public func update(state: ChannelState) {
        updateOptions({ options in
            options.state = state;
        });
    }
    
    public func update(permissions: Set<ChannelPermission>) {
        dispatcher.async(flags: .barrier) {
            self._permissions = permissions;
        }
    }
    
    public func update(info: ChannelInfo) {
        updateOptions({ options in
            options.name = info.name;
            options.description = info.description;
        })
    }
    
    public func update(ownNickname nickname: String?) {
        updateOptions({ options in
            options.nick = nickname;
        })
    }
        
    public var name: String? {
        return options.name;
    }
    
    public var displayName: String {
        return name ?? jid.stringValue;
    }
    
    public var description: String? {
        return options.description;
    }

    public var participantId: String {
        return options.participantId;
    }

    public var automaticallyFetchPreviews: Bool {
        return true;
    }
    
    public var channelJid: BareJID {
        return jid;
    }
    
    public var nickname: String? {
        return options.nick;
    }
    
    public var state: ChannelState {
        return options.state;
    }
    
    public var lastMessageTimestamp: Date? {
        return timestamp;
    }

    init(dispatcher: QueueDispatcher, context: Context, channelJid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: ChannelOptions) {
        super.init(dispatcher: dispatcher, context: context, jid: channelJid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options);
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
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected, self.state == .joined else {
            completionHandler?();
            return;
        }
        
        let message = self.createMessage(text: uploadedUrl);
        message.oob = uploadedUrl;
        send(message: message, completionHandler: nil)
        completionHandler?();
    }
}

extension Channel: MixParticipantsProtocol {
    
    public var participants: [MixParticipant] {
        return dispatcher.sync {
            return self.participantsStore.participants;
        }
    }
    
    public func participant(withId: String) -> MixParticipant? {
        return dispatcher.sync {
            return self.participantsStore.participant(withId: withId);
        }
    }
    
    public func set(participants: [MixParticipant]) {
        dispatcher.async(flags: .barrier) {
            self.participantsStore.set(participants: participants);
        }
    }
    
    public func update(participant: MixParticipant) {
        dispatcher.async(flags: .barrier) {
            self.participantsStore.update(participant: participant);
        }
    }
    
    public func removeParticipant(withId id: String) -> MixParticipant? {
        return dispatcher.sync(flags: .barrier) {
            return self.participantsStore.removeParticipant(withId: id);
        }
    }
}

public struct ChannelOptions: Codable, ChatOptionsProtocol, Equatable {
    
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
    
    public func equals(_ options: ChatOptionsProtocol) -> Bool {
        guard let options = options as? ChannelOptions else {
            return false;
        }
        return options == self;
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
