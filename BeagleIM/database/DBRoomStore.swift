//
// DBRoomStore.swift
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

open class DBRoomStore: RoomStore {
    
    public let dispatcher: QueueDispatcher;
    private let sessionObject: SessionObject;
    
    public var rooms: [Room] {
        return store.getChats(for: sessionObject.userBareJid!).filter({ $0 is Room}).map({ $0 as! Room });
    }
    
    private let store = DBChatStore.instance;
    
    public init(sessionObject: SessionObject) {
        self.sessionObject = sessionObject;
        self.dispatcher = store.dispatcher;
    }
    
    deinit {
        self.store.unloadChats(for: self.sessionObject.userBareJid!);
    }

    public func room(for jid: BareJID) -> Room? {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) as? Room;
    }
    
    public func createRoom(roomJid: BareJID, nickname: String, password: String?) -> Result<Room, ErrorCondition> {
        switch store.createRoom(for: sessionObject.userBareJid!, context: sessionObject.context, roomJid: roomJid, nickname: nickname, password: password) {
        case .success(let room):
            return .success(room as Room);
        case .failure(let error):
            return .failure(error);
        }
    }
    
    public func close(room: Room) -> Bool {
        return store.close(for: sessionObject.userBareJid!, chat: room);
    }
    

    public func initialize() {
        store.loadChats(for: sessionObject.userBareJid!, context: sessionObject.context);
    }
    
    public func deinitialize() {
        store.unloadChats(for: sessionObject.userBareJid!);
    }

}
