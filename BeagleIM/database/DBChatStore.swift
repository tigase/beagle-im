//
//  DBChatStore.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 02.08.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
        return store.getChats(for: sessionObject.userBareJid!)?.count ?? 0;
    }
    
    open var items: [ChatProtocol] {
        return store.getChats(for: sessionObject.userBareJid!)?.items ?? [];
    }
    
    public init(sessionObject: SessionObject) {
        self.sessionObject = sessionObject;
        self.dispatcher = store.dispatcher;
    }
    
    deinit {
        self.store.unloadChats(for: self.sessionObject.userBareJid!);
    }
    
    public func isFor(jid: BareJID) -> Bool {
        return store.getChats(for: sessionObject.userBareJid!)?.isFor(jid: jid) ?? false;
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
    
    fileprivate static let OPEN_CHAT = "INSERT INTO chats (account, jid, timestamp, type) VALUES (:account, :jid, :timestamp, :type)";
    fileprivate static let OPEN_ROOM = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    fileprivate static let CLOSE_CHAT = "DELETE FROM chats WHERE id = :id";
    fileprivate static let LOAD_CHATS = "SELECT c.id, c.type, c.jid, c.nickname, c.password, c.timestamp as creation_timestamp, last.timestamp as timestamp, (SELECT data FROM chat_history ch1 WHERE ch1.account = c.account AND ch1.jid = c.jid AND ch1.timestamp = last.timestamp) as data, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread FROM chats c LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account WHERE c.account = :account";
    fileprivate static let GET_LAST_MESSAGE = "SELECT last.timestamp as timestamp, (SELECT data FROM chat_history ch1 WHERE ch1.account = last.account AND ch1.jid = last.jid AND ch1.timestamp = last.timestamp) as data, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid GROUP BY ch.account, ch.jid) last";

    public let dispatcher: QueueDispatcher;

    fileprivate let closeChatStmt: DBStatement;
    fileprivate let openChatStmt: DBStatement;
    fileprivate let openRoomStmt: DBStatement;
    fileprivate let getLastMessageStmt: DBStatement;
    
    fileprivate var chats = [BareJID: AccountChats]();
    
    var unreadMessagesCount: Int = 0 {
        didSet {
            let value = self.unreadMessagesCount;
            DispatchQueue.main.async {
                if value > 0 {
                    NSApplication.shared.dockTile.badgeLabel = "\(value)";
                } else {
                    NSApplication.shared.dockTile.badgeLabel = nil;
                }
            }
        }
    }

    public init() {
        self.dispatcher = QueueDispatcher(label: "chat_store");
        
        openChatStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_CHAT);
        openRoomStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_ROOM);
        closeChatStmt = try! DBConnection.main.prepareStatement(DBChatStore.CLOSE_CHAT);
        getLastMessageStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_LAST_MESSAGE);
    }
 
    func count(for account: BareJID) -> Int {
        return dispatcher.sync {
            return chats[account]?.count ?? 0;
        }
    }
    
    func getChats() -> [DBChatProtocol] {
        return dispatcher.sync {
            var items: [DBChatProtocol] = [];
            chats.values.forEach({ (accountChats) in
                items.append(contentsOf: accountChats.items);
            });
            return items;
        }
    }
    
    func getChats(for account: BareJID) -> AccountChats? {
        return dispatcher.sync {
            return chats[account];
        }
    }
    
    func getChat(for account: BareJID, with jid: BareJID) -> DBChatProtocol? {
        return dispatcher.sync {
            return chats[account]?.get(with: jid);
        }
    }
    
    func open<T>(for account: BareJID, chat: ChatProtocol) -> T? {
        return dispatcher.sync {
            let accountChats = self.chats[account]!;
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
            guard let accountChats = chats[account] else {
                return false;
            }
            
            guard accountChats.close(chat: dbChat) else {
                return false;
            }

            destroyChat(account: account, chat: dbChat);
            
            NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: dbChat
                );
            
            return true;
        }
    }
    
    func closeAll(for account: BareJID) {
        dispatcher.async {
            if let items = self.getChats(for: account)?.items {
                items.forEach { chat in
                    _ = self.close(for: account, chat: chat);
                }
            }
        }
    }
    
    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, message: String, state: MessageState) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                if chat.updateLastMessage(message, timestamp: timestamp, isUnread: state.isUnread) {
                    if state.isUnread {
                        self.unreadMessagesCount = self.unreadMessagesCount + 1;
                    }
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                }
            }
        }
    }
    
    func markAsRead(for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                let unread = chat.unread;
                if chat.markAsRead() {
                    self.unreadMessagesCount = self.unreadMessagesCount - unread;
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                }
            }
        }
    }
    
//    func newMessage(event: MessageModule.MessageReceivedEvent, timestamp: Date) {
//        guard let chat = event.chat as? DBChat, let message = event.message.body else {
//            return;
//        }
//
//        guard chat.updateLastMessage(message, timestamp: timestamp) else {
//            return;
//        }
//
//        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
//    }
    
//    fileprivate func getOrCreateAccountChats(account: BareJID) -> AccountChats {
//        guard let accountChats = chats[account] else {
//            let accountChats = AccountChats();
//            chats[account] = accountChats;
//            return accountChats;
//        }
//        return accountChats;
//    }
    
    fileprivate func createChat(account: BareJID, chat: ChatProtocol) -> DBChatProtocol? {
        guard chat as? DBChatProtocol == nil else {
            return chat as? DBChatProtocol;
        }
        switch chat {
        case let c as Chat:
            let params: [String: Any?] = [ "account": account, "jid": c.jid.bareJid, "timestamp": Date(), "type": 0 ];
            let id = try! self.openChatStmt.insert(params);
            return DBChat(id: id!, account: account, jid: c.jid.bareJid, timestamp: Date(), lastMessage: getLastMessage(for: account, jid: chat.jid.bareJid), unread: 0);
        case let r as Room:
            let params: [String: Any?] = [ "account": account, "jid": r.roomJid, "timestamp": Date(), "type": 1, "nickname": r.nickname, "password": r.password];
            let id = try! self.openRoomStmt.insert(params);
            return DBRoom(id: id!, context: r.context, account: account, roomJid: r.roomJid, nickname: r.nickname, password: r.password, timestamp: Date(), lastMessage: getLastMessage(for: account, jid: chat.jid.bareJid), unread: 0);
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
                return cursor["data"];
            }
        }
    }
    
    func loadChats(for account: BareJID, context: Context) {
        dispatcher.async {
            guard self.chats[account] == nil else {
                return;
            }
            
            let stmt = try! DBConnection.main.prepareStatement(DBChatStore.LOAD_CHATS);
            let chats = try! stmt.query(["account": account]) { cursor -> DBChatProtocol? in
                let id: Int = cursor["id"]!;
                let type: Int = cursor["type"]!;
                let jid: BareJID = cursor["jid"]!;
                let creationTimestamp: Date = cursor["creation_timestamp"]!;
                let lastMessageTimestamp: Date = cursor["timestamp"]!;
                let lastMessage: String? = cursor["data"];
                let unread: Int = cursor["unread"]!;
                
                let timestamp = creationTimestamp.compare(lastMessageTimestamp) == .orderedAscending ? lastMessageTimestamp : creationTimestamp;
                
                switch type {
                case 1:
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
            
                    let room = DBRoom(id: id, context: context, account: account, roomJid: jid, nickname: nickname, password: password, timestamp: timestamp, lastMessage: lastMessage, unread: unread);
                    if lastMessage != nil {
                        room.lastMessageDate = timestamp;
                    }
                    return room;
                default:
                    return DBChat(id: id, account: account, jid: jid, timestamp: timestamp, lastMessage: lastMessage, unread: unread);
                }
            }
            let accountChats = AccountChats(items: chats);
            self.chats[account] = accountChats;
            
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
            guard let accountChats = self.chats.removeValue(forKey: account) else {
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
    }
    
    class DBChat: Chat, DBChatProtocol {
        
        let id: Int;
        let account: BareJID;
        var timestamp: Date;
        var lastMessage: String? = nil;
        var unread: Int;
        
        override var jid: JID {
            get {
                return super.jid;
            }
            set {
                super.jid = newValue.withoutResource;
            }
        }
        
        init(id: Int, account: BareJID, jid: BareJID, timestamp: Date, lastMessage: String?, unread: Int) {
            self.id = id;
            self.account = account;
            self.timestamp = timestamp;
            self.lastMessage = lastMessage;
            self.unread = unread;
            super.init(jid: JID(jid), thread: nil);
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
        
        func markAsRead() -> Bool {
            guard unread > 0 else {
                return false;
            }
            unread = 0;
            return true
        }
        
        override func createMessage(_ body: String, type: StanzaType, subject: String?, additionalElements: [Element]?) -> Message {
            let stanza = super.createMessage(body, type: type, subject: subject, additionalElements: additionalElements);
            stanza.id = UUID().uuidString;
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

        init(id: Int, context: Context, account: BareJID, roomJid: BareJID, nickname: String, password: String?, timestamp: Date, lastMessage: String?, unread: Int) {
            self.id = id;
            self.account = account;
            self.timestamp = timestamp;
            self.lastMessage = lastMessage;
            self.unread = unread;
            super.init(context: context, roomJid: roomJid, nickname: nickname);
            setPassword(password);
        }
        
        fileprivate func setPassword(_ pass: String?) {
            self.password = pass;
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
        
        func markAsRead() -> Bool {
            guard unread > 0 else {
                return false;
            }
            unread = 0;
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

    func markAsRead() -> Bool;
    func updateLastMessage(_ message: String?, timestamp: Date, isUnread: Bool) -> Bool;

}
