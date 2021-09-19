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
import TigaseSwiftOMEMO
import AppKit
import Combine

public class Room: ConversationBaseWithOptions<RoomOptions>, RoomProtocol, Conversation {
        
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
    
    @Published
    public var features: Set<Feature> = [] {
        didSet {
            if self.features.contains(.membersOnly) && self.features.contains(.nonAnonymous) {
                self.isOMEMOSupported = true;
                if let mucModule = context?.module(.muc) {
                    var members: [JID] = [];
                    let group = DispatchGroup();
                    for affiliation: MucAffiliation in [.member, .admin, .owner] {
                        group.enter();
                        mucModule.getRoomAffiliations(from: self, with: affiliation, completionHandler: { result in
                            switch result {
                            case .success(let affs):
                                members.append(contentsOf: affs.map({ $0.jid }));
                            case .failure(_):
                                break;
                            }
                            group.leave();
                        });
                    }
                    group.notify(queue: DispatchQueue.global(), execute: { [weak self] in
                        self?.dispatcher.async {
                            self?._members = members;
                        }
                    })
                }
            } else {
                self.isOMEMOSupported = false;
            }
        }
    }
    
    @Published
    public var isOMEMOSupported: Bool = false;
    
    public enum Feature: String {
        case membersOnly = "muc_membersonly"
        case nonAnonymous = "muc_nonanonymous"
    }
    
    init(dispatcher: QueueDispatcher,context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: RoomOptions) {
        self.displayable = RoomDisplayableId(displayName: options.name ?? jid.stringValue, status: nil, avatar: AvatarManager.instance.avatarPublisher(for: .init(account: context.userBareJid, jid: jid, mucNickname: nil)), description: nil);
        super.init(dispatcher: dispatcher, context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options, displayableId: displayable);
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
        return dispatcher.sync {
            return _members;
        }
    }
    
    public var occupants: [MucOccupant] {
        return dispatcher.sync {
            return self.occupantsStore.occupants;
        }
    }
    
    public func occupant(nickname: String) -> MucOccupant? {
        return dispatcher.sync {
            return occupantsStore.occupant(nickname: nickname);
        }
    }
    
    public func addOccupant(nickname: String, presence: Presence) -> MucOccupant {
        let occupant = MucOccupant(nickname: nickname, presence: presence, for: self);
        dispatcher.async(flags: .barrier) {
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
        dispatcher.async(flags: .barrier) {
            self.occupantsStore.remove(occupant: occupant);
            if let jid = occupant.jid {
                self._members = self._members?.filter({ $0 != jid });
            }
        }
    }
    
    public func addTemp(nickname: String, occupant: MucOccupant) {
        dispatcher.async(flags: .barrier) {
            self.occupantsStore.addTemp(nickname: nickname, occupant: occupant);
        }
    }
    
    public func removeTemp(nickname: String) -> MucOccupant? {
        return dispatcher.sync(flags: .barrier) {
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
            self.displayable.displayName = self.options.name ?? self.jid.stringValue;
        }
    }
    
    public func update(state: RoomState) {
        dispatcher.async(flags: .barrier) {
            self.state = state;
            self.occupantsStore.removeAll();
            if state != .joined && state != .requested {
                self._members = nil;
            }
        }
    }
        
    public override func createMessage(text: String, id: String, type: StanzaType) -> Message {
        let msg = super.createMessage(text: text, id: id, type: type);
        msg.isMarkable = true;
        return msg;
    }
    
    public func sendMessage(text: String, correctedMessageOriginId: String?) {
        let encryption = self.isOMEMOSupported ? self.options.encryption ?? Settings.messageEncryption : .none;
        
        let message = self.createMessage(text: text);
        message.lastMessageCorrectionId = correctedMessageOriginId;
        
        if encryption == .omemo, let omemoModule = context?.modulesManager.module(.omemo) {
            guard let members = self.members else {
                return;
            }
            omemoModule.encode(message: message, for: members.map({ $0.bareJid }), completionHandler: { result in
                switch result {
                case .failure(_):
                    break;
                case .successMessage(let message, let fingerprint):
                    super.send(message: message, completionHandler: nil);
                    DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.nickname, jid: nil), type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, options: .init(recipient: .none, encryption: .decrypted(fingerprint: fingerprint), isMarkable: true), linkPreviewAction: .auto, completionHandler: nil);
                }
            });
        } else {
            super.send(message: message, completionHandler: nil);
            DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.nickname, jid: nil), type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, options: .init(recipient: .none, encryption: .none, isMarkable: true), linkPreviewAction: .auto, completionHandler: nil);
        }
    }
    
    public func prepareAttachment(url originalURL: URL, completionHandler: @escaping (Result<(URL, Bool, ((URL) -> URL)?), ShareError>) -> Void) {
        let encryption = self.isOMEMOSupported ? self.options.encryption ?? Settings.messageEncryption : .none;
        switch encryption {
        case .none:
            completionHandler(.success((originalURL, false, nil)));
        case .omemo:
            guard let omemoModule: OMEMOModule = self.context?.module(.omemo), let data = try? Data(contentsOf: originalURL) else {
                completionHandler(.failure(.unknownError));
                return;
            }
            let result = omemoModule.encryptFile(data: data);
            switch result {
            case .success(let (encryptedData, hash)):
                let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);
                do {
                    try encryptedData.write(to: tmpFile);
                    completionHandler(.success((tmpFile, true, { url in
                        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                        parts.scheme = "aesgcm";
                        parts.fragment = hash;
                        let shareUrl = parts.url!;

                        return shareUrl;
                    })));
                } catch {
                    completionHandler(.failure(.noAccessError));
                }
            case .failure(_):
                completionHandler(.failure(.unknownError));
            }
        }
    }
    
    public func sendAttachment(url uploadedUrl: String, appendix: ChatAttachmentAppendix, originalUrl: URL?, completionHandler: (() -> Void)?) {
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected(), self.state == .joined else {
            completionHandler?();
            return;
        }
        
        let encryption = self.isOMEMOSupported ? self.options.encryption ?? Settings.messageEncryption : .none;
        
        let message = self.createMessage(text: uploadedUrl);
        if encryption == .omemo, let omemoModule = context?.modulesManager.module(.omemo) {
            guard let members = self.members else {
                completionHandler?();
                return;
            }
            omemoModule.encode(message: message, for: members.map({ $0.bareJid }), completionHandler: { result in
                switch result {
                case .failure(_):
                    break;
                case .successMessage(let message, let fingerprint):
                    super.send(message: message, completionHandler: nil);
                    DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.nickname, jid: nil), type: .attachment, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: uploadedUrl, appendix: appendix, options: .init(recipient: .none, encryption: .decrypted(fingerprint: fingerprint), isMarkable: true), linkPreviewAction: .auto, completionHandler: { msgId in
                        if let url = originalUrl {
                            _ = DownloadStore.instance.store(url, filename: appendix.filename ?? url.lastPathComponent, with: "\(msgId)");
                        }
                    });
                }
                completionHandler?();
            });
        } else {
            message.oob = uploadedUrl;
            super.send(message: message, completionHandler: nil);
            DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.nickname, jid: nil), type: .attachment, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: uploadedUrl, appendix: appendix, options: .init(recipient: .none, encryption: .none, isMarkable: true), linkPreviewAction: .auto, completionHandler: { msgId in
                if let url = originalUrl {
                    _ = DownloadStore.instance.store(url, filename: appendix.filename ?? url.lastPathComponent, with: "\(msgId)");
                }
            });
        }
    }
    
    public func sendPrivateMessage(to occupant: MucOccupant, text: String) {
        let message = self.createPrivateMessage(text, recipientNickname: occupant.nickname);
        let options = ConversationEntry.Options(recipient: .occupant(nickname: occupant.nickname), encryption: .none, isMarkable: false)
        DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.sent), sender: .occupant(nickname: self.options.nickname, jid: nil), type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, appendix: nil, options: options, linkPreviewAction: .auto, completionHandler: nil);
        self.send(message: message, completionHandler: nil);
    }
    
    public func canSendChatMarker() -> Bool {
        return self.features.contains(.membersOnly) && self.features.contains(.nonAnonymous);
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
            self.send(message: message, completionHandler: nil);
        } else if case .displayed(_) = marker {
            let message = self.createPrivateMessage(recipientNickname: self.nickname);
            message.chatMarkers = marker;
            message.hints = [.store]
            self.send(message: message, completionHandler: nil);
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

public struct RoomOptions: Codable, ChatOptionsProtocol, Equatable {
    
    public var name: String?;
    public let nickname: String;
    public var password: String?;

    var encryption: ChatEncryption?;
    public var notifications: ConversationNotification = .mention;
    public var confirmMessages: Bool = true;

    init(nickname: String, password: String?) {
        self.nickname = nickname;
        self.password = password;
    }
    
    init() {
        nickname = "";
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        encryption = try container.decodeIfPresent(String.self, forKey: .encryption).flatMap(ChatEncryption.init(rawValue: ));
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nickname = try container.decodeIfPresent(String.self, forKey: .nick) ?? "";
        password = try container.decodeIfPresent(String.self, forKey: .password)
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .mention;
        confirmMessages = try container.decodeIfPresent(Bool.self, forKey: .confirmMessages) ?? true;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encodeIfPresent(encryption?.rawValue, forKey: .encryption);
        try container.encodeIfPresent(name, forKey: .name);
        try container.encodeIfPresent(nickname, forKey: .nick);
        try container.encodeIfPresent(password, forKey: .password);
        if notifications != .mention {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
        try container.encode(confirmMessages, forKey: .confirmMessages)
    }
     
    public func equals(_ options: ChatOptionsProtocol) -> Bool {
        guard let options = options as? RoomOptions else {
            return false;
        }
        return options == self;
    }
    
    enum CodingKeys: String, CodingKey {
        case encryption = "encrypt"
        case name = "name";
        case nick = "nick";
        case password = "password";
        case notifications = "notifications";
        case confirmMessages = "confirmMessages"
    }
}
