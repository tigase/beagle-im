//
// DBChannelStore.swift
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

open class DBChannelStore: ChannelStore {
    
    public let dispatcher: QueueDispatcher;
    private let sessionObject: SessionObject;
    private let store = DBChatStore.instance;
    
    public init(sessionObject: SessionObject) {
        self.sessionObject = sessionObject;
        self.dispatcher = store.dispatcher;
    }
    
    public func channel(for jid: BareJID) -> Channel? {
        return store.getChat(for: sessionObject.userBareJid!, with: jid) as? Channel;
    }
    
    public func createChannel(jid: BareJID, participantId: String, nick: String?) -> Result<Channel, ErrorCondition> {
        switch store.createChannel(for: sessionObject.userBareJid!, channelJid: jid, participantId: participantId, nick: nick) {
        case .success(let channel):
            return .success(channel as Channel);
        case .failure(let error):
            return .failure(error);
        }
    }
    
    public func close(channel: Channel) -> Bool {
        return store.close(for: sessionObject.userBareJid!, chat: channel);
    }
    
    public func update(channel: Channel, nick: String?) -> Bool {
        guard channel.nickname != nick, let dbChannel = channel as? DBChatStore.DBChannel else {
            return false;
        }
        var options = dbChannel.options;
        options.nick = nick;
        store.updateOptions(for: dbChannel.account, jid: channel.channelJid, options: options, completionHandler: nil);
        return true;
    }
    
    public func initialize() {
        store.loadChats(for: sessionObject.userBareJid!, context: sessionObject.context);
    }
    
    public func deinitialize() {
        store.unloadChats(for: sessionObject.userBareJid!);
    }

}
