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

open class DBChatStore {
    
    static let instance: DBChatStore = DBChatStore.init();
    
    static let CHAT_OPENED = Notification.Name("CHAT_OPENED");
    static let CHAT_CLOSED = Notification.Name("CHAT_CLOSED");
    static let CHAT_UPDATED = Notification.Name("CHAT_UPDATED");
    
    static let UNREAD_MESSAGES_COUNT_CHANGED = Notification.Name("UNREAD_NOTIFICATIONS_COUNT_CHANGED");
    
    fileprivate static let OPEN_CHAT = "INSERT INTO chats (account, jid, timestamp, type) VALUES (:account, :jid, :timestamp, :type)";
    fileprivate static let OPEN_ROOM = "INSERT INTO chats (account, jid, timestamp, type, nickname, password) VALUES (:account, :jid, :timestamp, :type, :nickname, :password)";
    fileprivate static let OPEN_CHANNEL = "INSERT INTO chats (account, jid, timestamp, type, options) VALUES (:account, :jid, :timestamp, :type, :options)";
    fileprivate static let CLOSE_CHAT = "DELETE FROM chats WHERE id = :id";
    fileprivate static let LOAD_CHATS = "SELECT c.id, c.type, c.jid, c.name, c.nickname, c.password, c.timestamp as creation_timestamp, last.timestamp as timestamp, last1.item_type, last1.data, last1.encryption as lastEncryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue)) AND ch2.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) as unread, c.options, last1.author_nickname FROM chats c LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue)) GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account LEFT JOIN chat_history last1 ON last1.account = c.account AND last1.jid = c.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue)) WHERE c.account = :account";
    fileprivate static let GET_LAST_MESSAGE = "SELECT last.timestamp as timestamp, last1.item_type, last1.data, last1.encryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread, last1.author_nickname FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue)) GROUP BY ch.account, ch.jid) last LEFT JOIN chat_history last1 ON last1.account = last.account AND last1.jid = last.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))";
    fileprivate static let GET_LAST_MESSAGE_TIMESTAMP_FOR_ACCOUNT = "SELECT max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.state <> \(MessageState.outgoing_unsent.rawValue)";
    fileprivate static let UPDATE_CHAT_NAME = "UPDATE chats SET name = :name WHERE account = :account AND jid = :jid";
    fileprivate static let UPDATE_CHAT_OPTIONS = "UPDATE chats SET options = ? WHERE account = ? AND jid = ?";
    fileprivate static let CHANGE_CHAT_ENCRYPTION = "UPDATE chats SET encryption = :encryption WHERE account = :account AND jid = :jid";
    fileprivate static let UPDATE_MESSAGE_DRAFT = "UPDATE chats SET message_draft = ? WHERE account = ? AND jid = ? AND IFNULL(message_draft, '') <> IFNULL(?, '')";
    fileprivate static let GET_MESSAGE_DRAFT = "SELECT message_draft FROM chats WHERE account = ? AND jid = ?";
    public let dispatcher: QueueDispatcher;

    fileprivate let closeChatStmt: DBStatement;
    fileprivate let openChatStmt: DBStatement;
    fileprivate let openRoomStmt: DBStatement;
    fileprivate let openChannelStmt: DBStatement;
    fileprivate let getLastMessageStmt: DBStatement;
    fileprivate let getLastMessageTimestampForAccountStmt: DBStatement;
    fileprivate let updateChatOptionsStmt: DBStatement;
    fileprivate let updateChatNameStmt: DBStatement;
    fileprivate let changeChatEncryptionStmt: DBStatement;
    fileprivate let updateMessageDraftStmt: DBStatement;
    fileprivate let getMessageDraftStmt: DBStatement;


    private var accountChats = [BareJID: AccountChats]();
    
    fileprivate(set) var unreadMessagesCount: Int = 0 {
        didSet {
            let value = self.unreadMessagesCount;
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: value);
            }
        }
    }

    public init() {
        self.dispatcher = QueueDispatcher(label: "db_chat_store");
        
        openChatStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_CHAT);
        openRoomStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_ROOM);
        openChannelStmt = try! DBConnection.main.prepareStatement(DBChatStore.OPEN_CHANNEL);
        closeChatStmt = try! DBConnection.main.prepareStatement(DBChatStore.CLOSE_CHAT);
        getLastMessageStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_LAST_MESSAGE);
        getLastMessageTimestampForAccountStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_LAST_MESSAGE_TIMESTAMP_FOR_ACCOUNT);
        updateChatNameStmt = try! DBConnection.main.prepareStatement(DBChatStore.UPDATE_CHAT_NAME);
        updateChatOptionsStmt = try! DBConnection.main.prepareStatement(DBChatStore.UPDATE_CHAT_OPTIONS);
        changeChatEncryptionStmt = try! DBConnection.main.prepareStatement(DBChatStore.CHANGE_CHAT_ENCRYPTION);
        updateMessageDraftStmt = try! DBConnection.main.prepareStatement(DBChatStore.UPDATE_MESSAGE_DRAFT);
        getMessageDraftStmt = try! DBConnection.main.prepareStatement(DBChatStore.GET_MESSAGE_DRAFT);
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
    
    private func mapChats<T>(for account: BareJID, map: (AccountChats?)->T) -> T {
        return dispatcher.sync {
            return map(accountChats[account]);
        }
    }
    
    func getChat(for account: BareJID, with jid: BareJID) -> DBChatProtocol? {
        return dispatcher.sync {
            if let accountChats = self.accountChats[account] {
                return accountChats.get(with: jid);
            }
            return nil;
        }
    }
    
    func createChannel(for account: BareJID, channelJid: BareJID, participantId: String, nick: String?, state: Channel.State) -> Result<DBChannel, ErrorCondition> {
        return dispatcher.sync {
            let accountChats = self.accountChats[account]!;
            guard let dbChat = accountChats.get(with: channelJid) else {
                let options = ChannelOptions(participantId: participantId, nick: nick, state: state);
                guard let data = try? JSONEncoder().encode(options), let dataStr = String(data: data, encoding: .utf8) else {
                    return .failure(.bad_request);
                }
                
                let params: [String: Any?] = [ "account": account, "jid": channelJid, "timestamp": Date(), "type": 2, "options": dataStr];
                let id = try! self.openChannelStmt.insert(params);
                let channel = DBChannel(id: id!, account: account, jid: channelJid, timestamp: Date(), lastActivity: getLastActivity(for: account, jid: channelJid), unread: 0, options: options);

                if let result = accountChats.open(chat: channel) as? DBChannel {
                    NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: result);
                    return .success(result);
                } else {
                    return .failure(.conflict);
                }
            }
            guard let channel = dbChat as? DBChannel else {
                return .failure(.conflict);
            }
            return .success(channel);
        }

    }
    
    func createChat(for account: BareJID, jid: JID, thread: String?) -> Result<DBChat, ErrorCondition> {
        return dispatcher.sync {
            let accountChats = self.accountChats[account]!;
            guard let dbChat = accountChats.get(with: jid.bareJid) else {
                let params: [String: Any?] = [ "account": account, "jid": jid.bareJid, "timestamp": Date(), "type": 0];
                let id = try! self.openChatStmt.insert(params);
                let chat = DBChat(id: id!, account: account, jid: jid.bareJid, timestamp: Date(), lastActivity: getLastActivity(for: account, jid: jid.bareJid), unread: 0, options: ChatOptions());

                if let result = accountChats.open(chat: chat) as? DBChat {
                    NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: result);
                    return .success(result);
                } else {
                    return .failure(.conflict);
                }
            }
            guard let chat = dbChat as? DBChat else {
                return .failure(.conflict);
            }
            return .success(chat);
        }
    }
    
    func createRoom(for account: BareJID, context: Context, roomJid: BareJID, nickname: String, password: String?) -> Result<DBRoom, ErrorCondition> {
        return dispatcher.sync {
            let accountChats = self.accountChats[account]!;
            guard let dbChat = accountChats.get(with: roomJid) else {
                let params: [String: Any?] = [ "account": account, "jid": roomJid, "timestamp": Date(), "type": 1, "nickname": nickname, "password": password];
                let id = try! self.openRoomStmt.insert(params);
                let room = DBRoom(id: id!, context: context, account: account, roomJid: roomJid, name: nil, nickname: nickname, password: password, timestamp: Date(), lastActivity: getLastActivity(for: account, jid: roomJid), unread: 0, options: RoomOptions());

                if let result = accountChats.open(chat: room) as? DBRoom {
                    NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: result);
                    return .success(result);
                } else {
                    return .failure(.conflict);
                }
            }
            guard let room = dbChat as? DBRoom else {
                return .failure(.conflict);
            }
            return .success(room);
        }
    }
        
    func isMuted(chat conv: DBChatProtocol) -> Bool {
        if let chat = conv as? DBChat {
            return chat.options.notifications == .none;
        }
        if let room = conv as? DBRoom {
            return room.options.notifications == .none;
        }
        return false;
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

            if dbChat.unread > 0 && !self.isMuted(chat: dbChat) {
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
        return dispatcher.sync {
            return try! self.getLastMessageTimestampForAccountStmt.findFirst(["account": account] as [String: Any?], map: { (cursor) -> Date? in
                return cursor["timestamp"];
            }) ?? Date(timeIntervalSince1970: 0);
        }
    }
    
    func process(chatState remoteChatState: ChatState, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                (chat as? DBChat)?.update(remoteChatState: remoteChatState);
                NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
            }
        }
    }
    
    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, itemType: ItemType?, message: String?, state: MessageState, remoteChatState: ChatState? = nil, senderNickname: String? = nil, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                let lastActivity = LastChatActivity.from(itemType: itemType, data: message, sender: senderNickname);
                if chat.updateLastActivity(lastActivity, timestamp: timestamp, isUnread: state.isUnread) {
                    if state.isUnread && !self.isMuted(chat: chat) {
                        self.unreadMessagesCount = self.unreadMessagesCount + 1;
                    }
                    if remoteChatState != nil {
                        (chat as? DBChat)?.update(remoteChatState: remoteChatState);
                    } else {
                        if (chat as? DBChat)?.remoteChatState == .composing {
                            (chat as? DBChat)?.update(remoteChatState: .active);
                        }
                    }
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
                }
            }
            completionHandler();
        }
    }
    
    func markAsRead(for account: BareJID, with jid: BareJID, count: Int? = nil) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                let unread = chat.unread;
                if chat.markAsRead(count: count ?? unread) {
                    if !self.isMuted(chat: chat) {
                        self.unreadMessagesCount = self.unreadMessagesCount - (count ?? unread);
                    }
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
    
//    func changeChatEncryption(for account: BareJID, with jid: BareJID, to encryption: ChatEncryption?, completionHandler: @escaping ()->Void) {
//        dispatcher.async {
//            if let c = self.getChat(for: account, with: jid) {
//                if let chat = c as? DBChat {
//                    chat.encryption = encryption;
//                }
//                if try! self.changeChatEncryptionStmt.update(["account": account, "jid": jid, "encryption": encryption?.rawValue] as [String: Any?]) > 0 {
//                    // encryption was changed, do we need to do anything else?
//                    completionHandler();
//                }
//            }
//        }
//    }
    
    func resetChatStates(for account: BareJID) {
        dispatcher.async {
            self.getChats(for: account).forEach { chat in
                (chat as? DBChat)?.update(remoteChatState: nil);
                (chat as? DBChat)?.localChatState = .active;
            }
        }
    }
        
    func messageDraft(for account: BareJID, with jid: BareJID, completionHandler: @escaping (String?)->Void) {
        dispatcher.async {
            let text = try! self.getMessageDraftStmt.queryFirstMatching(account, jid, forEachRowUntil: { (cursor) -> String? in
                return cursor["message_draft"];
            })
            completionHandler(text);
        }
    }
    
    func storeMessage(draft: String?, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            _ = try! self.updateMessageDraftStmt.update(draft, account, jid, draft);
        }
    }
        
    private func destroyChat(account: BareJID, chat: DBChatProtocol) {
        let params: [String: Any?] = ["id": chat.id];
        _ = try! self.closeChatStmt.update(params);
    }
    
    private func getLastActivity(for account: BareJID, jid: BareJID) -> LastChatActivity? {
        return dispatcher.sync {
            let params: [String: Any?] = ["account": account, "jid": jid];
            return try! self.getLastMessageStmt.queryFirstMatching(params) { cursor in
                let encryption = MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none;
                let authorNickname: String? = cursor["author_nickname"];
                switch encryption {
                case .decrypted, .none:
                    if let itemType: Int = cursor["item_type"] {
                        return LastChatActivity.from(itemType: ItemType(rawValue: itemType), data: cursor["data"], sender: authorNickname);
                    } else {
                        return nil;
                    }
                default:
                    if let message = encryption.message() {
                        return .message(message, sender: nil);
                    } else {
                        return nil;
                    }
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
                var lastActivity: LastChatActivity?;
                if let itemType: Int = cursor["item_type"] {
                    lastActivity = LastChatActivity.from(itemType: ItemType(rawValue: itemType), data: lastMessageEncryption.message() ?? cursor["data"], sender: cursor["author_nickname"]);
                }
                let unread: Int = cursor["unread"]!;
                let optionsStr: String? = cursor["options"];
                
                let timestamp = creationTimestamp.compare(lastMessageTimestamp) == .orderedAscending ? lastMessageTimestamp : creationTimestamp;
                
                switch type {
                case 1:
                    let nickname: String = cursor["nickname"]!;
                    let password: String? = cursor["password"];
                    let name: String? = cursor["name"];
            
                    var options: RoomOptions? = nil;
                    if optionsStr != nil, let data = optionsStr!.data(using: .utf8) {
                        options = try? JSONDecoder().decode(RoomOptions.self, from: data);
                    }
                    let room = DBRoom(id: id, context: context, account: account, roomJid: jid, name: name, nickname: nickname, password: password, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? RoomOptions());
                    if lastActivity != nil {
                        room.lastMessageDate = timestamp;
                    }
                    return room;
                case 2:
                    guard optionsStr != nil, let data = optionsStr!.data(using: .utf8), let options = try? JSONDecoder().decode(ChannelOptions.self, from: data) else {
                        return nil;
                    }
                    return DBChannel(id: id, account: account, jid: jid, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options);
                default:
                    var options: ChatOptions? = nil;
                    if optionsStr != nil, let data = optionsStr!.data(using: .utf8) {
                        options = try? JSONDecoder().decode(ChatOptions.self, from: data);
                    }
                    return DBChat(id: id, account: account, jid: jid, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? ChatOptions());
                }
            }
            let accountChats = AccountChats(items: chats);
            self.accountChats[account] = accountChats;
            
            var unread = 0;
            chats.forEach { item in
                if !self.isMuted(chat: item) {
                    unread = unread + item.unread;
                }
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
                if !self.isMuted(chat: item) {
                    unread = unread + item.unread;
                }
                NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: item);
            }
            if unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount - unread;
            }
        }
    }
    
    open func updateOptions<T>(for account: BareJID, jid: BareJID, options: T, completionHandler: (()->Void)?) where T: ChatOptionsProtocol {
        dispatcher.async {
            switch options {
            case let options as RoomOptions:
                let data = try? JSONEncoder().encode(options);
                let dataStr = data != nil ? String(data: data!, encoding: .utf8)! : nil;
                _ = try? self.updateChatOptionsStmt.update(dataStr, account, jid);
                if let c = self.getChat(for: account, with: jid) as? DBRoom {
                    if c.unread > 0 {
                        if c.options.notifications == .none && options.notifications != .none {
                            self.unreadMessagesCount = self.unreadMessagesCount + c.unread;
                        } else if c.options.notifications != .none && options.notifications == .none {
                            self.unreadMessagesCount = self.unreadMessagesCount - c.unread;
                        }
                    }
                    c.options = options;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                }
                completionHandler?();
            case let options as ChatOptions:
                let data = try? JSONEncoder().encode(options);
                let dataStr = data != nil ? String(data: data!, encoding: .utf8)! : nil;
                _ = try? self.updateChatOptionsStmt.update(dataStr, account, jid);
                if let c = self.getChat(for: account, with: jid) as? DBChat {
                    if c.unread > 0 {
                        if c.options.notifications == .none && options.notifications != .none {
                            self.unreadMessagesCount = self.unreadMessagesCount + c.unread;
                        } else if c.options.notifications != .none && options.notifications == .none {
                            self.unreadMessagesCount = self.unreadMessagesCount - c.unread;
                        }
                    }
                    c.options = options;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                }
                completionHandler?();
            case let options as ChannelOptions:
                if let data = try? JSONEncoder().encode(options), let dataStr = String(data: data, encoding: .utf8) {
                    _ = try? self.updateChatOptionsStmt.update(dataStr, account, jid);
                    if let c = self.getChat(for: account, with: jid)  as? DBChannel {
                        if c.unread > 0 {
                            if c.options.notifications == .none && options.notifications != .none {
                                self.unreadMessagesCount = self.unreadMessagesCount + c.unread;
                            } else if c.options.notifications != .none && options.notifications == .none {
                                self.unreadMessagesCount = self.unreadMessagesCount - c.unread;
                            }
                        }
                        c.options = options;
                        c.nickname = options.nick;
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                        }
                    }
                }
                completionHandler?();
            default:
                completionHandler?();
                break;
            }
        }
    }
    
    private class AccountChats {
        
        private var chats = [BareJID: DBChatProtocol]();
        
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
                guard chat.lastActivity != nil else {
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
        var lastActivity: LastChatActivity?;
        var unread: Int;
        fileprivate(set) var options: ChatOptions = ChatOptions();
        
        fileprivate var localChatState: ChatState = .active;
        private(set) var remoteChatState: ChatState? = nil;
        
        override var jid: JID {
            get {
                return super.jid;
            }
            set {
                super.jid = newValue.withoutResource;
            }
        }
        
        init(id: Int, account: BareJID, jid: BareJID, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: ChatOptions) {
            self.id = id;
            self.account = account;
            self.timestamp = timestamp;
            self.lastActivity = lastActivity;
            self.unread = unread;
            self.options = options;
            super.init(jid: JID(jid), thread: nil);
        }
     
        func updateLastActivity(_ lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool {
            if isUnread {
                unread = unread + 1;
            }
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
                return isUnread;
            }
            if lastActivity != nil {
                self.lastActivity = lastActivity;
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
        
        func modifyOptions(_ fn: @escaping (inout ChatOptions) -> Void, completionHandler: (() -> Void)?) {
            DispatchQueue.main.async {
                var options = self.options;
                fn(&options);
                DBChatStore.instance.updateOptions(for: self.account, jid: self.jid.bareJid, options: options, completionHandler: completionHandler);
            }
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
        
        private var remoteChatStateTimer: Foundation.Timer?;
        
        func update(remoteChatState state: ChatState?) {
            if let oldState = remoteChatState, oldState == .composing {
                remoteChatStateTimer?.invalidate();
                remoteChatStateTimer = nil;
            }
            self.remoteChatState = state;
            
            if state == .composing {
                DispatchQueue.main.async {
                    self.remoteChatStateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false, block: { [weak self] timer in
                    guard let that = self else {
                        return;
                    }
                    if that.remoteChatState == .composing {
                        that.remoteChatState = .active;
                        that.remoteChatStateTimer = nil;
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: that);
                    }
                });
                }
            }
        }
        
        override func createMessage(_ body: String, type: StanzaType = .chat, subject: String? = nil, additionalElements: [Element]? = nil) -> Message {
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
        var lastActivity: LastChatActivity?;
        var subject: String? = nil;
        var unread: Int;
        var name: String? = nil;
        fileprivate(set) var options: RoomOptions = RoomOptions();

        init(id: Int, context: Context, account: BareJID, roomJid: BareJID, name: String?, nickname: String, password: String?, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: RoomOptions) {
            self.id = id;
            self.account = account;
            self.timestamp = timestamp;
            self.lastActivity = lastActivity;
            self.unread = unread;
            self.name = name;
            self.options = options;
            super.init(context: context, roomJid: roomJid, nickname: nickname);
            setPassword(password);
        }
        
        fileprivate func setPassword(_ pass: String?) {
            self.password = pass;
        }
        
        func updateRoom(name: String?) {
            self.name = name;
        }
        
        func updateLastActivity(_ lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool {
            if isUnread {
                unread = unread + 1;
            }
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
                return isUnread;
            }
            
            if lastActivity != nil {
                self.lastActivity = lastActivity;
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

        func modifyOptions(_ fn: @escaping (inout RoomOptions) -> Void, completionHandler: (() -> Void)?) {
            DispatchQueue.main.async {
                var options = self.options;
                fn(&options);
                DBChatStore.instance.updateOptions(for: self.account, jid: self.jid.bareJid, options: options, completionHandler: completionHandler);
            }
        }

        override func createPrivateMessage(_ body: String?, recipientNickname: String) -> Message {
            let stanza = super.createPrivateMessage(body, recipientNickname: recipientNickname);
            let id = UUID().uuidString;
            stanza.id = id;
            stanza.originId = id;
            return stanza;
        }
    }
    
    class DBChannel: Channel, DBChatProtocol {
        
        let id: Int
        let account: BareJID
        var timestamp: Date
        var lastActivity: LastChatActivity?
        var unread: Int
        var name: String? {
            return options.name;
        }
        var description: String? {
            return options.description;
        }
        var options: ChannelOptions;
        
        init(id: Int, account: BareJID, jid: BareJID, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: ChannelOptions) {
            self.id = id;
            self.account = account;
            self.unread = unread;
            self.lastActivity = lastActivity;
            self.timestamp = timestamp;
            self.options = options;
            
            super.init(channelJid: jid, participantId: options.participantId, nickname: options.nick, state: options.state);
            self.lastMessageDate = lastActivity != nil ? timestamp : nil;
        }
        
        func markAsRead(count: Int) -> Bool {
            guard unread > 0 else {
                return false;
            }
            unread = max(unread - count, 0);
            return true
        }
        
        func updateLastActivity(_ lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool {
            if isUnread {
                unread = unread + 1;
            }
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) == .orderedAscending else {
                return isUnread;
            }
            
            if lastActivity != nil {
                self.lastActivity = lastActivity;
                self.timestamp = timestamp;
                self.lastMessageDate = timestamp;
            }
            
            return true;
        }
        
    }
}

public enum ConversationNotification: String {
    case none
    case mention
    case always
}

public protocol ChatOptionsProtocol {
    
    var notifications: ConversationNotification { get }
    
}

public struct RoomOptions: Codable, ChatOptionsProtocol {
    
    public var notifications: ConversationNotification = .mention;
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .mention;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if notifications != .mention {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case notifications = "notifications";
    }
}

public struct ChatOptions: Codable, ChatOptionsProtocol {
    
    var encryption: ChatEncryption?;
    public var notifications: ConversationNotification = .always;
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        if let val = try container.decodeIfPresent(String.self, forKey: .encryption) {
            encryption = ChatEncryption(rawValue: val);
        }
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .always;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if encryption != nil {
            try container.encode(encryption!.rawValue, forKey: .encryption);
        }
        if notifications != .always {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case encryption = "encrypt"
        case notifications = "notifications";
    }
}

public struct ChannelOptions: Codable, ChatOptionsProtocol {
    
    var participantId: String;
    var nick: String?;
    var name: String?;
    var description: String?;
    var state: Channel.State;
    public var notifications: ConversationNotification = .always;
    
    public init(participantId: String, nick: String?, state: Channel.State) {
        self.participantId = participantId;
        self.nick = nick;
        self.state = state;
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        participantId = try container.decode(String.self, forKey: .participantId);
        state = try container.decodeIfPresent(Int.self, forKey: .state).map({ Channel.State(rawValue: $0) ?? .joined }) ?? .joined;
        nick = try container.decodeIfPresent(String.self, forKey: .nick);
        name = try container.decodeIfPresent(String.self, forKey: .name);
        description = try container.decodeIfPresent(String.self, forKey: .description);
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .always;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(participantId, forKey: .participantId);
        try container.encode(state.rawValue, forKey: .state);
        try container.encodeIfPresent(nick, forKey: .nick);
        try container.encodeIfPresent(name, forKey: .name);
        try container.encodeIfPresent(description, forKey: .description);
        if notifications != .always {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case participantId = "participantId"
        case nick = "nick";
        case state = "state"
        case notifications = "notifications";
        case name = "name";
        case description = "desc";
    }
}

protocol DBChatProtocol: ChatProtocol {
    var id: Int { get };
    var account: BareJID { get }
    var timestamp: Date { get };
    var lastActivity: LastChatActivity? { get };
    var unread: Int { get }
    
    func markAsRead(count: Int) -> Bool;
    func updateLastActivity(_ lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool;

}

enum LastChatActivity {
    case message(String, sender: String?)
    case attachment(String, sender: String?)
    
    static func from(itemType: ItemType?, data: String?, sender: String?) -> LastChatActivity? {
        guard itemType != nil else {
            return nil;
        }
        switch itemType! {
        case .message:
            return data == nil ? nil : .message(data!, sender: sender);
        case .attachment:
            return data == nil ? nil : .attachment(data!, sender: sender);
        case .linkPreview:
            return nil;
        }
    }
}

public enum ChatEncryption: String {
    case none = "none";
    case omemo = "omemo";    
}
