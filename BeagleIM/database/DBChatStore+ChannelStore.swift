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
import TigaseSwift

extension DBChatStore: ChannelStore {
    
    public typealias Channel = BeagleIM.Channel
    
    public func channels(for context: Context) -> [Channel] {
        return convert(items: conversations(for: context.userBareJid));
    }
    
    public func channel(for context: Context, with jid: BareJID) -> Channel? {
        return conversation(for: context.userBareJid, with: jid) as? Channel;
    }
    
    public func createChannel(for context: Context, with channelJid: BareJID, participantId: String, nick: String?, state: ChannelState) -> ConversationCreateResult<Channel> {
        if let channel = channel(for: context, with: channelJid) {
            return .found(channel);
        }
    
        let account = context.userBareJid;
        guard let channel: Channel = createConversation(for: account, with: channelJid, execute: {
            let timestamp = Date();
            let options = ChannelOptions(participantId: participantId, nick: nick, state: state);
            
            let id = try! self.openConversation(account: account, jid: channelJid, type: .channel, timestamp: timestamp, options: options);
            let channel = Channel(context: context, channelJid: channelJid, id: id, timestamp: timestamp, lastActivity: lastActivity(for: account, jid: channelJid), unread: 0, options: options);

            return channel;
        }) else {
            if let channel = self.channel(for: context, with: channelJid) {
                return .found(channel);
            }
            return .none;
        }
        return .created(channel);
    }
    
    public func close(channel: Channel) -> Bool {
        return close(conversation: channel);
    }
    
    
    // FIXME: below methods should be part of a Channel class!!
    
    public func update(channel: Channel, nick: String?) -> Bool {
        guard channel.nickname != nick else {
            return false;
        }
        return dispatcher.sync {
            var options = channel.options;
            options.nick = nick;
            self.updateOptions(for: channel.account, jid: channel.jid, options: options, completionHandler: nil);

            channel.nickname = nick;
            return true;
        }
    }
    
    public func update(channel: Channel, info: ChannelInfo) -> Bool {
        guard channel.name != info.name || channel.description != info.description else {
            return false;
        }
        dispatcher.sync {
            var options = channel.options;
            options.name = info.name;
            options.description = info.description;
            self.updateOptions(for: channel.account, jid: channel.jid, options: options, completionHandler: nil);
        }
        return true;
    }
    
    public func update(channel: Channel, state: ChannelState) -> Bool {
        guard channel.state != state else {
            return false;
        }
        return dispatcher.sync {
            var options = channel.options;
            options.state = state;
            _ = channel.update(state: state);
            self.updateOptions(for: channel.account, jid: channel.jid, options: options, completionHandler: nil);
            return true;
        }
    }
}
