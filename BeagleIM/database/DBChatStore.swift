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

open class DBChatStore {

    static let instance: DBChatStore = DBChatStore.init();

    static let CHAT_OPENED = Notification.Name("CHAT_OPENED");
    static let CHAT_CLOSED = Notification.Name("CHAT_CLOSED");
    static let CHAT_UPDATED = Notification.Name("CHAT_UPDATED");

    static let UNREAD_MESSAGES_COUNT_CHANGED = Notification.Name("UNREAD_NOTIFICATIONS_COUNT_CHANGED");

    public let dispatcher: QueueDispatcher;

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

    private func openConversation(account: BareJID, jid: BareJID, type: ConversationType, timestamp: Date = Date(), nickname: String? = nil, password: String? = nil, options: ChatOptionsProtocol?) throws -> Int {
        let params: [String: Any?] = [ "account": account, "jid": jid, "timestamp": Date(), "type": type.rawValue, "options": options, "nickname": nickname, "password": password];
        return try Database.main.writer({ database in
            try database.insert(query: .chatInsert, params: params);
            return database.lastInsertedRowId!;
        })
    }

    func createChannel(for account: BareJID, channelJid: BareJID, participantId: String, nick: String?, state: Channel.State) -> Result<DBChannel, ErrorCondition> {
        return dispatcher.sync {
            guard let accountChats = self.accountChats[account] else {
                return .failure(.undefined_condition);
            }
            guard let dbChat = accountChats.get(with: channelJid) else {
                let options = ChannelOptions(participantId: participantId, nick: nick, state: state);

                let id = try! self.openConversation(account: account, jid: channelJid, type: .channel, timestamp: Date(), options: options);
                let channel = DBChannel(id: id, account: account, jid: channelJid, timestamp: Date(), lastActivity: getLastActivity(for: account, jid: channelJid), unread: 0, options: options);

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
                let id = try! self.openConversation(account: account, jid: jid.bareJid, type: .chat, timestamp: Date(), options: nil);
                let chat = DBChat(id: id, account: account, jid: jid.bareJid, timestamp: Date(), lastActivity: getLastActivity(for: account, jid: jid.bareJid), unread: 0, options: ChatOptions());

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
                let id = try! self.openConversation(account: account, jid: roomJid, type: .room, timestamp: Date(), nickname: nickname, password: password, options: nil);
                let room = DBRoom(id: id, context: context, account: account, roomJid: roomJid, name: nil, nickname: nickname, password: password, timestamp: Date(), lastActivity: getLastActivity(for: account, jid: roomJid), unread: 0, options: RoomOptions());

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

                DBChatHistoryStore.instance.markAsRead(for: account, with: dbChat.jid.bareJid, before: Date());
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

    func process(chatState remoteChatState: ChatState, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) as? DBChat, chat.update(remoteChatState: remoteChatState) {
                NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: chat);
            }
        }
    }

    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, itemType: ItemType?, message: String?, state: MessageState, remoteChatState: ChatState? = nil, senderNickname: String? = nil, completionHandler: @escaping ()->Void) {
        let lastActivity = LastChatActivity.from(itemType: itemType, data: message, direction: state.direction, sender: senderNickname);
        newMessage(for: account, with: jid, timestamp: timestamp, lastActivity: lastActivity, state: state, remoteChatState: remoteChatState, completionHandler: completionHandler);
    }

    func newMessage(for account: BareJID, with jid: BareJID, timestamp: Date, lastActivity: LastChatActivity?, state: MessageState, remoteChatState: ChatState? = nil, completionHandler: @escaping ()->Void) {
        dispatcher.async {
            if let chat = self.getChat(for: account, with: jid) {
                let unread = lastActivity != nil && state.isUnread;
                if chat.updateLastActivity(lastActivity, timestamp: timestamp, isUnread: unread) {
                    if unread && !self.isMuted(chat: chat) {
                        self.unreadMessagesCount = self.unreadMessagesCount + 1;
                    }
                    if remoteChatState != nil {
                        _ = (chat as? DBChat)?.update(remoteChatState: remoteChatState);
                    } else {
                        if (chat as? DBChat)?.remoteChatState == .composing {
                            _ = (chat as? DBChat)?.update(remoteChatState: .active);
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
                    if try! Database.main.writer({ database -> Int in
                        try database.update(query: .chatUpdateName, params: ["account": account, "jid": jid, "name": name]);
                        return database.changes;
                    }) > 0 {
                        NotificationCenter.default.post(name: MucEventHandler.ROOM_NAME_CHANGED, object: chat);
                    }
                }
            }
        }
    }

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

    private func destroyChat(account: BareJID, chat: DBChatProtocol) {
        try! Database.main.writer({ database in
            try database.delete(query: .chatDelete, params: ["id": chat.id]);
        });
        if chat is DBRoom {
            DispatchQueue.global().async {
                DBChatHistorySyncStore.instance.removeSyncPeriods(forAccount: account, component: chat.jid.bareJid);
            }
        }
    }

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

            let chats = try! Database.main.reader({ database in
                return try database.select(query: .chatFindAllForAccount, params: ["account": account]).mapAll({ cursor -> DBChatProtocol? in
                    guard let type = ConversationType(rawValue: cursor.int(for: "type") ?? -1) else {
                        return nil;
                    }
                    let id = cursor.int(for: "id")!;
                    let unread = cursor.int(for: "unread") ?? 0;
                    guard let jid = cursor.bareJid(for: "jid"), let creationTimestamp = cursor.date(for: "creation_timestamp"), let lastMessageTimestamp = cursor.date(for: "timestamp") else {
                        return nil;
                    }
                    let lastMessageEncryption = MessageEncryption(rawValue: cursor.int(for: "lastEncryption") ?? 0) ?? .none;
                    let lastActivity = LastChatActivity.from(itemType: ItemType(rawValue: cursor.int(for: "item_type") ?? -1), data: lastMessageEncryption.message() ?? cursor.string(for: "data"), direction: MessageState(rawValue: cursor.int(for: "item_type") ?? -1)?.direction, sender: cursor.string(for: "author_nickname"));
                    let timestamp = creationTimestamp.compare(lastMessageTimestamp) == .orderedAscending ? lastMessageTimestamp : creationTimestamp;

                    switch type {
                    case .chat:
                        let options: ChatOptions? = cursor.object(for: "options");
                        return DBChat(id: id, account: account, jid: jid, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? ChatOptions());
                    case .room:
                        guard let nickname = cursor.string(for: "nickname") else {
                            return nil;
                        }
                        let options: RoomOptions? = cursor.object(for: "options");
                        let room = DBRoom(id: id, context: context, account: account, roomJid: jid, name: cursor.string(for: "name"), nickname: nickname, password: cursor.string(for: "password"), timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? RoomOptions());
                        if lastActivity != nil {
                            room.lastMessageDate = timestamp;
                        }
                        return room;
                    case .channel:
                        guard let options: ChannelOptions = cursor.object(for: "options") else {
                            return nil;
                        }
                        return DBChannel(id: id, account: account, jid: jid, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options);
                    }
                });
            })

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
            try! Database.main.writer({ database in
                try database.update(query: .chatUpdateOptions, params: ["options": options, "account": account, "jid": jid]);
            })

            if let c = self.getChat(for: account, with: jid) {
                switch c {
                case let chat as DBChat:
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
                case let room as DBRoom:
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
                case let channel as DBChannel:
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

    class DBChat: Chat, DBChatProtocol {

        let id: Int;
        let account: BareJID;
        var timestamp: Date;
        var lastActivity: LastChatActivity?;
        var unread: Int;
        fileprivate(set) var options: ChatOptions = ChatOptions();

        fileprivate var localChatState: ChatState = .active;
        private(set) var remoteChatState: ChatState? = nil;

        var notifications: ConversationNotification {
            return options.notifications;
        }

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
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) != .orderedDescending else {
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

        func update(remoteChatState state: ChatState?) -> Bool {
            // proper handle when we have the same state!!
            let prevState = remoteChatState;
            if prevState == .composing {
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
            return remoteChatState != prevState;
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

        var notifications: ConversationNotification {
            return options.notifications;
        }

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
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) != .orderedDescending else {
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

        override func createMessage(_ body: String?) -> Message {
            let message = super.createMessage(body);
            if message.id == nil {
                message.id = UUID().uuidString;
            }
            return message;
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

        var notifications: ConversationNotification {
            return options.notifications;
        }

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
            guard self.lastActivity == nil || self.timestamp.compare(timestamp) != .orderedDescending else {
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

fileprivate class AccountChats {

    private var chats = [BareJID: DBChatProtocol]();

    private let queue = DispatchQueue(label: "accountChats");

    var count: Int {
        return self.queue.sync(execute: {
            return self.chats.count;
        })
    }

    var items: [DBChatProtocol] {
        return self.queue.sync(execute: {
            return self.chats.values.map({ (chat) -> DBChatProtocol in
                return chat;
            });
        });
    }

    init(items: [DBChatProtocol]) {
        items.forEach { item in
            self.chats[item.jid.bareJid] = item;
        }
    }

    func open(chat: DBChatProtocol) -> DBChatProtocol {
        return self.queue.sync(execute: {
            var chats = self.chats;
            guard let existingChat = chats[chat.jid.bareJid] else {
                chats[chat.jid.bareJid] = chat;
                self.chats = chats;
                return chat;
            }
            return existingChat;
        });
    }

    func close(chat: DBChatProtocol) -> Bool {
        return self.queue.sync(execute: {
            var chats = self.chats;
            defer {
                self.chats = chats;
            }
            return chats.removeValue(forKey: chat.jid.bareJid) != nil;
        });
    }

    func isFor(jid: BareJID) -> Bool {
        return self.queue.sync(execute: {
            return self.chats[jid] != nil;
        });
    }

    func get(with jid: BareJID) -> DBChatProtocol? {
        return self.queue.sync(execute: {
            let chats = self.chats;
            return chats[jid];
        });
    }

    func lastMessageTimestamp() -> Date {
        return self.queue.sync(execute: {
            var timestamp = Date(timeIntervalSince1970: 0);
            self.chats.values.forEach { (chat) in
                guard chat.lastActivity != nil else {
                    return;
                }
                timestamp = max(timestamp, chat.timestamp);
            }
            return timestamp;
        });
    }
}

public enum ConversationNotification: String {
    case none
    case mention
    case always
}

public protocol ChatOptionsProtocol: Codable, DatabaseConvertibleStringValue {

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

    var notifications: ConversationNotification { get }

    func markAsRead(count: Int) -> Bool;
    func updateLastActivity(_ lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool;
}

extension DBChatProtocol {
    static func from(cursor: Cursor) -> DBChatProtocol? {
        let type = cursor.int(for: "type");
        switch type {
        case 0:
            return DBChatStore.DBChat.from(cursor: cursor);
        case 1:
            return DBChatStore.DBRoom.from(cursor: cursor);
        case 2:
            return DBChatStore.DBChannel.from(cursor: cursor);
        default:
            return nil;
        }
    }
}

enum ConversationType: Int {
    case chat = 0
    case room = 1
    case channel = 2
}

public enum LastChatActivity {
    case message(String, direction: MessageDirection, sender: String?)
    case attachment(String, direction: MessageDirection, sender: String?)
    case invitation(String, direction: MessageDirection, sender: String?)

    static func from(itemType: ItemType?, data: String?, direction: MessageDirection?, sender: String?) -> LastChatActivity? {
        guard let itemType = itemType, let direction = direction else {
            return nil;
        }
        switch itemType {
        case .message:
            return data == nil ? nil : .message(data!, direction: direction, sender: sender);
        case .invitation:
            return data == nil ? nil : .invitation(data!, direction: direction, sender: sender);
        case .attachment:
            return data == nil ? nil : .attachment(data!, direction: direction, sender: sender);
        case .linkPreview:
            return nil;
        case .messageRetracted, .attachmentRetracted:
            // TODO: Should we notify user that last message was retracted??
            return nil;
        }
    }
}

public enum ChatEncryption: String {
    case none = "none";
    case omemo = "omemo";
}
