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
import TigaseSQLite3

extension Query {
    static let chatInsert = Query("INSERT INTO chats (account, jid, timestamp, type, nickname, password, options) VALUES (:account, :jid, :timestamp, :type, :nickname, :password, :options)");
    static let chatDelete = Query("DELETE FROM chats WHERE id = :id");
    static let chatFindAllForAccount = Query("SELECT c.id, c.type, c.jid, c.name, c.nickname, c.password, c.timestamp as creation_timestamp, last.timestamp as timestamp, last1.item_type, last1.data, last1.encryption as lastEncryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue)) AND ch2.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) as unread, c.options, last1.author_nickname FROM chats c LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue)) GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account LEFT JOIN chat_history last1 ON last1.account = c.account AND last1.jid = c.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue)) WHERE c.account = :account");
    static let chatUpdateOptions = Query("UPDATE chats SET options = :options WHERE account = :account AND jid = :jid");
    static let chatUpdateName = Query("UPDATE chats SET name = :name WHERE account = :account AND jid = :jid");
    static let chatUpdateMessageDraft = Query("UPDATE chats SET message_draft = :draft WHERE account = :account AND jid = :jid AND IFNULL(message_draft, '') <> IFNULL(:draft, '')");
    static let chatFindMessageDraft = Query("SELECT message_draft FROM chats WHERE account = :account AND jid = :jid");
    static let chatFindLastActivity = Query("SELECT last.timestamp as timestamp, last1.item_type, last1.data, last1.encryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(MessageState.incoming_unread.rawValue), \(MessageState.incoming_error_unread.rawValue), \(MessageState.outgoing_error_unread.rawValue))) as unread, last1.author_nickname FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue)) GROUP BY ch.account, ch.jid) last LEFT JOIN chat_history last1 ON last1.account = last.account AND last1.jid = last.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))");
}

open class DBChatStore: ContextLifecycleAware {

    static let instance: DBChatStore = DBChatStore.init();

    static let CHAT_OPENED = Notification.Name("CHAT_OPENED");
    static let CHAT_CLOSED = Notification.Name("CHAT_CLOSED");
    static let CHAT_UPDATED = Notification.Name("CHAT_UPDATED");

    static let UNREAD_MESSAGES_COUNT_CHANGED = Notification.Name("UNREAD_NOTIFICATIONS_COUNT_CHANGED");

    public let dispatcher: QueueDispatcher;

    private var accountChats = [BareJID: AccountConversations]();
    
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
    }

    public func accountChats(for account: BareJID) -> AccountConversations? {
        return dispatcher.sync {
            return accountChats[account];
        }
    }

    public func conversations() -> [Conversation] {
        return dispatcher.sync(execute: {
            return accountChats.values;
        }).flatMap({ $0.items });
    }
    
    public func conversations(for account: BareJID) -> [Conversation] {
        return dispatcher.sync(execute: {
            return accountChats[account];
        })?.items ?? [];
    }
    
    public func conversation(for account: BareJID, with jid: BareJID) -> Conversation? {
        return dispatcher.sync(execute: {
            return accountChats[account];
        })?.get(with: jid);
    }
    
    public func close(conversation: Conversation) -> Bool {
        let result = dispatcher.sync(execute: {
            return accountChats[conversation.account];
        })?.close(conversation: conversation, execute: {
            self.destroy(conversation: conversation);
        }) ?? false;
        
        if result {
            NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: conversation);
        }
        
        return result;
    }

    func convert<T: Conversation>(items: [Conversation]) -> [T] {
        return items.filter({ $0 is T }).map({ $0 as! T});
    }
    
    public func createConversation<T: Conversation>(for account: BareJID, with jid: BareJID, execute: ()->Conversation) -> T? {
        if let conversation = dispatcher.sync(execute: {
            return accountChats[account];
        })?.open(with: jid, execute: execute) as? T {
            NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: conversation);
            return conversation;
        }
        return nil;
    }
    
    public func initialize(context: Context) {
        loadChats(for: context.userBareJid, context: context);
    }
    
    public func deinitialize(context: Context) {
        unloadChats(for: context.userBareJid);
    }

    func openConversation(account: BareJID, jid: BareJID, type: ConversationType, timestamp: Date = Date(), nickname: String? = nil, password: String? = nil, options: ChatOptionsProtocol?) throws -> Int {
        let params: [String: Any?] = [ "account": account, "jid": jid, "timestamp": Date(), "type": type.rawValue, "options": options, "nickname": nickname, "password": password];
        return try Database.main.writer({ database in
            try database.insert(query: .chatInsert, params: params);
            return database.lastInsertedRowId!;
        })
    }

    func isMuted(conversation: Conversation) -> Bool {
        return conversation.notifications == .none;
    }

    func closeAll(for account: BareJID) {
        dispatcher.async {
            let items = self.conversations(for: account)
            for conversation in items {
                _ = self.close(conversation: conversation);
            }
        }
    }

    func process(chatState remoteChatState: ChatState, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            if let chat = self.conversation(for: account, with: jid) as? Chat, chat.update(remoteChatState: remoteChatState) {
                NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
            }
        }
    }

    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, itemType: ItemType?, message: String?, state: ConversationEntryState, remoteChatState: ChatState? = nil, senderNickname: String? = nil, completionHandler: @escaping ()->Void) {
        let lastActivity = LastChatActivity.from(itemType: itemType, data: message, direction: state.direction, sender: senderNickname);
        newMessage(for: account, with: jid, timestamp: timestamp, lastActivity: lastActivity, state: state, remoteChatState: remoteChatState, completionHandler: completionHandler);
    }

    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, lastActivity: LastChatActivity?, state: ConversationEntryState, remoteChatState: ChatState? = nil, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            if let conversation = self.conversation(for: account, with: jid) {
                let unread = lastActivity != nil && state.isUnread;
                if conversation.updateLastActivity(lastActivity, timestamp: timestamp, isUnread: unread) {
                    if unread && !self.isMuted(conversation: conversation) {
                        self.unreadMessagesCount = self.unreadMessagesCount + 1;
                    }
                    if let chat = conversation as? Chat {
                        if remoteChatState != nil {
                            _ = chat.update(remoteChatState: remoteChatState);
                        } else {
                            if chat.remoteChatState == .composing {
                                _ = chat.update(remoteChatState: .active);
                            }
                        }
                    }
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: conversation);
                }
            }
            completionHandler();
        }
    }

    func markAsRead(for account: BareJID, with jid: BareJID, count: Int? = nil) {
        dispatcher.async {
            if let conversation = self.conversation(for: account, with: jid) {
                let unread = conversation.unread;
                if conversation.markAsRead(count: count ?? unread) {
                    if !self.isMuted(conversation: conversation) {
                        self.unreadMessagesCount = self.unreadMessagesCount - (count ?? unread);
                    }
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: conversation);
                }
            }
        }
    }

    func updateRoomName(for account: BareJID, with jid: BareJID, name: String?) {
        dispatcher.async {
            if let conversation = self.conversation(for: account, with: jid) {
                if let room = conversation as? Room, room.name != name {
                    room.name = name;
                    if try! Database.main.writer({ database -> Int in
                        try database.update(query: .chatUpdateName, params: ["account": account, "jid": jid, "name": name]);
                        return database.changes;
                    }) > 0 {
                        NotificationCenter.default.post(name: MucEventHandler.ROOM_NAME_CHANGED, object: conversation);
                    }
                }
            }
        }
    }

    func resetChatStates(for account: BareJID) {
        dispatcher.async {
            for conversation in self.conversations(for: account) {
                if let chat = conversation as? Chat {
                    chat.update(remoteChatState: nil);
                    chat.localChatState = .active;
                }
            }
        }
    }

    func messageDraft(for account: BareJID, with jid: BareJID, completionHandler: @escaping (String?)->Void) {
        dispatcher.async {
            let text = try! Database.main.reader({ database -> String? in
                return try database.select(query: .chatFindMessageDraft, params: ["account": account, "jid": jid]).string(for: "message_draft");
            })
            completionHandler(text);
        }
    }

    func storeMessage(draft: String?, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.update(query: .chatUpdateMessageDraft, params: ["account": account, "jid": jid, "draft": draft]);
            })
        }
    }

    private func destroy(conversation: Conversation) {
        try! Database.main.writer({ database in
            try database.delete(query: .chatDelete, params: ["id": conversation.id]);
        });
        if conversation is Room {
            DispatchQueue.global().async {
                DBChatHistorySyncStore.instance.removeSyncPeriods(forAccount: conversation.account, component: conversation.jid);
            }
        }
    }

    public func lastActivity(for account: BareJID, jid: BareJID) -> LastChatActivity? {
        return getLastActivity(for: account, jid: jid)
    }
    
    @available(*, deprecated, renamed: "lastActivity")
    public func getLastActivity(for account: BareJID, jid: BareJID) -> LastChatActivity? {
        return dispatcher.sync {
            return try! Database.main.reader({ database in
                try database.select(query: .chatFindLastActivity, params: ["account": account, "jid": jid]).mapFirst({ cursor -> LastChatActivity? in
                    let encryption = MessageEncryption(rawValue: cursor.int(for: "encryption") ?? 0) ?? .none;
                    let authorNickname: String? = cursor.string(for: "author_nickname");
                    switch encryption {
                    case .decrypted, .none:
                        if let state = MessageState(rawValue: cursor.int(for: "state") ?? 0) {
                            return LastChatActivity.from(itemType: ItemType(rawValue: cursor.int(for: "item_type") ?? -1), data: cursor["data"], direction: state.direction, sender: authorNickname);
                        } else {
                            return nil;
                        }
                    default:
                        if let message = encryption.message() {
                            return .message(message, direction: .incoming, sender: nil);
                        } else {
                            return nil;
                        }
                    }
                });
            })
        }
    }

    func loadChats(for account: BareJID, context: Context) {
        dispatcher.async {
            guard self.accountChats[account] == nil else {
                return;
            }

            let conversations = try! Database.main.reader({ database in
                return try database.select(query: .chatFindAllForAccount, params: ["account": account]).mapAll({ cursor -> Conversation? in
                    guard let type = ConversationType(rawValue: cursor.int(for: "type") ?? -1) else {
                        return nil;
                    }
                    let id = cursor.int(for: "id")!;
                    let unread = cursor.int(for: "unread") ?? 0;
                    guard let jid = cursor.bareJid(for: "jid"), let creationTimestamp = cursor.date(for: "creation_timestamp"), let lastMessageTimestamp = cursor.date(for: "timestamp") else {
                        return nil;
                    }
                    let lastMessageEncryption = MessageEncryption(rawValue: cursor.int(for: "lastEncryption") ?? 0) ?? .none;
                    let lastActivity = LastChatActivity.from(itemType: ItemType(rawValue: cursor.int(for: "item_type") ?? -1), data: lastMessageEncryption.message() ?? cursor.string(for: "data"), direction: MessageState(rawValue: cursor.int(for: "item_type") ?? -1)?.direction ?? .incoming, sender: cursor.string(for: "author_nickname"));
                    let timestamp = creationTimestamp.compare(lastMessageTimestamp) == .orderedAscending ? lastMessageTimestamp : creationTimestamp;

                    switch type {
                    case .chat:
                        let options: ChatOptions? = cursor.object(for: "options");
                        return Chat(context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? ChatOptions());
                    case .room:
                        print("loading room:", jid, "with:", timestamp, creationTimestamp, lastMessageTimestamp);
                        guard let nickname = cursor.string(for: "nickname") else {
                            return nil;
                        }
                        let options: RoomOptions? = cursor.object(for: "options");
                        let room = Room(context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? RoomOptions(), name: cursor.string(for: "name"), nickname: nickname, password: cursor.string(for: "password"));
                        return room;
                    case .channel:
                        guard let options: ChannelOptions = cursor.object(for: "options") else {
                            return nil;
                        }
                        return Channel(context: context, channelJid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options);
                    }
                });
            })

            let accountConversation = AccountConversations(items: conversations);
            self.accountChats[account] = accountConversation;

            var unread = 0;
            for item in conversations {
                if !self.isMuted(conversation: item) {
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
                if !self.isMuted(conversation: item) {
                    unread = unread + item.unread;
                }
                NotificationCenter.default.post(name: DBChatStore.CHAT_CLOSED, object: item);
            }
            if unread > 0 {
                self.unreadMessagesCount = self.unreadMessagesCount - unread;
            }
        }
    }

    // FIXME: move to the conversation object!
    open func updateOptions<T>(for account: BareJID, jid: BareJID, options: T, completionHandler: (()->Void)?) where T: ChatOptionsProtocol {
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.update(query: .chatUpdateOptions, params: ["options": options, "account": account, "jid": jid]);
            })

            if let c = self.conversation(for: account, with: jid) {
                switch c {
                case let chat as Chat:
                    if chat.unread > 0 {
                        if chat.options.notifications == .none && options.notifications != .none {
                            self.unreadMessagesCount = self.unreadMessagesCount + chat.unread;
                        } else if chat.options.notifications != .none && options.notifications == .none {
                            self.unreadMessagesCount = self.unreadMessagesCount - chat.unread;
                        }
                    }
                    chat.options = options as! ChatOptions;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                case let room as Room:
                    if room.unread > 0 {
                        if room.options.notifications == .none && options.notifications != .none {
                            self.unreadMessagesCount = self.unreadMessagesCount + room.unread;
                        } else if room.options.notifications != .none && options.notifications == .none {
                            self.unreadMessagesCount = self.unreadMessagesCount - room.unread;
                        }
                    }
                    room.options = options as! RoomOptions;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                case let channel as Channel:
                    if channel.unread > 0 {
                        if channel.options.notifications == .none && options.notifications != .none {
                            self.unreadMessagesCount = self.unreadMessagesCount + channel.unread;
                        } else if channel.options.notifications != .none && options.notifications == .none {
                            self.unreadMessagesCount = self.unreadMessagesCount - channel.unread;
                        }
                    }
                    channel.options = options as! ChannelOptions;
                    channel.nickname = channel.options.nick;
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: c, userInfo: nil);
                    }
                default:
                    break;
                }
            }
            completionHandler?();
        }
    }
}
