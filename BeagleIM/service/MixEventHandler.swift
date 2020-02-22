//
// MixEventHandler.swift
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

class MixEventHandler: XmppServiceEventHandler {
    
    let instance = MixEventHandler();
    
    let events: [Event] = [MixModule.MessageReceivedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as MixModule.MessageReceivedEvent:
            // only mix message (with `mix` element) are processed here...
            guard let mix = e.message.mix, let from = e.message.from else {
                return;
            }
            
            let account = e.sessionObject.userBareJid!;
            let (body, encryption,fingerprint) = MessageEventHandler.prepareBody(message: e.message, forAccount: account);
            guard body != nil else {
                return;
            }
            
            let jid = from.bareJid;
            let timestamp = e.message.delay?.stamp ?? Date();
            var state = MessageState.incoming_unread;
            let authorNickname = mix.nickname ?? e.message.from?.resource; // if there is no nick we are using participant id (should be in resource of received message
            let authorJid = mix.jid;
            
            if mix.jid != nil {
                if mix.jid == account {
                    if state.isError {
                        state = .outgoing_error;
                    } else {
                        state = .outgoing;
                    }
                }
            } else if let senderId = from.resource {
                if e.channel.participantId == senderId {
                    if state.isError {
                        state = .outgoing_error;
                    } else {
                        state = .outgoing;
                    }
                }
            } else if mix.nickname == e.channel.nickname {
                if state.isError {
                    state = .outgoing_error;
                } else {
                    state = .outgoing;
                }
            }
            
            var type: ItemType = .message;
            if let oob = e.message.oob {
                if oob == body!, URL(string: oob) != nil {
                    type = .attachment;
                }
            }

            DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: nil, type: type, timestamp: timestamp, stanzaId: e.message.id, data: body!, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, completionHandler: nil);
            
            if type == .message && !state.isError, #available(macOS 10.15, *) {
                let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.address.rawValue);
                let matches = detector.matches(in: body!, range: NSMakeRange(0, body!.utf16.count));
                matches.forEach { match in
                    if let url = match.url, let scheme = url.scheme, ["https", "http"].contains(scheme) {
                        DBChatHistoryStore.instance.appendItem(for: account, with: from.bareJid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: nil, type: .linkPreview, timestamp: timestamp, stanzaId: nil, data: url.absoluteString, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, completionHandler: nil);
                    }
                    if let address = match.components {
                        let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                        let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                        DBChatHistoryStore.instance.appendItem(for: account, with: from.bareJid, state: state, authorNickname: authorNickname, authorJid: authorJid, recipientNickname: nil, type: .linkPreview, timestamp: timestamp, stanzaId: nil, data: mapUrl.absoluteString, errorCondition: e.message.errorCondition, errorMessage: e.message.errorText, encryption: encryption, encryptionFingerprint: fingerprint, completionHandler: nil);
                    }
                }
            }
        default:
            break;
        }
    }

}
