//
// DBChatStoreWrapper.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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

open class DBChatStoreWrapper: ChatStore {
            
    public let dispatcher: QueueDispatcher
    
    public func chat(with jid: BareJID, filter: @escaping (Chat) -> Bool) -> Chat? {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) as? Chat;
    }
    
    fileprivate let sessionObject: SessionObject;
    fileprivate let store = DBChatStore.instance;
    
    open var count: Int {
        return store.count(for: sessionObject.userBareJid!);
    }
    
    open var chats: [Chat] {
        return store.getChats(for: sessionObject.userBareJid!).filter({ $0 is Chat }).map({ $0 as! Chat });
    }
    
    public init(sessionObject: SessionObject) {
        self.sessionObject = sessionObject;
        self.dispatcher = store.dispatcher;
    }
    
    deinit {
        self.store.unloadChats(for: self.sessionObject.userBareJid!);
    }
    
    public func isFor(jid: BareJID) -> Bool {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) != nil;
    }
    
    public func createChat(jid: JID, thread: String?) -> Result<Chat, ErrorCondition> {
        switch store.createChat(for: sessionObject.userBareJid!, jid: jid, thread: thread) {
        case .success(let chat):
            return .success(chat as Chat);
        case .failure(let error):
            return .failure(error)
        }
    }
    
    public func close(chat: Chat) -> Bool {
        return store.close(for: sessionObject.userBareJid!, chat: chat);
    }
    
    public func initialize() {
        store.loadChats(for: sessionObject.userBareJid!, context: sessionObject.context);
    }
    
    public func deinitialize() {
        store.unloadChats(for: sessionObject.userBareJid!);
    }
}
