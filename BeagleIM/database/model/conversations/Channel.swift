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
import Martin
import AppKit
import Combine
import Intents

public class Channel: ConversationBaseWithOptions<ChannelOptions>, ChannelProtocol, Conversation, LastMessageTimestampAware, @unchecked Sendable {
    
    open override var defaultMessageType: StanzaType {
        return .groupchat;
    }

    @Published
    open private(set) var permissions: Set<ChannelPermission>?;
    
    public var permissionsPublisher: AnyPublisher<Set<ChannelPermission>,Never> {
        if permissions == nil {
            Task {
                try await context?.module(.mix).affiliations(for: self);
            }
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
        withLock {
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
    
    private let creationTimestamp: Date;
    public var lastMessageTimestamp: Date? {
        guard creationTimestamp == lastActivity.timestamp else {
            return nil;
        }
        return lastActivity.timestamp;
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

    typealias Feature = ChannelFeature;
    
    init(context: Context, channelJid: BareJID, id: Int, lastActivity: LastChatActivity, unread: Int, options: ChannelOptions, creationTimestamp: Date) {
        self.creationTimestamp = creationTimestamp;
        self.displayable = ChannelDisplayableId(displayName: options.name ?? channelJid.description, status: nil, avatar: AvatarManager.instance.avatarPublisher(for: .init(account: context.userBareJid, jid: channelJid, mucNickname: nil)), description: options.description);
        super.init(context: context, jid: channelJid, id: id, lastActivity: lastActivity, unread: unread, options: options, displayableId: displayable);
        context.$state.sink(receiveValue: { [weak self] state in
            self?.connectionState = state;
        }).store(in: &cancellables);
        (context.module(.httpFileUpload) as! HttpFileUploadModule).isAvailablePublisher.combineLatest(context.$state, { isAvailable, state -> [ConversationFeature] in
            if case .connected(_) = state {
                return isAvailable ? [.httpFileUpload] : [];
            } else {
                return [];
            }
        }).sink(receiveValue: { [weak self] value in
            self?.update(features: value);
        }).store(in: &cancellables);

    }
        
    public override func isLocal(sender: ConversationEntrySender) -> Bool {
        switch sender {
        case .participant(let id, _, let jid):
            guard let jid = jid else {
                return participantId == id;
            }
            return jid == account;
        default:
            return false;
        }
    }
    
    public override func updateOptions(_ fn: @escaping (inout ChannelOptions) -> Void) {
        super.updateOptions(fn);
        DispatchQueue.main.async {
            self.displayable.displayName = self.options.name ?? self.jid.description;
            self.displayable.description = self.options.description;
            self.updateState();
        }
    }
    
    public override func createMessage(text: String, id: String, type: StanzaType) -> Message {
        let msg = super.createMessage(text: text, id: id, type: type);
        msg.isMarkable = true;
        return msg;
    }
    
    public func sendMessage(text: String, correctedMessageOriginId: String?) async throws {
        let message = self.createMessage(text: text);
        message.lastMessageCorrectionId = correctedMessageOriginId;
        try await self.send(message: message);
        if #available(macOS 12.0, *) {
            let sender = INPerson(personHandle: INPersonHandle(value: self.account.description, type: .unknown), nameComponents: nil, displayName: self.nickname, image: AvatarManager.instance.avatar(for: self.account, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.account.description, isMe: true, suggestionType: .instantMessageAddress);
            let recipient = INPerson(personHandle: INPersonHandle(value: self.jid.description, type: .unknown), nameComponents: nil, displayName: self.displayName, image: AvatarManager.instance.avatar(for: self.jid, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INSendMessageIntent(recipients: [recipient], outgoingMessageType: .outgoingMessageText, content: nil, speakableGroupName: INSpeakableString(spokenPhrase: self.displayName), conversationIdentifier: "account=\(self.account.description)|sender=\(self.jid.description)", serviceName: "Beagle IM", sender: sender, attachments: nil);
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .outgoing;
            try? await interaction.donate();
        }
    }
    
    public func prepareAttachment(url originalURL: URL) throws -> SharePreparedAttachment {
        return .init(url: originalURL, isTemporary: false, prepareShareURL: nil);
    }
    
    public func sendAttachment(url uploadedUrl: String, appendix: ChatAttachmentAppendix, originalUrl: URL?) async throws {
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected(), self.state == .joined else {
            throw XMPPError(condition: .remote_server_timeout);
        }
        
        let message = self.createMessage(text: uploadedUrl);
        message.oob = uploadedUrl;
        try await send(message: message)
        if #available(macOS 12.0, *) {
            let sender = INPerson(personHandle: INPersonHandle(value: self.account.description, type: .unknown), nameComponents: nil, displayName: self.nickname, image: AvatarManager.instance.avatar(for: self.account, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.account.description, isMe: true, suggestionType: .instantMessageAddress);
            let recipient = INPerson(personHandle: INPersonHandle(value: self.jid.description, type: .unknown), nameComponents: nil, displayName: self.displayName, image: AvatarManager.instance.avatar(for: self.jid, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INSendMessageIntent(recipients: [recipient], outgoingMessageType: .outgoingMessageText, content: nil, speakableGroupName: INSpeakableString(spokenPhrase: self.displayName), conversationIdentifier: "account=\(self.account.description)|sender=\(self.jid.description)", serviceName: "Beagle IM", sender: sender, attachments: nil);
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .outgoing;
            try? await interaction.donate();
        }
    }
    
    public func canSendChatMarker() -> Bool {
        return self.options.features.contains(.membersOnly);
    }
    
    public func sendChatMarker(_ marker: Message.ChatMarkers, andDeliveryReceipt receipt: Bool) {
        guard Settings.confirmMessages else {
            return;
        }
        
        if options.confirmMessages && canSendChatMarker() {
            let message = self.createMessage();
            message.chatMarkers = marker;
            message.hints = [.store]
            if receipt {
                message.messageDelivery = .received(id: marker.id)
            }
            Task {
                try await self.send(message: message);
            }
        } else if case .displayed(_) = marker {
            let message = createMessage(id: UUID().uuidString, type: .chat);
            message.to = JID(BareJID(localPart: "\(participantId)#\(jid.localPart!)", domain: jid.domain), resource: nil);
            message.chatMarkers = marker;
            message.hints = [.store]
            Task {
                try await self.send(message: message);
            }
        }
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
            return avatar.avatarPublisher.replaceNil(with: AvatarManager.instance.defaultGroupchatAvatar).eraseToAnyPublisher();
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
        return withLock {
            return self.participantsStore.participants;
        }
    }
    
    public var participantsPublisher: AnyPublisher<[MixParticipant],Never> {
        return self.participantsStore.participantsPublisher;
    }
    
    public func participant(withId: String) -> MixParticipant? {
        return withLock {
            return self.participantsStore.participant(withId: withId);
        }
    }
    
    public func set(participants: [MixParticipant]) {
        withLock {
            self.participantsStore.set(participants: participants);
        }
    }
    
    public func update(participant: MixParticipant) {
        withLock {
            self.participantsStore.update(participant: participant);
        }
    }
    
    public func removeParticipant(withId id: String) -> MixParticipant? {
        return withLock {
            return self.participantsStore.removeParticipant(withId: id);
        }
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
