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
import Combine

extension Query {
    static let chatInsert = Query("INSERT INTO chats (account, jid, timestamp, type, options) VALUES (:account, :jid, :timestamp, :type, :options)");
    static let chatDelete = Query("DELETE FROM chats WHERE id = :id");
    static let chatFindAllForAccount = Query("SELECT c.id, c.type, c.jid, c.name, c.nickname, c.password, c.timestamp as creation_timestamp, last.timestamp as timestamp, last1.item_type, last1.data, last1.state, last1.encryption as lastEncryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(ConversationEntryState.incoming(.received).rawValue), \(ConversationEntryState.incoming_error(.received).rawValue), \(ConversationEntryState.outgoing_error(.received).rawValue)) AND ch2.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue),\(ItemType.location.rawValue))) as unread, c.options, last1.author_nickname FROM chats c LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue), \(ItemType.location.rawValue)) GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account LEFT JOIN chat_history last1 ON last1.account = c.account AND last1.jid = c.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue), \(ItemType.location.rawValue)) WHERE c.account = :account");
    static let chatUpdateOptions = Query("UPDATE chats SET options = :options WHERE account = :account AND jid = :jid");
    static let chatUpdateName = Query("UPDATE chats SET name = :name WHERE account = :account AND jid = :jid");
    static let chatUpdateMessageDraft = Query("UPDATE chats SET message_draft = ? WHERE account = ? AND jid = ? AND IFNULL(message_draft, '') <> IFNULL(?, '')");
    static let chatFindMessageDraft = Query("SELECT message_draft FROM chats WHERE account = :account AND jid = :jid");
    static let chatFindLastActivity = Query("SELECT last.timestamp as timestamp, last1.item_type, last1.data, last1.encryption, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(ConversationEntryState.incoming(.received).rawValue), \(ConversationEntryState.incoming_error(.received).rawValue), \(ConversationEntryState.outgoing_error(.received).rawValue))) as unread, last1.author_nickname FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue), \(ItemType.location.rawValue)) GROUP BY ch.account, ch.jid) last LEFT JOIN chat_history last1 ON last1.account = last.account AND last1.jid = last.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue), \(ItemType.location.rawValue))");
}

open class DBChatStore: ContextLifecycleAware {

    static let instance: DBChatStore = DBChatStore.init();

    public let conversationDispatcher = QueueDispatcher(label: "ConversationDispatcher", attributes: .concurrent)
    public let dispatcher: QueueDispatcher;

    private var accountChats = [BareJID: AccountConversations]();
    
    @Published
    public private(set) var conversations: [Conversation] = [];
    private let conversationsDispatcher = QueueDispatcher(label: "conversationsDispatcher");

    public let conversationsLifecycleQueue = QueueDispatcher(label: "conversationsLifecycle");
    
    @Published
    fileprivate(set) var unreadMessagesCount: Int = 0;

    private var cancellables: Set<AnyCancellable> = [];
    
    public init() {
        self.dispatcher = QueueDispatcher(label: "db_chat_store");
    }

    public func accountChats(for account: BareJID) -> AccountConversations? {
        return dispatcher.sync {
            return accountChats[account];
        }
    }

//    public func conversations() -> [Conversation] {
//        return dispatcher.sync(execute: {
//            return accountChats.values;
//        }).flatMap({ $0.items });
//    }
    
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
            if conversation.unread > 0 && !self.isMuted(conversation: conversation) {
                self.unreadMessagesCount = max(self.unreadMessagesCount - conversation.unread, 0)

                DBChatHistoryStore.instance.markAsRead(for: conversation, before: Date());
            }
        }
                
        return result;
    }

    func convert<T: Conversation>(items: [Conversation]) -> [T] {
        return items.filter({ $0 is T }).map({ $0 as! T});
    }
    
    public func createConversation<T: Conversation>(for account: BareJID, with jid: BareJID, execute: ()->Conversation) -> T? {
        if let conversation = dispatcher.sync(execute: {
            return accountChats[account];
        })?.open(with: jid, execute: {
            let conversation = execute();
            self.conversationDispatcher.async {
                self.conversations.append(conversation);
            }
            return conversation;
        }) as? T {
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

    func openConversation(account: BareJID, jid: BareJID, type: ConversationType, timestamp: Date = Date(), options: ChatOptionsProtocol?) throws -> Int {
        let params: [String: Any?] = [ "account": account, "jid": jid, "timestamp": Date(), "type": type.rawValue, "options": options];
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
            if let chat = self.conversation(for: account, with: jid) as? Chat {
                chat.update(remoteChatState: remoteChatState);
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
                
                let updated = conversation.update(lastActivity: lastActivity, timestamp: timestamp, isUnread: unread);
                if unread && !self.isMuted(conversation: conversation) {
                    self.unreadMessagesCount = self.unreadMessagesCount + 1;
                }

                if updated {
                    if let chat = conversation as? Chat {
                        if remoteChatState != nil {
                            chat.update(remoteChatState: remoteChatState);
                        } else {
                            if chat.remoteChatState == .composing {
                                chat.update(remoteChatState: .active);
                            }
                        }
                    }
                    self.refreshConversationsList();
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
                        self.unreadMessagesCount = max(self.unreadMessagesCount - (count ?? unread), 0);
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

    func refreshConversationsList() {
        self.conversationsDispatcher.sync {
            let items = self.conversations;
            self.conversations = items;
        }
    }
    
    func messageDraft(for account: BareJID, with jid: BareJID, completionHandler: @escaping (String?)->Void) {
        dispatcher.async {
            let text = try! Database.main.reader({ database -> String? in
                return try database.select(query: .chatFindMessageDraft, params: ["account": account, "jid": jid]).mapFirst({ $0.string(for: "message_draft") });
            })
            completionHandler(text);
        }
    }

    func storeMessage(draft: String?, for account: BareJID, with jid: BareJID) {
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.update(query: .chatUpdateMessageDraft, params: [draft, account, jid, draft]);
            })
        }
    }

    private func destroy(conversation: Conversation) {
        conversationsDispatcher.async {
            self.conversations.removeAll(where: { $0 === conversation })
        }
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
        return dispatcher.sync {
            return try! Database.main.reader({ database in
                try database.select(query: .chatFindLastActivity, params: ["account": account, "jid": jid]).mapFirst({ cursor -> LastChatActivity? in
                    let encryption = MessageEncryption(rawValue: cursor.int(for: "encryption") ?? 0) ?? .none;
                    let authorNickname: String? = cursor.string(for: "author_nickname");
                    switch encryption {
                    case .decrypted, .none:
                        let state = ConversationEntryState.from(code: cursor.int(for: "state") ?? 0, errorMessage: nil);
                        return LastChatActivity.from(itemType: ItemType(rawValue: cursor.int(for: "item_type") ?? -1), data: cursor["data"], direction: state.direction, sender: authorNickname);
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
    
    @available(*, deprecated, renamed: "lastActivity")
    public func getLastActivity(for account: BareJID, jid: BareJID) -> LastChatActivity? {
        lastActivity(for: account, jid: jid);
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
                    guard let jid = cursor.bareJid(for: "jid"), let creationTimestamp = cursor.date(for: "creation_timestamp") else {
                        return nil;
                    }
                    let lastMessageTimestamp = cursor.date(for: "timestamp");
                    let lastMessageEncryption = MessageEncryption(rawValue: cursor.int(for: "lastEncryption") ?? 0) ?? .none;
                    let lastActivity = cursor.int(for: "state") == nil ? nil : LastChatActivity.from(itemType: ItemType(rawValue: cursor.int(for: "item_type") ?? -1), data: lastMessageEncryption.message() ?? cursor.string(for: "data"), direction: ConversationEntryState.from(code: cursor.int(for: "state") ?? -1, errorMessage: nil).direction, sender: cursor.string(for: "author_nickname"));
                    let timestamp = lastMessageTimestamp == nil ? creationTimestamp : (creationTimestamp.compare(lastMessageTimestamp!) == .orderedAscending ? lastMessageTimestamp! : creationTimestamp);

                    switch type {
                    case .chat:
                        let options: ChatOptions? = cursor.object(for: "options");
                        return Chat(dispatcher: self.conversationDispatcher, context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options ?? ChatOptions());
                    case .room:
                        guard let options: RoomOptions = cursor.object(for: "options") else {
                            return nil;
                        }
                        let room = Room(dispatcher: self.conversationDispatcher, context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options);
                        return room;
                    case .channel:
                        guard let options: ChannelOptions = cursor.object(for: "options") else {
                            return nil;
                        }
                        return Channel(dispatcher: self.conversationDispatcher, context: context, channelJid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options, creationTimestamp: cursor.date(for: "creation_timestamp")!);
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
//                NotificationCenter.default.post(name: DBChatStore.CHAT_OPENED, object: item);
            }
            let items = accountConversation.items;
            self.conversationsDispatcher.async {
                self.conversations.append(contentsOf: items);
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
            }
            
            let removed = accountChats.items;
            self.conversationsDispatcher.async {
                self.conversations.removeAll(where: { it in removed.contains(where: { it === $0 }) })
            }
            
            if unread > 0 {
                self.unreadMessagesCount = max(self.unreadMessagesCount - unread, 0);
            }
        }
    }
    
    private func calculateChange(_ old: ConversationNotification, _ new: ConversationNotification) -> Bool? {
        if old == .none && new != .none {
            return true;
        } else if old != .none && new == .none {
            return false;
        }
        return nil;
    }

    open func update(options: ChatOptionsProtocol, for conversation: Conversation) {
        let notificationChange = calculateChange(conversation.notifications, options.notifications);
        dispatcher.async {
            try! Database.main.writer({ database in
                try database.update(query: .chatUpdateOptions, params: ["options": options, "account": conversation.account, "jid": conversation.jid]);
            })
            
            if conversation.unread > 0, let change = notificationChange {
                if change {
                    self.unreadMessagesCount = self.unreadMessagesCount + conversation.unread;
                } else {
                    self.unreadMessagesCount = max(self.unreadMessagesCount - conversation.unread, 0)
                }
            }
        }
    }
    
}
