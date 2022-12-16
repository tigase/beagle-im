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
import Martin
import MartinOMEMO
import AppKit
import Combine
import Intents

public class Room: ConversationBaseWithOptions<RoomOptions>, RoomProtocol, Conversation, RoomWithPushSupportProtocol, @unchecked Sendable {
        
    open override var defaultMessageType: StanzaType {
        return .groupchat;
    }
    
    private let occupantsStore = RoomOccupantsStoreBase();
    
    public var occupantsPublisher: AnyPublisher<[MucOccupant], Never> {
        return occupantsStore.occupantsPublisher;
    }
    
    private let displayable: RoomDisplayableId;
    @Published
    public var role: MucRole = .none;
    @Published
    public var affiliation: MucAffiliation = .none;
    
    @Published
    public private(set) var state: RoomState = .not_joined() {
        didSet {
            switch state {
            case .joined:
                DispatchQueue.main.async {
                    self.displayable.status = .online;
                }
            case .requested:
                DispatchQueue.main.async {
                    self.displayable.status = .away;
                }
            default:
                DispatchQueue.main.async {
                    self.displayable.status = nil;
                }
            }
        }
    }
    public var statePublisher: AnyPublisher<RoomState, Never> {
        return $state.eraseToAnyPublisher();
    }
    
    public var subject: String? {
        get {
            return displayable.description;
        }
        set {
            DispatchQueue.main.async {
                self.displayable.description = newValue;
            }
        }
    }
    
    public var name: String? {
        return options.name;
    }
    
    public var nickname: String {
        return options.nickname;
    }
    
    public var password: String? {
        return options.password;
    }
    
    public var automaticallyFetchPreviews: Bool {
        return true;
    }
    
    public var roomJid: BareJID {
        return jid;
    }
    
    public var debugDescription: String {
        return "Room(account: \(account), jid: \(jid))";
    }
    
    public var allowedPM: RoomConfig.AllowPM = .anyone;
    
    @Published
    public var roomFeatures: Set<Feature> = [] {
        didSet {
            if self.roomFeatures.contains(.membersOnly) && self.roomFeatures.contains(.nonAnonymous) {
                if let mucModule = context?.module(.muc) {
                    Task {
                        let members: [JID] = await withTaskGroup(of: [JID].self, body: { group in
                            for affiliation: MucAffiliation in [.member, .admin, .owner] {
                                group.addTask(operation: {
                                    ((try? await mucModule.roomAffiliations(from: self, with: affiliation)) ?? []) .map({ $0.jid })
                                })
                            }
                            return await group.reduce(into: [JID](), { $0.append(contentsOf: $1) })
                        })
                        withLock({
                            self._members = members;
                        })
                    }
                }
            }
        }
    }
        
    public enum Feature: String {
        case membersOnly = "muc_membersonly"
        case nonAnonymous = "muc_nonanonymous"
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    init(context: Context, jid: BareJID, id: Int, lastActivity: LastChatActivity, unread: Int, options: RoomOptions) {
        self.displayable = RoomDisplayableId(displayName: options.name ?? jid.description, status: nil, avatar: AvatarManager.instance.avatarPublisher(for: .init(account: context.userBareJid, jid: jid, mucNickname: nil)), description: nil);
        super.init( context: context, jid: jid, id: id, lastActivity: lastActivity, unread: unread, options: options, displayableId: displayable);
        (context.module(.httpFileUpload) as! HttpFileUploadModule).isAvailablePublisher.combineLatest(self.statePublisher, self.$roomFeatures, { isAvailable, state, roomFeatures -> [ConversationFeature] in
            var features: [ConversationFeature] = [];
            if state == .joined {
                if isAvailable {
                    features.append(.httpFileUpload);
                }
                if roomFeatures.contains(.membersOnly) && roomFeatures.contains(.nonAnonymous) {
                    features.append(.omemo);
                }
            }
            return features;
        }).sink(receiveValue: { [weak self] value in self?.update(features: value); }).store(in: &cancellables);
    }

    public override func isLocal(sender: ConversationEntrySender) -> Bool {
        switch sender {
        case .occupant(let nickname, let jid):
            guard let jid = jid else {
                return nickname == self.nickname;
            }
            return jid == account;
        default:
            return false;
        }
    }
    
    private static let nonMembersAffiliations: Set<MucAffiliation> = [.none, .outcast];
    private var _members: [JID]?;
    public var members: [JID]? {
        return withLock {
            return _members;
        }
    }
    
    public var occupants: [MucOccupant] {
        return withLock {
            return self.occupantsStore.occupants;
        }
    }
    
    public func occupant(nickname: String) -> MucOccupant? {
        return withLock {
            return occupantsStore.occupant(nickname: nickname);
        }
    }
    
    public func addOccupant(nickname: String, presence: Presence) -> MucOccupant {
        let occupant = MucOccupant(nickname: nickname, presence: presence, for: self);
        withLock {
            self.occupantsStore.add(occupant: occupant);
            if let jid = occupant.jid {
                if !Room.nonMembersAffiliations.contains(occupant.affiliation) {
                    if !(self._members?.contains(jid) ?? false) {
                        self._members?.append(jid);
                    }
                } else {
                    self._members = self._members?.filter({ $0 != jid });
                }
            }
        }
        return occupant;
    }
    
    public func remove(occupant: MucOccupant) {
        withLock {
            self.occupantsStore.remove(occupant: occupant);
            if let jid = occupant.jid {
                self._members = self._members?.filter({ $0 != jid });
            }
        }
    }
    
    public func addTemp(nickname: String, occupant: MucOccupant) {
        withLock {
            self.occupantsStore.addTemp(nickname: nickname, occupant: occupant);
        }
    }
    
    public func removeTemp(nickname: String) -> MucOccupant? {
        withLock {
            return occupantsStore.removeTemp(nickname: nickname);
        }
    }
    
    public func updateRoom(name: String?) {
        updateOptions({ options in
            options.name = name;
        });
    }
    
    public override func updateOptions(_ fn: @escaping (inout RoomOptions) -> Void) {
        super.updateOptions(fn);
        DispatchQueue.main.async {
            self.displayable.displayName = self.options.name ?? self.jid.description;
        }
    }
    
    public func update(state: RoomState) {
        withLock {
            self.state = state;
            if state != .joined && state != .requested {
                self.occupantsStore.removeAll();
                self._members = nil;
            }
        }
    }
        
    public override func createMessage(text: String, id: String, type: StanzaType) -> Message {
        let msg = super.createMessage(text: text, id: id, type: type);
        msg.isMarkable = true;
        return msg;
    }
    
    public func sendMessage(text: String, correctedMessageOriginId: String?) async throws {
        let (message,encryption) = try await self.prepareForSend(message: self.createMessage(text: text));
        message.lastMessageCorrectionId = correctedMessageOriginId;

        try await super.send(message: message);
        if correctedMessageOriginId == nil {
            _ = DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.nickname, jid: nil), type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, options: .init(recipient: .none, encryption: encryption, isMarkable: true), linkPreviewAction: .auto);
        }
        
        if #available(macOS 12.0, *) {
            let sender = INPerson(personHandle: INPersonHandle(value: self.account.description, type: .unknown), nameComponents: nil, displayName: self.nickname, image: AvatarManager.instance.avatar(for: self.account, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.account.description, isMe: true, suggestionType: .instantMessageAddress);
            let recipient = INPerson(personHandle: INPersonHandle(value: self.jid.description, type: .unknown), nameComponents: nil, displayName: self.displayName, image: AvatarManager.instance.avatar(for: self.jid, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INSendMessageIntent(recipients: [recipient], outgoingMessageType: .outgoingMessageText, content: nil, speakableGroupName: INSpeakableString(spokenPhrase: self.displayName), conversationIdentifier: "account=\(self.account.description)|sender=\(self.jid.description)", serviceName: "Beagle IM", sender: sender, attachments: nil);
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .outgoing;
            try? await interaction.donate()
        }
    }
    
    private func prepareForSend(message: Message) async throws -> (Message,ConversationEntryEncryption) {
        let encryption = self.features.contains(.omemo) ? self.options.encryption ?? Settings.messageEncryption : .none;
        if encryption == .omemo, let omemoModule = context?.modulesManager.module(.omemo) {
            guard let members = self.members else {
                throw XMPPError(condition: .not_acceptable, message: NSLocalizedString("Could not send encrypted message due to missing list of room members.", comment: "omemo muc error - no members"));
            }
            message.oob = nil;
            let encrypted = try await omemoModule.encrypt(message: message, for: members.map({ $0.bareJid }));
            return (encrypted.message, .decrypted(fingerprint: encrypted.fingerprint));
        } else {
            return (message,.none)
        }
    }
    
    public func prepareAttachment(url originalURL: URL) throws -> SharePreparedAttachment {
        let encryption = self.features.contains(.omemo) ? self.options.encryption ?? Settings.messageEncryption : .none;
        switch encryption {
        case .none:
            return .init(url: originalURL, isTemporary: false, prepareShareURL: nil);
        case .omemo:
            let (encryptedData, hash) = try OMEMOModule.encryptFile(url: originalURL);
            let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);
            try encryptedData.write(to: tmpFile);
            return .init(url: tmpFile, isTemporary: true, prepareShareURL: { url in
                var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                parts.scheme = "aesgcm";
                parts.fragment = hash;
                let shareUrl = parts.url!;

                return shareUrl;
            });
        }
    }
    
    public func sendAttachment(url uploadedUrl: String, appendix: ChatAttachmentAppendix, originalUrl: URL?) async throws {
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected(), self.state == .joined else {
            throw XMPPError(condition: .remote_server_timeout);
        }
        
        let origMessage = self.createMessage(text: uploadedUrl);
        origMessage.oob = uploadedUrl;
        let (message,encryption) = try await self.prepareForSend(message: origMessage);
        try await super.send(message: message);
        if let msgId = DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.nickname, jid: nil), type: .attachment, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: uploadedUrl, appendix: appendix, options: .init(recipient: .none, encryption: encryption, isMarkable: true), linkPreviewAction: .auto) {
            if let url = originalUrl {
                _ = DownloadStore.instance.store(url, filename: appendix.filename ?? url.lastPathComponent, with: "\(msgId)");
            }
        }
        if #available(macOS 12.0, *) {
            let sender = INPerson(personHandle: INPersonHandle(value: self.account.description, type: .unknown), nameComponents: nil, displayName: self.nickname, image: AvatarManager.instance.avatar(for: self.account, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.account.description, isMe: true, suggestionType: .instantMessageAddress);
            let recipient = INPerson(personHandle: INPersonHandle(value: self.jid.description, type: .unknown), nameComponents: nil, displayName: self.displayName, image: AvatarManager.instance.avatar(for: self.jid, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: self.jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INSendMessageIntent(recipients: [recipient], outgoingMessageType: .outgoingMessageText, content: nil, speakableGroupName: INSpeakableString(spokenPhrase: self.displayName), conversationIdentifier: "account=\(self.account.description)|sender=\(self.jid.description)", serviceName: "Beagle IM", sender: sender, attachments: nil);
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .outgoing;
            try? await interaction.donate();
        }
    }
    
    public func sendPrivateMessage(to occupant: MucOccupant, text: String) async throws {
        let message = self.createPrivateMessage(text, recipientNickname: occupant.nickname);
        let options = ConversationEntry.Options(recipient: .occupant(nickname: occupant.nickname), encryption: .none, isMarkable: false)
        _ = DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.options.nickname, jid: nil), type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, appendix: nil, options: options, linkPreviewAction: .auto);
        do {
            try await self.send(message: message);
        } catch {
            if let id = message.id {
                DBChatHistoryStore.instance.markOutgoingAsError(for: ConversationKeyItem(account: account, jid: jid), stanzaId: id, error: error as? XMPPError ?? .undefined_condition)
            }
            throw error;
        }
    }
    
    public func canSendChatMarker() -> Bool {
        return self.roomFeatures.contains(.membersOnly) && self.roomFeatures.contains(.nonAnonymous);
    }
    
    public func canSendPrivateMessage() -> Bool {
        switch allowedPM {
        case .anyone:
            return true;
        case .moderators:
            return role == .moderator;
        case .participants:
            return role == .participant || role == .moderator;
        case .none:
            return false;
        }
    }

    public func sendChatMarker(_ marker: Message.ChatMarkers, andDeliveryReceipt receipt: Bool) {
        guard Settings.confirmMessages else {
            return;
        }
        
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected(), self.state == .joined else {
            return;
        }
        
        if self.options.confirmMessages && canSendChatMarker() {
            let message = self.createMessage();
            message.chatMarkers = marker;
            message.hints = [.store]
            if receipt {
                message.messageDelivery = .received(id: marker.id)
            }
            Task {
                try await self.send(message: message);
            }
        } else if case .displayed(_) = marker, canSendPrivateMessage() {
            let message = self.createPrivateMessage(recipientNickname: self.nickname);
            message.chatMarkers = marker;
            message.hints = [.store]
            Task {
                try await self.send(message: message);
            }
        }
        
    }
    
    private class RoomDisplayableId: DisplayableIdProtocol {
        
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
            self.description = description;
            self.status = status;
            self.avatar = avatar;
        }
        
    }
}
