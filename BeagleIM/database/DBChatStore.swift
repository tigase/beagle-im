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

import Foundation
import Martin
import TigaseSQLite3
import Combine

extension Query {
    static let chatInsert = Query("INSERT INTO chats (account, jid, timestamp, type, options) VALUES (:account, :jid, :timestamp, :type, :options)");
    static let chatDelete = Query("DELETE FROM chats WHERE id = :id");
    static let chatFindAllForAccount = Query("SELECT c.id, c.type, c.jid, c.name, c.nickname, c.password, c.timestamp as creation_timestamp, last.timestamp as timestamp, last1.item_type, last1.data, last1.state, last1.encryption, last1.fingerprint, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(ConversationEntryState.incoming(.received).rawValue), \(ConversationEntryState.incoming_error(.received).rawValue), \(ConversationEntryState.outgoing_error(.received).rawValue)) AND ch2.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue),\(ItemType.location.rawValue))) as unread, c.options, last1.author_nickname FROM chats c LEFT JOIN (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue),\(ItemType.location.rawValue)) GROUP BY ch.account, ch.jid) last ON c.jid = last.jid AND c.account = last.account LEFT JOIN chat_history last1 ON last1.account = c.account AND last1.jid = c.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue),\(ItemType.location.rawValue)) WHERE c.account = :account");
    static let chatUpdateOptions = Query("UPDATE chats SET options = :options WHERE account = :account AND jid = :jid");
    static let chatUpdateName = Query("UPDATE chats SET name = :name WHERE account = :account AND jid = :jid");
    static let chatUpdateMessageDraft = Query("UPDATE chats SET message_draft = ? WHERE account = ? AND jid = ? AND IFNULL(message_draft, '') <> IFNULL(?, '')");
    static let chatFindMessageDraft = Query("SELECT message_draft FROM chats WHERE account = :account AND jid = :jid");
    static let chatFindLastActivity = Query("SELECT last.timestamp as timestamp, last1.item_type, last1.data, last1.encryption, last1.fingerprint, (SELECT count(id) FROM chat_history ch2 WHERE ch2.account = last.account AND ch2.jid = last.jid AND ch2.state IN (\(ConversationEntryState.incoming(.received).rawValue), \(ConversationEntryState.incoming_error(.received).rawValue), \(ConversationEntryState.outgoing_error(.received).rawValue))) as unread, last1.author_nickname FROM (SELECT ch.account, ch.jid, max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.jid = :jid AND ch.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue),\(ItemType.location.rawValue)) GROUP BY ch.account, ch.jid) last LEFT JOIN chat_history last1 ON last1.account = last.account AND last1.jid = last.jid AND last1.timestamp = last.timestamp AND last1.item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue),\(ItemType.location.rawValue))");
}

open class DBChatStore: ContextLifecycleAware {

    static let instance: DBChatStore = DBChatStore.init();

    public let queue: DispatchQueue;
    
    let accountsConversations = Conversations();
    
    public var conversations: [Conversation] {
        return queue.sync(execute: {
            return accountsConversations.items;
        })
    }
    
    public var conversationsPublisher: Published<[Conversation]>.Publisher {
        return accountsConversations.$items;
    }
    
    public var unreadMessageCountPublisher: Published<Int>.Publisher {
        return accountsConversations.$unreadMessagesCount;
    }

    public let conversationsEventsPublisher = PassthroughSubject<ConversationEvent,Never>();
    
    private var cancellables: Set<AnyCancellable> = [];
    
    public init() {
        self.queue = DispatchQueue(label: "db_chat_store");
    }
    
    public func conversations(for account: BareJID) -> [Conversation] {
        return queue.sync(execute: {
            return accountsConversations.conversations(for: account);
        }) ?? [];
    }

    public func conversation(for account: BareJID, with jid: BareJID) -> Conversation? {
        return queue.sync(execute: {
            return accountsConversations.conversation(for: account, with: jid);
        })
    }

    public func close(conversation: Conversation) -> Bool {
        return queue.sync {
            guard accountsConversations.remove(conversation) else {
                return false;
            }
            conversationsEventsPublisher.send(.destroyed(conversation));
            try! Database.main.writer({ database in
                try database.delete(query: .chatDelete, params: ["id": conversation.id]);
            });
            if conversation is Room {
                DispatchQueue.global().async {
                    DBChatHistorySyncStore.instance.removeSyncPeriods(forAccount: conversation.account, component: conversation.jid);
                }
            }
            if conversation.unread > 0 {
                DBChatHistoryStore.instance.markAsRead(for: conversation, before: Date());
            }
            return true;
        }
    }

    func convert<T: Conversation>(items: [Conversation]) -> [T] {
        return items.filter({ $0 is T }).map({ $0 as! T});
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

    func closeAll(for account: BareJID) {
        queue.async {
            if let items = self.accountsConversations.conversations(for: account) {
                for conversation in items {
                    _ = self.close(conversation: conversation);
                }
            }
        }
    }

    func process(chatState remoteChatState: ChatState, for account: BareJID, with jid: BareJID) {
        queue.async {
            if let chat = self.accountsConversations.conversation(for: account, with: jid) as? Chat {
                chat.update(remoteChatState: remoteChatState);
            }
        }
    }

    func newActivity(_ activity: LastChatActivity, isUnread: Bool, for account: BareJID, with jid: BareJID, completionHandler: @escaping ()->Void) {
        queue.async {
            if let conversation = self.accountsConversations.conversation(for: account, with: jid) {
                self.accountsConversations.newActivity(activity, isUnread: isUnread, for: conversation);
            }
            completionHandler();
        }
    }

    func markAsRead(for account: BareJID, with jid: BareJID, count: Int? = nil) {
        queue.async {
            if let conversation = self.accountsConversations.conversation(for: account, with: jid) {
                self.accountsConversations.markAsRead(count ?? conversation.unread, in: conversation);
            }
        }
    }

    func resetChatStates(for account: BareJID) {
        queue.async {
            self.accountsConversations.resetChatStates(for: account);
        }
    }

    func messageDraft(for account: BareJID, with jid: BareJID) -> String? {
        return try! Database.main.reader({ database -> String? in
            return try database.select(query: .chatFindMessageDraft, params: ["account": account, "jid": jid]).mapFirst({ $0.string(for: "message_draft") });
        })
    }

    func storeMessage(draft: String?, for account: BareJID, with jid: BareJID) {
        try! Database.main.writer({ database in
            try database.update(query: .chatUpdateMessageDraft, params: [draft, account, jid, draft]);
        })
    }

    public func lastActivity(for account: BareJID, jid: BareJID, conversationType: ConversationType) -> LastChatActivity? {
        return try! Database.main.reader({ database in
            try database.select(query: .chatFindLastActivity, params: ["account": account, "jid": jid]).mapFirst({ cursor -> LastChatActivity? in
                let timestamp = cursor.date(for: "timestamp")!;
                return LastChatActivity.init(timestamp: timestamp, sender: .from(conversationType: conversationType, conversation: ConversationKeyItem(account: account, jid: jid), cursor: cursor), payload: .from(cursor));
            });
        })
    }

    func loadChats(for account: BareJID, context: Context) {
        queue.async {
            guard !self.accountsConversations.hasConversations(for: account) else {
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
                    let timestamp = lastMessageTimestamp == nil ? creationTimestamp : (creationTimestamp.compare(lastMessageTimestamp!) == .orderedAscending ? lastMessageTimestamp! : creationTimestamp);
                    
                    let lastActivity = LastChatActivity(timestamp: timestamp, sender: .from(conversationType: type, conversation: ConversationKeyItem(account: account, jid: jid), cursor: cursor), payload: .from(cursor))

                    switch type {
                    case .chat:
                        let options: ChatOptions? = cursor.object(for: "options");
                        return Chat(context: context, jid: jid, id: id, lastActivity: lastActivity, unread: unread, options: options ?? ChatOptions());
                    case .room:
                        guard let options: RoomOptions = cursor.object(for: "options") else {
                            return nil;
                        }
                        let room = Room(context: context, jid: jid, id: id, lastActivity: lastActivity, unread: unread, options: options);
                        return room;
                    case .channel:
                        guard let options: ChannelOptions = cursor.object(for: "options") else {
                            return nil;
                        }
                        return Channel(context: context, channelJid: jid, id: id, lastActivity: lastActivity, unread: unread, options: options, creationTimestamp: cursor.date(for: "creation_timestamp")!);
                    }
                });
            })

            let accountConversation = AccountConversations(items: conversations);
            self.accountsConversations.add(accountConversation, for: account);
        }
    }

    func unloadChats(for account: BareJID) {
        queue.async {
            self.accountsConversations.removeConversations(for: account);
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
        queue.async {
            try! Database.main.writer({ database in
                try database.update(query: .chatUpdateOptions, params: ["options": options, "account": conversation.account, "jid": conversation.jid]);
            })
            
            if notificationChange != nil {
                self.accountsConversations.muteChanged(for: conversation);
            }
        }
    }
    
    func refreshConversationsList() {
        queue.async {
            self.accountsConversations.refresh();
        }
    }
    
    public enum ConversationEvent {
        case created(Conversation)
        case destroyed(Conversation)
    }
    
    final class Conversations {

        @Published
        public private(set) var items: [Conversation] = [];
        public let conversationsEventsPublisher = PassthroughSubject<ConversationEvent,Never>();

        @Published
        fileprivate(set) var unreadMessagesCount: Int = 0;
        
        private var accountChats = [BareJID: AccountConversations]();

        public func conversations(for account: BareJID) -> [Conversation]? {
            return accountChats[account]?.items;
        }
        
        public func conversation(for account: BareJID, with jid: BareJID) -> Conversation? {
            return accountChats[account]?.get(with: jid);
        }
        
        public func hasConversations(for account: BareJID) -> Bool {
            return accountChats[account] != nil;
        }
                
        public func add(_ conversations: AccountConversations, for account: BareJID) {
            accountChats[account] = conversations;
            items.append(contentsOf: conversations.items);
            unreadMessagesCount = unreadMessagesCount + conversations.items.filter({ !$0.isMuted }).map({ $0.unread }).reduce(0, +);
        }
        
        public func removeConversations(for account: BareJID) {
            guard let removed = accountChats.removeValue(forKey: account)?.items else {
                return;
            }
            self.items.removeAll(where: { it in removed.contains(where: { it === $0 }) })
            unreadMessagesCount = max(unreadMessagesCount - removed.filter({ !$0.isMuted }).map({ $0.unread }).reduce(0, +), 0);
        }
        
        public func add(_ conversation: Conversation) -> Bool {
            guard let conversations = accountChats[conversation.account] else {
                return false;
            }
            conversations.add(conversation);
            items.append(conversation);
            if !conversation.isMuted {
                unreadMessagesCount = unreadMessagesCount + conversation.unread
            }
            return true;
        }
        
        public func remove(_ conversation: Conversation) -> Bool {
            guard let conversations = accountChats[conversation.account] else {
                return false;
            }
            guard conversations.remove(conversation) else {
                return false;
            }
            
            items.removeAll(where: { conversation === $0 });
            if !conversation.isMuted {
                unreadMessagesCount = max(unreadMessagesCount - conversation.unread, 0);
            }
            return true;
        }
        
        public func newActivity(_ activity: LastChatActivity, isUnread: Bool, for conversation: Conversation) {
            let updated = conversation.update(activity, isUnread: isUnread);
            if isUnread && !conversation.isMuted {
                unreadMessagesCount = unreadMessagesCount + 1;
            }

            if updated {
                if let chat = conversation as? Chat {
                    chat.update(remoteChatState: .active);
                }
                self.items = items;
            }
        }
        
        public func markAsRead(_ count: Int, in conversation: Conversation) {
            if conversation.markAsRead(count: count) && !conversation.isMuted {
                unreadMessagesCount = max(self.unreadMessagesCount - count, 0);
            }
        }
        
        public func muteChanged(for conversation: Conversation) {
            if conversation.isMuted {
                unreadMessagesCount = max(self.unreadMessagesCount - conversation.unread, 0);
            } else {
                unreadMessagesCount = self.unreadMessagesCount + conversation.unread;
            }
        }
        
        public func resetChatStates(for account: BareJID) {
            if let items = accountChats[account]?.items {
                for conversation in items {
                    if let chat = conversation as? Chat {
                        chat.update(remoteChatState: nil);
                        chat.update(localChatState: .active);
                    }
                }
            }
        }
        
        public func refresh() {
            self.items = items;
        }
    }
}

extension Conversation {
    
    public var isMuted: Bool {
        return notifications == .none;
    }
    
}
