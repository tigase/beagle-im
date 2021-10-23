//
// NotificationsManager.swift
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
import UserNotifications
import TigaseSwift
import Combine
import TigaseLogging

extension ConversationEntry {
    
    func shouldNotify() -> Bool {
        guard case .incoming(let state) = self.state, state == .received else {
            return false;
        }
         
        guard let conversation = self.conversation as? Conversation else {
            return false;
        }
        
        switch payload {
        case .message(let message, _):
            switch conversation.notifications {
            case .none:
                return false;
            case .mention:
                if let nickname = (conversation as? Room)?.nickname ?? (conversation as? Channel)?.nickname {
                    if !message.contains(nickname) {
                        let keywords = Settings.markKeywords;
                        if !keywords.isEmpty {
                            if  keywords.first(where: { message.contains($0) }) == nil {
                                return false;
                            }
                        } else {
                            return false;
                        }
                    }
                } else {
                    return false;
                }
            default:
                break;
            }
        case .location(_):
            guard conversation.notifications == .always else {
                return false;
            }
        case .attachment(_, _):
            guard conversation.notifications == .always else {
                 return false;
             }
         default:
            return false;
        }
        
        if conversation is Chat {
            guard Settings.notificationsFromUnknownSenders || conversation.displayName != conversation.jid.stringValue else {
                return false;
            }
        }
        
        return true;
    }
    
    var notificationContent: String? {
        switch self.payload {
        case .message(let message, _):
            return message;
        case .invitation(_, _):
            return "📨 \(NSLocalizedString("Invitation", comment: "invitation label for chats list"))"
        case .location(_):
            return "📍 \(NSLocalizedString("Location", comment: "attachemt label for conversations list"))";
        case .attachment(_, _):
            return "📎 \(NSLocalizedString("Attachment", comment: "attachemt label for conversations list"))";
        default:
            return nil;
        }
    }

}

public class NotificationManager {
    
    public static let instance = NotificationManager();
    
    private var queues: [NotificationQueueKey: NotificationQueue] = [:];
    
    private let dispatcher = QueueDispatcher(label: "NotificationManager");
    private var cancellables: Set<AnyCancellable> = [];
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "NotificationManager");
    
    init() {
        MessageEventHandler.eventsPublisher.receive(on: dispatcher.queue).sink(receiveValue: { [weak self] event in
            switch event {
            case .started(let account, let jid):
                self?.syncStarted(for: account, with: jid);
            case .finished(let account, let jid):
                self?.syncCompleted(for: account, with: jid);
            }
        }).store(in: &cancellables);
        DBChatHistoryStore.instance.markedAsRead.receive(on: dispatcher.queue).sink(receiveValue: { [weak self] marked in
            self?.markAsRead(on: marked.account, with: marked.jid, itemsIds: marked.messages.map({ $0.id }));
        }).store(in: &cancellables);
    }
    
    func newMessage(_ entry: ConversationEntry) {
        dispatcher.async {
            guard entry.shouldNotify() else {
                return;
            }
            
            if let queue = self.queues[.init(account: entry.conversation.account, jid: entry.conversation.jid)] ?? self.queues[.init(account: entry.conversation.account, jid: nil)] {
                queue.add(message: entry);
            } else {
                self.notifyNewMessage(message: entry);
            }
        }
    }
    
    private func markAsRead(on account: BareJID, with jid: BareJID, itemsIds: [Int]) {
        if let queue = self.queues[.init(account: account, jid: jid)] {
            queue.cancel(forIds: itemsIds);
        }
        if let queue = self.queues[.init(account: account, jid: nil)] {
            queue.cancel(forIds: itemsIds);
        }
        let ids = itemsIds.map({ "message:\($0):new" });
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids);
    }
    
    private func syncStarted(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            let key = NotificationQueueKey(account: account, jid: jid);
            if self.queues[key] == nil {
                self.queues[key] = NotificationQueue();
            }
        }
    }
    
    private func syncCompleted(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            if let messages = self.queues.removeValue(forKey: .init(account: account, jid: jid))?.unreadMessages {
                for message in messages {
                    self.notifyNewMessage(message: message);
                }
            }
        }
    }
    
    private func notifyNewMessage(message entry: ConversationEntry) {
        guard let conversation = entry.conversation as? Conversation else {
            return;
        }
        
        guard let body = entry.notificationContent else {
            return;
        }
        
        let content = UNMutableNotificationContent();
        content.title = conversation.displayName;
        if conversation is Room || conversation is Channel {
            content.subtitle = entry.sender.nickname ?? "";
        }
        content.body = (body.contains("`") || !Settings.enableMarkdownFormatting || !Settings.showEmoticons) ? body : body.emojify();
        content.sound = UNNotificationSound.default
        content.userInfo = ["account": conversation.account.stringValue, "jid": conversation.jid.stringValue, "id": "message-new"];
 
        let request = UNNotificationRequest(identifier: "message:\(entry.id):new", content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request) { (error) in
            self.logger.debug("could not show notification: \(error as Any)");
        }
    }
    
    struct NotificationQueueKey: Hashable {
        let account: BareJID;
        let jid: BareJID?;
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(account);
            if let jid = jid {
                hasher.combine(jid);
            }
        }
    }

    class NotificationQueue {
        
        private(set) var unreadMessages: [ConversationEntry] = [];
 
        func add(message: ConversationEntry) {
            unreadMessages.append(message);
        }
        
        func cancel(forIds: [Int]) {
            let ids = Set(forIds);
            unreadMessages.removeAll(where: { ids.contains($0.id) });
        }
    }
}
