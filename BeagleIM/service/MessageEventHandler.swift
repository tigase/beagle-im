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
    
    let events: [Event] = [MessageModule.MessageReceivedEvent.TYPE, MessageDeliveryReceiptsModule.ReceiptEvent.TYPE, MessageCarbonsModule.CarbonReceivedEvent.TYPE, DiscoveryModule.ServerFeaturesReceivedEvent.TYPE];
    
    init() {
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.CHANGED, object: nil);
    }
    
    @objc func settingsChanged(_ notification: Notification) {
        guard let setting = notification.object as? Settings else {
            return;
        }
        
        switch setting {
        case .enableMessageCarbons:
            XmppService.instance.clients.values.filter { (client) -> Bool in
                return client.state == .connected
                }.forEach { client in
                    guard let mcModule: MessageCarbonsModule = XmppService.instance.getClient(for: client.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) else {
                        return;
                    }
                    if setting.bool() {
                        guard let features: [String] = client.sessionObject.getProperty(DiscoveryModule.SERVER_FEATURES_KEY) else {
                            return;
                        }
                        guard features.contains(MessageCarbonsModule.MC_XMLNS) else {
                            return;
                        }
                        mcModule.enable();
                    } else {
                        mcModule.disable();
                    }
            }
        default:
            break;
        }
    }
    
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
            DBChatHistoryStore.instance.updateItemState(for: account, with: from, stanzaId: e.messageId, from: .outgoing, to: .outgoing_delivered);
        case let e as DiscoveryModule.ServerFeaturesReceivedEvent:
            guard Settings.enableMessageCarbons.bool() else {
                return;
            }
            guard e.features.contains(MessageCarbonsModule.MC_XMLNS) else {
                return;
            }
            guard let mcModule: MessageCarbonsModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MessageCarbonsModule.ID) else {
                return;
            }
            mcModule.enable();
        case let e as MessageCarbonsModule.CarbonReceivedEvent:
            guard let account = e.sessionObject.userBareJid, let from = e.message.from, let to = e.message.to, let body = MessageEventHandler.prepareBody(message: e.message) else {
                return;
            }
            let jid = account == from.bareJid ? to.bareJid : from.bareJid;
            let timestamp = e.message.delay?.stamp ?? Date();
            let state: MessageState = calculateState(direction: account == from.bareJid ? .outgoing : .incoming, error: ((e.message.type ?? .chat) == .error), unread: !Settings.markMessageCarbonsAsRead.bool());
            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, type: .message, timestamp: timestamp, stanzaId: e.message.id, data: body, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, completionHandler: nil);
        default:
            break;
        }
    }
    
    fileprivate func calculateState(direction: MessageDirection, error: Bool, unread: Bool) -> MessageState {
        if direction == .incoming {
            if error {
                return unread ? .incoming_error_unread : .incoming_error;
            }
            return unread ? .incoming_unread : .incoming;
        } else {
            if error {
                return unread ? .outgoing_error_unread : .outgoing_error;
            }
            return .outgoing;
        }
    }

}
