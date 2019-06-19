//
// DBChatStore.swift
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

import AppKit
import TigaseSwift

open class DBChatStoreWrapper: ChatStore {
    public var dispatcher: QueueDispatcher
    
    public func getChat<T>(with jid: BareJID, filter: @escaping (T) -> Bool) -> T? where T : ChatProtocol {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) as? T;
    }
    
    public func getAllChats<T>() -> [T] where T : ChatProtocol {
        return items as! [T];
    }
    
    fileprivate let sessionObject: SessionObject;
    fileprivate let store = DBChatStore.instance;
    
    open var count: Int {
        return store.count(for: sessionObject.userBareJid!);
    }
    
    open var items: [ChatProtocol] {
        return store.getChats(for: sessionObject.userBareJid!);
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
    
    public func open<T>(chat: ChatProtocol) -> T? {
        return store.open(for: sessionObject.userBareJid!, chat: chat);
    }
    
    public func close(chat: ChatProtocol) -> Bool {
        return store.close(for: sessionObject.userBareJid!, chat: chat);
    }
    
    public func initialize() {
        store.loadChats(for: sessionObject.userBareJid!, context: sessionObject.context);
    }
    
    public func deinitialize() {
        store.unloadChats(for: sessionObject.userBareJid!);
    }
}

open class DBChatStore {
    
    static let instance: DBChatStore = DBChatStore.init();
    
    static let CHAT_OPENED = Notification.Name("CHAT_OPENED");
    static let CHAT_CLOSED = Notification.Name("CHAT_CLOSED");
    static let CHAT_UPDATED = Notification.Name("CHAT_UPDATED");
    
    static let UNREAD_MESSAGES_COUNT_CHANGED = Notification.Name("UNREAD_NOTIFICATIONS_COUNT_CHANGED");
    
    fileprivate static let OPEN_CHAT = "INSERT INTO chats (account, jid, timestamp, type) VALUES (:account, :jid, :timestamp, :type)";
    fileprivate static let OPEN_ROOM = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    fileprivate static let CLOSE_CHAT = "DELETE FROM chats WHERE id = :id";
    fileprivate static let LOAD_CHATS = "SELECT c.id, c.type, c.jid, c.name, c.nickname, c.password, c.timestamp as creation_timestamp, last.timestamp as timestamp, last1.data, last1.encryption as lastEncryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread, c.encryption FROM chats c LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account LEFT JOIN chat_history last1 ON last1.account = c.account AND last1.jid = c.jid AND last1.timestamp = last.timestamp WHERE c.account = :account";
    fileprivate static let GET_LAST_MESSAGE = "SELECT last.timestamp as timestamp, last1.data, last1.encryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid GROUP BY ch.account, ch.jid) last LEFT JOIN chat_history last1 ON last1.account = last.account AND last1.jid = last.jid AND last1.timestamp = last.timestamp";
    fileprivate static let UPDATE_CHAT_NAME = "UPDATE chats SET name = :name WHERE account = :account AND jid = :jid";
    fileprivate static let CHANGE_CHAT_ENCRYPTION = "UPDATE chats SET encryption = :encryption WHERE account = :account AND jid = :jid";
    public let dispatcher: QueueDispatcher;

    fileprivate let closeChatStmt: DBStatement;
    fileprivate let openChatStmt: DBStatement;
    fileprivate let openRoomStmt: DBStatement;
    fileprivate let getLastMessageStmt: DBStatement;
    fileprivate let updateChatNameStmt: DBStatement;
    fileprivate let changeChatEncryptionStmt: DBStatement;

    fileprivate var accountChats = [BareJID: AccountChats]();
    
    var unreadMessagesCount: Int = 0 {
        didSet {
            let value = self.unreadMessagesCount;
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: value);
            }
        }
    }

    public init() {
        self.dispatcher = QueueDispatcher(label: "chat_store");
        
        openChatStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_CHAT);
        openRoomStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_ROOM);
        closeChatStmt = try! DBConnection.main.prepareStatement(DBChatStore.CLOSE_CHAT);
        getLastMessageStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_LAST_MESSAGE);
        updateChatNameStmt = try! DBConnection.main.prepareStatement(DBChatStore.UPDATE_CHAT_NAME);
        changeChatEncryptionStmt = try! DBConnection.main.prepareStatement(DBChatStore.CHANGE_CHAT_ENCRYPTION);
    }
 
    func count(for account: BareJID) -> Int {
        return dispatcher.sync {
            return self.accountChats[account]?.count ?? 0;
        }
    }
    
    func getChats() -> [DBChatProtocol] {
        return dispatcher.sync {
            var items: [DBChatProtocol] = [];
            self.accountChats.values.forEach({ (accountChats) in
                items.append(contentsOf: accountChats.items);
            });
            return items;
        }
    }
    
    func getChats(for account: BareJID) -> [DBChatProtocol] {
        return mapChats(for: account, map: { (chats) in
            return chats?.items ?? [];
        });
    }
    
    func mapChats<T>(for account: BareJID, map: (AccountChats?)->T) -> T {
        return dispatcher.sync {
            return map(accountChats[account]);
        }
    }
    
    func getChat(for account: BareJID, with jid: BareJID) -> DBChatProtocol? {
        return dispatcher.sync {
            return accountChats[account]?.get(with: jid);
        }
    }
    
    func open<T>(for account: BareJID, chat: ChatProtocol) -> T? {
        return dispatcher.sync {
            let accountChats = self.accountChats[account]!;
            guard let dbChat = accountChats.get(with: chat.jid.bareJid) else {
                guard let dbChat = createChat(account: account, chat: chat) else {
                    return nil;
                }
                guard let result = accountChats.open(chat: dbChat) as? T else {
                    return nil;
                }
                
                NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: result);
                
                return result;
            }
            return dbChat as? T;
        }
    }
    
    func close(for account: BareJID, chat: ChatProtocol) -> Bool {
        guard let dbChat = chat as? DBChatProtocol else {
            return false;
        }
        
        return dispatcher.sync {
            guard let accountChats = self.accountChats[account] else {
                return false;
            }
            
            guard accountChats.close(chat: dbChat) else {
                return false;
            }

            destroyChat(account: account, chat: dbChat);

            if dbChat.unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount - dbChat.unread;
                
                DBChatHistoryStore.instance.markAsRead(for: account, with: dbChat.jid.bareJid);
            }
            
            NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: dbChat
                );
            
            return true;
        }
    }
    
    func closeAll(for account: BareJID) {
        dispatcher.async {
            let items = self.getChats(for: account)
            items.forEach { chat in
                _ = self.close(for: account, chat: chat);
            }
        }
    }
    
    func lastMessageTimestamp(for account: BareJID) -> Date {
        return mapChats(for: account, map: { chats -> Date? in
            return chats?.lastMessageTimestamp();
        }) ?? Date(timeIntervalSince1970: 0);
    }
    
    func process(chatState remoteChatState: ChatState, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                (chat as? DBChat)?.remoteChatState = remoteChatState;
                NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
            }
        }
    }
    
    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, message: String?, state: MessageState, remoteChatState: ChatState? = nil) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                if chat.updateLastMessage(message, timestamp: timestamp, isUnread: state.isUnread) {
                    if state.isUnread {
                        self.unreadMessagesCount = self.unreadMessagesCount + 1;
                    }
                    if remoteChatState != nil {
                        (chat as? DBChat)?.remoteChatState = remoteChatState;
                    }
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                }
            }
        }
    }
    
    func markAsRead(for account: BareJID, with jid: BareJID, count: Int? = nil) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                let unread = chat.unread;
                if chat.markAsRead(count: count ?? unread) {
                    self.unreadMessagesCount = self.unreadMessagesCount - (count ?? unread);
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                }
            }
        }
    }
    
    func updateChatName(for account: BareJID, with jid: BareJID, name: String?) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                if let room = chat as? DBRoom, room.name != name {
                    room.name = name;
                    if try! self.updateChatNameStmt.update(["account": account, "jid": jid, "name": name] as [String: Any?]) > 0 {
                        NotificationCenter.default.post(name: MucEventHandler.ROOM_NAME_CHANGED, object: chat);
                    }
                }
            }
        }
    }
    
    func changeChatEncryption(for account: BareJID, with jid: BareJID, to encryption: ChatEncryption?, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            if let c = self.getChat(for: account, with: jid) {
                if let chat = c as? DBChat {
                    chat.encryption = encryption;
                }
                if try! self.changeChatEncryptionStmt.update(["account": account, "jid": jid, "encryption": encryption?.rawValue] as [String: Any?]) > 0 {
                    // encryption was changed, do we need to do anything else?
                    completionHandler();
                }
            }
        }
    }
    
    func resetChatStates(for account: BareJID) {
        dispatcher.async {
            self.getChats(for: account).forEach { chat in
                (chat as? DBChat)?.remoteChatState = nil;
                (chat as? DBChat)?.localChatState = .active;
            }
        }
    }
    
    fileprivate func createChat(account: BareJID, chat: ChatProtocol) -> DBChatProtocol? {
        guard chat as? DBChatProtocol == nil else {
            return chat as? DBChatProtocol;
        }
        switch chat {
        case let c as Chat:
            let params: [String: Any?] = [ "account": account, "jid": c.jid.bareJid, "timestamp": Date(), "type": 0 ];
            let id = try! self.openChatStmt.insert(params);
            return DBChat(id: id!, account: account, jid: c.jid.bareJid, timestamp: Date(), lastMessage: getLastMessage(for: account, jid: chat.jid.bareJid), unread: 0, encryption: nil);
        case let r as Room:
            let params: [String: Any?] = [ "account": account, "jid": r.roomJid, "timestamp": Date(), "type": 1, "nickname": r.nickname, "password": r.password];
            let id = try! self.openRoomStmt.insert(params);
            return DBRoom(id: id!, context: r.context, account: account, roomJid: r.roomJid, name: nil, nickname: r.nickname, password: r.password, timestamp: Date(), lastMessage: getLastMessage(for: account, jid: chat.jid.bareJid), unread: 0);
        default:
            return nil;
        }
    }
    
    fileprivate func destroyChat(account: BareJID, chat: DBChatProtocol) {
        let params: [String: Any?] = ["id": chat.id];
        _ = try! self.closeChatStmt.update(params);
    }
    
    fileprivate func getLastMessage(for account: BareJID, jid: BareJID) -> String? {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account, "jid": jid];
            return try! self.getLastMessageStmt.queryFirstMatching(params) { cursor in
                let encryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
                switch encryption {
                case .decrypted, .none:
                    return cursor["data"];
                default:
                    return encryption.message();
                }
            }
        }
    }
    
    func loadChats(for account: BareJID, context: Context) {
        dispatcher.async {
            guard self.accountChats[account] == nil else {
                return;
            }
            
            let stmt = try! DBConnection.main.prepareStatement(DBChatStore.LOAD_CHATS);
            let chats = try! stmt.query(["account": account]) { cursor -> DBChatProtocol? in
                let id: Int = cursor["id"]!;
                let type: Int = cursor["type"]!;
                let jid: BareJID = cursor["jid"]!;
                let creationTimestamp: Date = cursor["creation_timestamp"]!;
                let lastMessageTimestamp: Date = cursor["timestamp"]!;
                let lastMessageEncryption = MessageEncryption(rawValue: cursor["lastEncryption"] ?? 0) ?? .none;
                let lastMessage: String? = lastMessageEncryption.message() ?? cursor["data"];
                let unread: Int = cursor["unread"]!;
                
                let encryption = ChatEncryption(rawValue: cursor["encryption"] ?? "");
                
                let timestamp = creationTimestamp.compare(lastMessageTimestamp) == .orderedAscending ? lastMessageTimestamp : creationTimestamp;
                
                switch type {
                case 1:
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
                    let name: String? = cursor["name"];
            
                    let room = DBRoom(id: id, context: context, account: account, roomJid: jid, name: name, nickname: nickname, password: password, timestamp: timestamp, lastMessage: lastMessage, unread: unread);
                    if lastMessage != nil {
                        room.lastMessageDate = timestamp;
                    }
                    return room;
                default:
                    return DBChat(id: id, account: account, jid: jid, timestamp: timestamp, lastMessage: lastMessage, unread: unread, encryption: encryption);
                }
            }
            let accountChats = AccountChats(items: chats);
            self.accountChats[account] = accountChats;
            
            var unread = 0;
            chats.forEach { item in
                unread = unread + item.unread;
                NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: item);
            }
            if unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount + unread;
            }
        }
    }
    
    func unloadChats(for account: BareJID) {
        dispatcher.async {
            guard let accountChats = self.accountChats.removeValue(forKey: account) else {
                return;
            }
            
            var unread = 0;
            accountChats.items.forEach { item in
                unread = unread + item.unread;
                NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: item);
            }
            if unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount - unread;
            }
        }
    }
    
    class AccountChats {
        
        fileprivate var chats = [BareJID: DBChatProtocol]();
        
        var count: Int {
            return chats.count;
        }
        
        var items: [DBChatProtocol] {
            return chats.values.map({ (chat) -> DBChatProtocol in
                return chat;
            });
        }
        
        init(items: [DBChatProtocol]) {
            items.forEach { item in
                self.chats[item.jid.bareJid] = item;
            }
        }
        
        func open(chat: DBChatProtocol) -> DBChatProtocol {
            guard let existingChat = chats[chat.jid.bareJid] else {
                chats[chat.jid.bareJid] = chat;
                return chat;
            }
            return existingChat;
        }
        
        func close(chat: DBChatProtocol) -> Bool {
            return chats.removeValue(forKey: chat.jid.bareJid) != nil;
        }
        
        func isFor(jid: BareJID) -> Bool {
            return chats[jid] != nil;
        }
        
        func get(with jid: BareJID) -> DBChatProtocol? {
            return chats[jid];
        }
        
        func lastMessageTimestamp() -> Date {
            var timestamp = Date(timeIntervalSince1970: 0);
            chats.values.forEach { (chat) in
                guard chat.lastMessage != nil else {
                    return;
                }
                timestamp = max(timestamp, chat.timestamp);
            }
            return timestamp;
        }
    }
    
    class DBChat: Chat, DBChatProtocol {
        
        let id: Int;
        let account: BareJID;
        var timestamp: Date;
        var lastMessage: String? = nil;
        var unread: Int;
        var encryption: ChatEncryption? = nil;
        
        fileprivate var localChatState: ChatState = .active;
        var remoteChatState: ChatState? = nil;
        
        override var jid: JID {
            get {
                return super.jid;
            }
            set {
                super.jid = newValue.withoutResource;
            }
        }
        
        init(id: Int, account: BareJID, jid: BareJID, timestamp: Date, lastMessage: String?, unread: Int, encryption: ChatEncryption?) {
            self.id = id;
            self.account = account;
            self.timestamp = timestamp;
            self.lastMessage = lastMessage;
            self.unread = unread;
            self.encryption = encryption;
            super.init(jid: JID(jid), thread: nil);
        }
     
        func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool {
            if isUnread {
                unread = unread + 1;
            }
            guard self.lastMessage == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
                return isUnread;
            }
            if message != nil {
                self.lastMessage = message;
                self.timestamp = timestamp;
            }
            return true;
        }
        
        func markAsRead(count: Int) -> Bool {
            guard unread > 0 else {
                return false;
            }
            unread = max(unread - count, 0);
            return true
        }
        
        func changeChatState(state: ChatState) -> Message? {
            guard localChatState != state else {
                return nil;
            }
            self.localChatState = state;
            if (remoteChatState != nil) {
                let msg = Message();
                msg.to = jid;
                msg.type = StanzaType.chat;
                msg.chatState = state;
                return msg;
            }
            return nil;
        }
        
        override func createMessage(_ body: String, type: StanzaType, subject: String?, additionalElements: [Element]?) -> Message {
            let stanza = super.createMessage(body, type: type, subject: subject, additionalElements: additionalElements);
            stanza.id = UUID().uuidString;
            self.localChatState = .active;
            stanza.chatState = ChatState.active;
            return stanza;
        }
    }
    
    class DBRoom: Room, DBChatProtocol {
     
        let id: Int;
        let account: BareJID;
        var timestamp: Date;
        var lastMessage: String? = nil;
        var subject: String? = nil;
        var unread: Int;
        var name: String? = nil;
        var encryption: ChatEncryption? = nil;

        init(id: Int, context: Context, account: BareJID, roomJid: BareJID, name: String?, nickname: String, password: String?, timestamp: Date, lastMessage: String?, unread: Int) {
            self.id = id;
            self.account = account;
            self.timestamp = timestamp;
            self.lastMessage = lastMessage;
            self.unread = unread;
            self.name = name;
            super.init(context: context, roomJid: roomJid, nickname: nickname);
            setPassword(password);
        }
        
        fileprivate func setPassword(_ pass: String?) {
            self.password = pass;
        }
        
        func updateRoom(name: String?) {
            self.name = name;
        }
        
        func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool {
            if isUnread {
                unread = unread + 1;
            }
            guard self.lastMessage == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
                return isUnread;
            }
            
            self.lastMessage = message;
            self.timestamp = timestamp;
            
            return true;
        }
        
        func markAsRead(count: Int) -> Bool {
            guard unread > 0 else {
                return false;
            }
            unread = max(unread - count, 0);
            return true
        }

    }
}

protocol DBChatProtocol: ChatProtocol {
    
    var id: Int { get };
    var account: BareJID { get }
    var timestamp: Date { get };
    var lastMessage: String? { get };
    var unread: Int { get }
    var encryption: ChatEncryption? { get }

    func markAsRead(count: Int) -> Bool;
    func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool;

}

public enum ChatEncryption: String {
    case none = "none";
    case omemo = "omemo";    
}
