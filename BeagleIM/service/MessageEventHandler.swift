//
//  MessageEventHandler.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 27/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class MessageEventHandler: XmppServiceEventHandler {
    
    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            guard let from = e.message.from, let body = e.message.body else {
                return;
            }
            let timestamp = e.message.delay?.stamp ?? Date();
            DBChatHistoryStore.instance.appendItem(for: e.sessionObject.userBareJid!, with: from.bareJid, state: ((e.message.type ?? .chat) == .error) ? .incoming_error_unread : .incoming_unread, type: .message, timestamp: timestamp, stanzaId: e.message.id, data: body, completionHandler: nil);
        default:
            break;
        }
    }
}
