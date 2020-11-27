//
// ConversationBase.swift
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
import TigaseSwift

public class ConversationBase<Options: ChatOptionsProtocol>: TigaseSwift.ConversationBase, Identifiable {
    
    public let id: Int;
    public let dispatcher: QueueDispatcher;
    
    public private(set) var unread: Int;
    private var _options: Options;
    public var options: Options {
        return dispatcher.sync {
            return _options;
        }
    }
    
    private var _timestamp: Date;
    public var timestamp: Date {
        return dispatcher.sync {
            return _timestamp;
        }
    }
    
    private var _lastActivity: LastChatActivity?;
    public var lastActivity: LastChatActivity? {
        return dispatcher.sync {
            return _lastActivity;
        }
    }

    public var notifications: ConversationNotification {
        return options.notifications;
    }

    
    public init(dispatcher: QueueDispatcher, context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastChatActivity?, unread: Int, options: Options) {
        self.id = id;
        self._timestamp = timestamp;
        self.dispatcher = dispatcher;
        self._lastActivity = lastActivity;
        self.unread = unread;
        self._options = options;
        super.init(context: context, jid: jid);
    }
    
    public func markAsRead(count: Int) -> Bool {
        return dispatcher.sync(flags: .barrier) {
            guard unread > 0 else {
                return false;
            }
            unread = max(unread - count, 0);
            return true
        }
    }
    
    public func updateOptions(_ fn: @escaping (inout Options)->Void) {
        dispatcher.async(flags: .barrier) {
            var options = self._options;
            fn(&options);
            if !options.equals(self._options) {
                DBChatStore.instance.update(options: options, for: self as! Conversation);
                self._options = options;
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: DBChatStore.CHAT_UPDATED, object: self, userInfo: nil);
                }
            }
        }
    }
    
    public func update(lastActivity: LastChatActivity?, timestamp: Date, isUnread: Bool) -> Bool {
        return dispatcher.sync(flags: .barrier) {
            if isUnread {
                unread = unread + 1;
            }
            guard self._lastActivity == nil || self._timestamp.compare(timestamp) != .orderedDescending else {
                return isUnread;
            }
            
            if lastActivity != nil {
                self._lastActivity = lastActivity;
                self._timestamp = timestamp;
            }
            
            return true;
        }
    }

}
