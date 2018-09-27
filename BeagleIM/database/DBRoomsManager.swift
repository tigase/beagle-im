//
//  DBRoomsManager.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 20.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

open class DBRoomsManager: DefaultRoomsManager {

    fileprivate let store = DBChatStore.instance;
    
    public init() {
        super.init(dispatcher: store.dispatcher);
    }
    
    open override func createRoomInstance(roomJid: BareJID, nickname: String, password: String?) -> Room {
        let room = super.createRoomInstance(roomJid: roomJid, nickname: nickname, password: password);
        return store.open(for: context.sessionObject.userBareJid!, chat: room)!;
    }
    
    open override func contains(roomJid: BareJID) -> Bool {
        return getRoom(for: roomJid) != nil;
    }
    
    open override func getRoom(for roomJid: BareJID) -> Room? {
        return store.getChat(for: context.sessionObject.userBareJid!, with: roomJid) as? Room;
    }
    
    open override func getRoomOrCreate(for roomJid: BareJID, nickname: String, password: String?, onCreate: @escaping (Room) -> Void) -> Room {
        let room = super.createRoomInstance(roomJid: roomJid, nickname: nickname, password: password);
        let account: BareJID = context.sessionObject.userBareJid!;
        let dbRoom: DBChatStore.DBRoom = store.open(for: account, chat: room)!;
        if dbRoom.state == .not_joined {
            onCreate(dbRoom);
        }
        return dbRoom;
    }
    
    open override func getRooms() -> [Room] {
        var result: [Room] = [];
        guard let items = store.getChats(for: context.sessionObject.userBareJid!)?.items else {
            return result;
        }
        items.forEach { (item) in
            guard let room = item as? Room else {
                return;
            }
            result.append(room);
        }
        return result;
    }
    
    open override func register(room: Room) {
        // nothing to do....
    }
    
    open override func remove(room: Room) {
        _ = store.close(for: context!.sessionObject.userBareJid!, chat: room);
    }

    open override func initialize() {
        super.initialize();
        store.loadChats(for: context!.sessionObject.userBareJid!, context: context);
    }
    
    public func deinitialize() {
        store.unloadChats(for: context!.sessionObject.userBareJid!);
    }

}
