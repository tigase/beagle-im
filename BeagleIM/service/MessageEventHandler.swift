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
    
    static func prepareBody(message: Message) -> String? {
        guard let body = message.body ?? message.oob else {
            return nil;
        }
        guard (message.type ?? .chat) != .error else {
            guard let error = message.errorCondition else {
                return "Error: Unknown error\n------\n\(body)";
            }
            return "Error: \(message.errorText ?? error.rawValue)\n------\n\(body)";
        }
        return body;
    }
    
    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE, MessageDeliveryReceiptsModule.ReceiptEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as MessageModule.MessageReceivedEvent:
            guard let from = e.message.from, let account = e.sessionObject.userBareJid, let body = MessageEventHandler.prepareBody(message: e.message) else {
                return;
            }
            let timestamp = e.message.delay?.stamp ?? Date();
            let state: MessageState = ((e.message.type ?? .chat) == .error) ? .incoming_error_unread : .incoming_unread;
            DBChatHistoryStore.instance.appendItem(for: account, with: from.bareJid, state: state, type: .message, timestamp: timestamp, stanzaId: e.message.id, data: body, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, completionHandler: nil);
        case let e as MessageDeliveryReceiptsModule.ReceiptEvent:
            guard let from = e.message.from?.bareJid, let account = e.sessionObject.userBareJid else {
                return;
            }
            DBChatHistoryStore.instance.updateItemState(for: account, with: from, stanzaId: e.messageId, from: .outgoing, to: .outgoing_delivered)
        default:
            break;
        }
    }
    
}
