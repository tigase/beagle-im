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

extension ConversationMessage {
    
    func shouldNotify() -> Bool {
        guard state == .incoming_unread else {
            return false;
        }
         
        guard let conversation = self.conversation as? Conversation else {
            return false;
        }
        
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
        
        if conversation is Chat {
            guard Settings.notificationsFromUnknownSenders || conversation.displayName != conversation.jid.stringValue else {
                return false;
            }
        }
        
        return true;
    }
    
}

public class NotificationManager {
    
    public static let instance = NotificationManager();
    
    private var queues: [NotificationQueueKey: NotificationQueue] = [:];
    
    private let dispatcher = QueueDispatcher(label: "NotificationManager");
    
    func newMessage(_ message: ConversationMessage) {
        dispatcher.async {
            guard message.shouldNotify() else {
                return;
            }
            
            if let queue = self.queues[.init(account: message.conversation.account, jid: message.conversation.jid)] ?? self.queues[.init(account: message.conversation.account, jid: nil)] {
                queue.add(message: message);
            } else {
                self.notifyNewMessage(message: message);
            }
        }
    }
    
    func markAsRead(on account: BareJID, with jid: BareJID, itemsIds: [Int]) {
        dispatcher.async {
            if let queue = self.queues[.init(account: account, jid: jid)] {
                queue.cancel(forIds: itemsIds);
            }
            if let queue = self.queues[.init(account: account, jid: nil)] {
                queue.cancel(forIds: itemsIds);
            }
            let ids = itemsIds.map({ "message:\($0):new" });
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids);
        }
    }
    
    func syncStarted(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            let key = NotificationQueueKey(account: account, jid: jid);
            if self.queues[key] == nil {
                self.queues[key] = NotificationQueue();
            }
        }
    }
    
    func syncCompleted(for account: BareJID, with jid: BareJID?) {
        dispatcher.async {
            if let messages = self.queues.removeValue(forKey: .init(account: account, jid: jid))?.unreadMessages {
                for message in messages {
                    self.notifyNewMessage(message: message);
                }
            }
        }
    }
    
    private func notifyNewMessage(message: ConversationMessage) {
        guard let conversation = message.conversation as? Conversation else {
            return;
        }
        
        let content = UNMutableNotificationContent();
        content.title = conversation.displayName;
        if conversation is Room || conversation is Channel {
            content.subtitle = message.nickname;
        }
        content.body = (message.message.contains("`") || !Settings.enableMarkdownFormatting || !Settings.showEmoticons) ? message.message : message.message.emojify();
        content.sound = UNNotificationSound.default
        content.userInfo = ["account": conversation.account.stringValue, "jid": conversation.jid.stringValue, "id": "message-new"];
 
        let request = UNNotificationRequest(identifier: "message:\(message.id):new", content: content, trigger: nil);
        UNUserNotificationCenter.current().add(request) { (error) in
            print("could not show notification:", error as Any);
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
        
        private(set) var unreadMessages: [ConversationMessage] = [];
 
        func add(message: ConversationMessage) {
            unreadMessages.append(message);
        }
        
        func cancel(forIds: [Int]) {
            let ids = Set(forIds);
            unreadMessages.removeAll(where: { ids.contains($0.id) });
        }
    }
}
