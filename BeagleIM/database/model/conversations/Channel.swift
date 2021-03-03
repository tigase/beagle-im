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
import AppKit
import Combine

public class Channel: ConversationBaseWithOptions<ChannelOptions>, ChannelProtocol, Conversation, LastMessageTimestampAware {
    
    open override var defaultMessageType: StanzaType {
        return .groupchat;
    }

    @Published
    open private(set) var permissions: Set<ChannelPermission>?;
    
    public var permissionsPublisher: AnyPublisher<Set<ChannelPermission>,Never> {
        if permissions == nil {
            context?.module(.mix).retrieveAffiliations(for: self, completionHandler: nil);
        }
        return $permissions.compactMap({ $0 }).eraseToAnyPublisher();
    }

    private let participantsStore: MixParticipantsProtocol = MixParticipantsBase();
    
    public func update(state: ChannelState) {
        updateOptions({ options in
            options.state = state;
        });
    }
    
    public func update(permissions: Set<ChannelPermission>) {
        dispatcher.async(flags: .barrier) {
            self.permissions = permissions;
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
    
    private let displayable: ChannelDisplayableId;
        
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
    
    private var connectionState: XMPPClient.State = .disconnected() {
        didSet {
            DispatchQueue.main.async {
                self.updateState();
            }
        }
    }
    private var cancellables: Set<AnyCancellable> = [];

    public var debugDescription: String {
        return "Channel(account: \(account), jid: \(jid))";
    }
    
    init(dispatcher: QueueDispatcher, context: Context, channelJid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: ChannelOptions) {
        self.displayable = ChannelDisplayableId(displayName: options.name ?? channelJid.stringValue, status: nil, avatar: AvatarManager.instance.avatarPublisher(for: .init(account: context.userBareJid, jid: channelJid, mucNickname: nil)), description: options.description);
        super.init(dispatcher: dispatcher, context: context, jid: channelJid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options, displayableId: displayable);
        context.$state.sink(receiveValue: { [weak self] state in
            self?.connectionState = state;
        }).store(in: &cancellables);
    }
        
    public func isLocalParticipant(jid: JID) -> Bool {
        return account == jid.bareJid || (channelJid == jid.bareJid && participantId == jid.resource);
    }
    
    public override func updateOptions(_ fn: @escaping (inout ChannelOptions) -> Void) {
        super.updateOptions(fn);
        DispatchQueue.main.async {
            self.displayable.displayName = self.options.name ?? self.jid.stringValue;
            self.displayable.description = self.options.description;
            self.updateState();
        }
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
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected(), self.state == .joined else {
            completionHandler?();
            return;
        }
        
        let message = self.createMessage(text: uploadedUrl);
        message.oob = uploadedUrl;
        send(message: message, completionHandler: nil)
        completionHandler?();
    }
    
    private func updateState() {
        switch self.options.state {
        case .left:
            return self.displayable.status = nil;
        case .joined:
            switch self.connectionState {
            case .connected:
                self.displayable.status = .online;
            default:
                self.displayable.status = nil;
            }
        }
    }
    
    private class ChannelDisplayableId: DisplayableIdProtocol {
        
        @Published
        var displayName: String
        var displayNamePublisher: Published<String>.Publisher {
            return $displayName;
        }
        
        @Published
        var status: Presence.Show?
        var statusPublisher: Published<Presence.Show?>.Publisher {
            return $status;
        }
        
        @Published
        var description: String?;
        var descriptionPublisher: Published<String?>.Publisher {
            return $description;
        }
        
        let avatar: Avatar;
        var avatarPublisher: AnyPublisher<NSImage?, Never> {
            return avatar.$avatar.replaceNil(with: AvatarManager.instance.defaultGroupchatAvatar).eraseToAnyPublisher();
        }
        
        init(displayName: String, status: Presence.Show?, avatar: Avatar, description: String?) {
            self.displayName = displayName;
            self.status = status;
            self.description = description;
            self.avatar = avatar;
        }
        
    }
}

extension Channel: MixParticipantsProtocol {
    
    public var participants: [MixParticipant] {
        return dispatcher.sync {
            return self.participantsStore.participants;
        }
    }
    
    public var participantsPublisher: AnyPublisher<[MixParticipant],Never> {
        return self.participantsStore.participantsPublisher;
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

extension MixParticipant: Hashable {
    
    public static func == (lhs: MixParticipant, rhs: MixParticipant) -> Bool {
        return lhs.id == rhs.id;
    }
    
    public func hash(into hasher: inout Hasher) {
        return hasher.combine(id);
    }
    
}
