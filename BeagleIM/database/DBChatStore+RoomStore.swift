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
import TigaseSwift

extension DBChatStore: RoomStore {

    public typealias Room = BeagleIM.Room
    
    public func rooms(for context: Context) -> [Room] {
        return convert(items: self.conversations(for: context.userBareJid));
    }
    
    public func room(for context: Context, with jid: BareJID) -> Room? {
        return conversation(for: context.userBareJid, with: JID(jid)) as? Room;
    }
    
    public func createRoom(for context: Context, with jid: BareJID, nickname: String, password: String?) -> ConversationCreateResult<Room> {
        if let room = room(for: context, with: jid) {
            return .found(room);
        }
    
        let account = context.userBareJid;
        guard let room: Room = createConversation(for: account, with: JID(jid), execute: {
            let timestamp = Date();
            let id = try! self.openConversation(account: account, jid: JID(jid), type: .room, timestamp: timestamp, nickname: nickname, password: password, options: nil);

            let room = Room(context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity(for: account, jid: JID(jid)), unread: 0, options: RoomOptions(), name: nil, nickname: nickname, password: password);

            return room;
        }) else {
            if let room = self.room(for: context, with: jid) {
                return .found(room);
            }
            return .none;
        }
        return .created(room);
    }
    
    public func close(room: Room) -> Bool {
        return close(conversation: room);
    }
    
    
}
