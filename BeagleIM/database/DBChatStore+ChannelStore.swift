//
// DBChatStore+ChannelStore.swift
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
import Martin

extension DBChatStore: ChannelStore {
    
    public typealias Channel = BeagleIM.Channel
    
    public func channels(for context: Context) -> [Channel] {
        return convert(items: conversations(for: context.userBareJid));
    }
    
    public func channel(for context: Context, with jid: BareJID) -> Channel? {
        return conversation(for: context.userBareJid, with: jid) as? Channel;
    }
    
    public func createChannel(for context: Context, with jid: BareJID, participantId: String, nick: String?, state: ChannelState) -> ConversationCreateResult<Channel> {
        let account = context.userBareJid;
        return self.queue.sync {
            guard let conversation = self.accountsConversations.conversation(for: account, with: jid) else {
                let timestamp = Date();
                let options = ChannelOptions(participantId: participantId, nick: nick, state: state);
                let id = try! self.openConversation(account: context.userBareJid, jid: jid, type: .channel, timestamp: timestamp, options: nil);
                let channel = Channel(context: context, channelJid: jid, id: id, lastActivity: lastActivity(for: account, jid: jid, conversationType: .channel) ?? .none(timestamp: timestamp), unread: 0, options: options, creationTimestamp: timestamp);
                if self.accountsConversations.add(channel) {
                    self.conversationsEventsPublisher.send(.created(channel));
                    return .created(channel);
                } else {
                    return .none;
                }
            }
            guard let channel = conversation as? Channel else {
                return .none;
            }
            return .found(channel);
        }
    }
    
    public func close(channel: Channel) -> Bool {
        return close(conversation: channel);
    }
    
}
