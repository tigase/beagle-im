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
import AppKit

public class Room: ConversationBase<RoomOptions>, RoomProtocol, Conversation {
        
    open override var defaultMessageType: StanzaType {
        return .groupchat;
    }

    private let occupantsStore = RoomOccupantsStoreBase();

    @TigaseSwift.Published
    public var status: Presence.Show? = nil;
    public var statusPublisher: AnyPublisher<Presence.Show?, Never> {
        return $status.eraseToAnyPublisher();
    }
    
    public var occupantsPublisher: AnyPublisher<[MucOccupant], Never> {
        return occupantsStore.occupantsPublisher;
    }
    
    @TigaseSwift.Published
    public var role: MucRole = .none;
    @TigaseSwift.Published
    public var affiliation: MucAffiliation = .none;
    
    public private(set) var state: RoomState = .not_joined {
        didSet {
            switch state {
            case .joined:
                DispatchQueue.main.async {
                    self.status = .online;
                }
            case .requested:
                DispatchQueue.main.async {
                    self.status = .away;
                }
            default:
                DispatchQueue.main.async {
                    self.status = nil;
                }
            }
        }
    }
    
    @TigaseSwift.Published
    public var subject: String? = nil;
    
    public var name: String? {
        return options.name;
    }
    
    public var nickname: String {
        return options.nickname;
    }
    
    public var password: String? {
        return options.password;
    }

    @TigaseSwift.Published
    public var displayName: String;
    
    public var displayNamePublisher: AnyPublisher<String, Never> {
        return $displayName.eraseToAnyPublisher();
    }
    
    public var avatar: AnyPublisher<NSImage?, Never> {
        return AvatarManager.instance.avatarPublisher(for: .init(account: account, jid: jid, type: .buddy)).replaceNil(with: AvatarManager.instance.defaultGroupchatAvatar).eraseToAnyPublisher();
    }
        
    public var automaticallyFetchPreviews: Bool {
        return true;
    }
    
    public var roomJid: BareJID {
        return jid;
    }

    override init(dispatcher: QueueDispatcher,context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: RoomOptions) {
        displayName = options.name ?? jid.stringValue;
        super.init(dispatcher: dispatcher, context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options);
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
        let occupant = MucOccupant(nickname: nickname, presence: presence);
        dispatcher.async(flags: .barrier) {
            self.occupantsStore.add(occupant: occupant);
        }
        return occupant;
    }
    
    public func remove(occupant: MucOccupant) {
        dispatcher.async(flags: .barrier) {
            self.occupantsStore.remove(occupant: occupant);
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
        NotificationCenter.default.post(name: MucEventHandler.ROOM_NAME_CHANGED, object: self);
    }
    
    public override func updateOptions(_ fn: @escaping (inout RoomOptions) -> Void) {
        super.updateOptions(fn);
        DispatchQueue.main.async {
            self.displayName = self.options.name ?? self.jid.stringValue;
        }
    }
    
    public func update(state: RoomState) {
        dispatcher.async(flags: .barrier) {
            self.state = state;
            self.occupantsStore.removeAll();
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
        guard ((self.context as? XMPPClient)?.state ?? .disconnected()) == .connected, self.state == .joined else {
            completionHandler?();
            return;
        }
        
        let message = self.createMessage(text: uploadedUrl);
        message.oob = uploadedUrl;
        send(message: message, completionHandler: nil)
        completionHandler?();
    }
    
    public func sendPrivateMessage(to occupant: MucOccupant, text: String) {
        let message = self.createPrivateMessage(text, recipientNickname: occupant.nickname);
        DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing, sender: .occupant(nickname: self.options.nickname, jid: nil), recipient: .occupant(nickname: occupant.nickname), type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: text, encryption: .none, appendix: nil, linkPreviewAction: .auto, completionHandler: nil);
        self.send(message: message, completionHandler: nil);
    }
    
}

public struct RoomOptions: Codable, ChatOptionsProtocol, Equatable {
    
    public var name: String?;
    public let nickname: String;
    public var password: String?;

    public var notifications: ConversationNotification = .mention;
    
    init(nickname: String, password: String?) {
        self.nickname = nickname;
        self.password = password;
    }
    
    init() {
        nickname = "";
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        name = try container.decodeIfPresent(String.self, forKey: .name)
        nickname = try container.decodeIfPresent(String.self, forKey: .nick) ?? "";
        password = try container.decodeIfPresent(String.self, forKey: .password)
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .mention;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encodeIfPresent(name, forKey: .name);
        try container.encodeIfPresent(nickname, forKey: .nick);
        try container.encodeIfPresent(password, forKey: .password);
        if notifications != .mention {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
     
    public func equals(_ options: ChatOptionsProtocol) -> Bool {
        guard let options = options as? RoomOptions else {
            return false;
        }
        return options == self;
    }
    
    enum CodingKeys: String, CodingKey {
        case name = "name";
        case nick = "nick";
        case password = "password";
        case notifications = "notifications";
    }
}
