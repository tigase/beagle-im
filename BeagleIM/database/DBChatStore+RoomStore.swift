//
// DBChatStore+RoomStore.swift
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

extension DBChatStore: RoomStore {

    public typealias Room = BeagleIM.Room
    
    public func rooms(for context: Context) -> [Room] {
        return convert(items: self.conversations(for: context.userBareJid));
    }
    
    public func room(for context: Context, with jid: BareJID) -> Room? {
        return conversation(for: context.userBareJid, with: jid) as? Room;
    }
    
    public func createRoom(for context: Context, with jid: BareJID, nickname: String, password: String?) -> ConversationCreateResult<Room> {
        let account = context.userBareJid;
        return self.queue.sync {
            guard let conversation = self.accountsConversations.conversation(for: account, with: jid) else {
                let timestamp = Date();
                let options = RoomOptions(nickname: nickname, password: password);
                let id = try! self.openConversation(account: context.userBareJid, jid: jid, type: .room, timestamp: timestamp, options: options);
                let room = Room(context: context, jid: jid, id: id, lastActivity: lastActivity(for: account, jid: jid, conversationType: .room) ?? .none(timestamp: timestamp), unread: 0, options: options);
                if self.accountsConversations.add(room) {
                    self.conversationsEventsPublisher.send(.created(room));
                    return .created(room);
                } else {
                    return .none;
                }
            }
            guard let room = conversation as? Room else {
                return .none;
            }
            return .found(room);
        }
    }
    
    public func close(room: Room) -> Bool {
        return close(conversation: room);
    }
    
    
}
