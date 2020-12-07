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

public class Room: ConversationBase<RoomOptions>, RoomProtocol, Conversation {
        
    open override var defaultMessageType: StanzaType {
        return .groupchat;
    }

    private let occupantsStore = RoomOccupantsStoreBase();

    private var _state: RoomState = .not_joined;
    public var state: RoomState {
        return dispatcher.sync {
            return _state;
        }
    }
    
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

    public var displayName: String {
        return name ?? jid.stringValue;
    }
        
    public var automaticallyFetchPreviews: Bool {
        return true;
    }
    
    public var roomJid: BareJID {
        return jid;
    }

    override init(dispatcher: QueueDispatcher,context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: RoomOptions) {
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
    
    public func add(occupant: MucOccupant) {
        dispatcher.async(flags: .barrier) {
            self.occupantsStore.add(occupant: occupant);
        }
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
    
    public func update(state: RoomState) {
        dispatcher.async(flags: .barrier) {
            self._state = state;
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
