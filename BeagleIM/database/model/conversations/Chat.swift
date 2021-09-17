//
// Chat.swift
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
import TigaseSwiftOMEMO
import AppKit
import Combine

public class Chat: ConversationBaseWithOptions<ChatOptions>, ChatProtocol, Conversation {
    
    public override var defaultMessageType: StanzaType {
        return .chat;
    }
    
    var localChatState: ChatState = .active;
    @Published
    private(set) var remoteChatState: ChatState? = nil;
    
    public var automaticallyFetchPreviews: Bool {
        return DBRosterStore.instance.item(for: account, jid: JID(jid)) != nil;
    }
    
    public var debugDescription: String {
        return "Chat(account: \(account), jid: \(jid))";
    }

    init(dispatcher: QueueDispatcher, context: Context, jid: BareJID, id: Int, timestamp: Date, lastActivity: LastConversationActivity?, unread: Int, options: ChatOptions) {
        let contact = ContactManager.instance.contact(for: .init(account: context.userBareJid, jid: jid, type: .buddy));
        super.init(dispatcher: dispatcher, context: context, jid: jid, id: id, timestamp: timestamp, lastActivity: lastActivity, unread: unread, options: options, displayableId: contact);
    }
    
    public func isLocalParticipant(jid: JID) -> Bool {
        return account == jid.bareJid;
    }
    
    func changeChatState(state: ChatState) -> Message? {
        guard localChatState != state else {
            return nil;
        }
        self.localChatState = state;
        if (remoteChatState != nil) {
            let msg = Message();
            msg.to = JID(jid);
            msg.type = StanzaType.chat;
            msg.chatState = state;
            return msg;
        }
        return nil;
    }
    
    private var remoteChatStateTimer: Foundation.Timer?;
    
//    func updateDisplayName(rosterItem: RosterItem?) {
//        DispatchQueue.main.async {
//            self.displayName = rosterItem?.name ?? self.jid.stringValue;
//        }
//    }
    
    func update(remoteChatState state: ChatState?) {
        // proper handle when we have the same state!!
        let prevState = remoteChatState;
        if prevState == .composing {
            remoteChatStateTimer?.invalidate();
            remoteChatStateTimer = nil;
        }
        self.remoteChatState = state;
        
        if state == .composing {
            DispatchQueue.main.async {
                self.remoteChatStateTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 60.0, repeats: false, block: { [weak self] timer in
                guard let that = self else {
                    return;
                }
                if that.remoteChatState == .composing {
                    that.remoteChatState = .active;
                    that.remoteChatStateTimer = nil;
                }
            });
            }
        }
    }
    
    public override func createMessage(text: String, id: String, type: StanzaType) -> Message {
        let msg = super.createMessage(text: text, id: id, type: type);
        msg.chatState = .active;
        msg.isMarkable = true;
        msg.messageDelivery = .request;
        self.localChatState = .active;
        return msg;
    }
    
    public func canSendChatMarker() -> Bool {
        return true;
    }
    
    public func sendChatMarker(_ marker: Message.ChatMarkers, andDeliveryReceipt receipt: Bool) {
        guard Settings.confirmMessages && options.confirmMessages else {
            return;
        }
        
        let message = self.createMessage();
        message.chatMarkers = marker;
        if receipt {
            message.messageDelivery = .received(id: marker.id)
        }
        message.hints = [.store];
        self.send(message: message, completionHandler: nil);
    }
 
    public func prepareAttachment(url originalURL: URL, completionHandler: @escaping (Result<(URL, Bool, ((URL) -> URL)?), ShareError>) -> Void) {
        let encryption = self.options.encryption ?? .none;
        switch encryption {
        case .none:
            completionHandler(.success((originalURL, false, nil)));
        case .omemo:
            guard let omemoModule: OMEMOModule = self.context?.module(.omemo), let data = try? Data(contentsOf: originalURL) else {
                completionHandler(.failure(.unknownError));
                return;
            }
            let result = omemoModule.encryptFile(data: data);
            switch result {
            case .success(let (encryptedData, hash)):
                let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);
                do {
                    try encryptedData.write(to: tmpFile);
                    completionHandler(.success((tmpFile, true, { url in
                        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                        parts.scheme = "aesgcm";
                        parts.fragment = hash;
                        let shareUrl = parts.url!;

                        return shareUrl;
                    })));
                } catch {
                    completionHandler(.failure(.noAccessError));
                }
            case .failure(_):
                completionHandler(.failure(.unknownError));
            }
        }
    }
    
    public func sendMessage(text: String, correctedMessageOriginId: String?) {
        let stanzaId = UUID().uuidString;
        let encryption = self.options.encryption ?? Settings.messageEncryption;
        
        if let correctedMessageId = correctedMessageOriginId {
            DBChatHistoryStore.instance.correctMessage(for: self, stanzaId: correctedMessageId, sender: .none, data: text, correctionStanzaId: stanzaId, correctionTimestamp: Date(), newState: .outgoing(.unsent));
        } else {
            var messageEncryption: ConversationEntryEncryption = .none;
            switch encryption {
            case .omemo:
                messageEncryption = .decrypted(fingerprint: DBOMEMOStore.instance.identityFingerprint(forAccount: self.account, andAddress: SignalAddress(name: self.account.stringValue, deviceId: Int32(bitPattern: DBOMEMOStore.instance.localRegistrationId(forAccount: self.account)!))));
            case .none:
                break;
            }
            let options = ConversationEntry.Options(recipient: .none, encryption: messageEncryption, isMarkable: true)
            DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.unsent), sender: .me(conversation: self), type: .message, timestamp: Date(), stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: text, appendix: nil, options: options, linkPreviewAction: .none, completionHandler: nil);
        }
        
        resendMessage(content: text, isAttachment: false, encryption: encryption, stanzaId: stanzaId, correctedMessageOriginId: correctedMessageOriginId);
    }
    
    // we are only encrypting URL and not file content, it should be encoded prior uploading
    public func sendAttachment(url: String, appendix: ChatAttachmentAppendix, originalUrl: URL?, completionHandler: (()->Void)?) {
        let stanzaId = UUID().uuidString;
        let encryption = self.options.encryption ?? Settings.messageEncryption;

        var messageEncryption: ConversationEntryEncryption = .none;
        switch encryption {
        case .omemo:
            messageEncryption = .decrypted(fingerprint: DBOMEMOStore.instance.identityFingerprint(forAccount: self.account, andAddress: SignalAddress(name: self.account.stringValue, deviceId: Int32(bitPattern: DBOMEMOStore.instance.localRegistrationId(forAccount: self.account)!))));
        case .none:
            break;
        }
        let options = ConversationEntry.Options(recipient: .none, encryption: messageEncryption, isMarkable: true)
        DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.unsent), sender: .me(conversation: self), type: .attachment, timestamp: Date(), stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: url, appendix: appendix, options: options, linkPreviewAction: .none, completionHandler: { msgId in
            if let url = originalUrl {
                _ = DownloadStore.instance.store(url, filename: url.lastPathComponent, with: "\(msgId)");
            }
            completionHandler?();
        });
        resendMessage(content: url, isAttachment: true, encryption: encryption, stanzaId: stanzaId, correctedMessageOriginId: nil);
    }
    
    func resendMessage(content: String, isAttachment: Bool, encryption: ChatEncryption, stanzaId: String, correctedMessageOriginId: String?) {
        let message = createMessage(text: content, id: stanzaId);
        if isAttachment {
            message.oob = content
        }
        message.lastMessageCorrectionId = correctedMessageOriginId;
        send(message: message, encryption: encryption, completionHandler: { result in
            switch result {
            case .success(_):
                DBChatHistoryStore.instance.updateItemState(for: self, stanzaId: correctedMessageOriginId ?? message.id!, from: .outgoing(.unsent), to: .outgoing(.sent), withTimestamp: correctedMessageOriginId != nil ? nil : Date());
            case .failure(let error):
                switch error {
                case .gone:
                    return;
                default:
                    break;
                }
                DBChatHistoryStore.instance.markOutgoingAsError(for: self, stanzaId: message.id!, errorCondition: .undefined_condition, errorMessage: error.message)
            }
        })
    }
    
    private func send(message: Message, encryption: ChatEncryption, completionHandler: @escaping (Result<Void,XMPPError>)->Void) {
        XmppService.instance.tasksQueue.schedule(for: jid, task: { callback in
            switch encryption {
            case .none:
                super.send(message: message, completionHandler: { result in
                    completionHandler(result);
                    callback();
                });
            case .omemo:
                guard let context = self.context as? XMPPClient, context.isConnected else {
                    completionHandler(.failure(.gone(nil)));
                    callback();
                    return;
                }
                message.oob = nil;
                context.module(.omemo).encode(message: message, completionHandler: { result in
                    switch result {
                    case .successMessage(let encodedMessage, _):
                        guard context.isConnected else {
                            completionHandler(.failure(.gone(nil)))
                            callback();
                            return;
                        }
                        super.send(message: encodedMessage, completionHandler: { result in
                            completionHandler(result);
                            callback();
                        });
                    case .failure(let error):
                        var errorMessage = NSLocalizedString("It was not possible to send encrypted message due to encryption error", comment: "omemo encryption error");
                        switch error {
                        case .noSession:
                            errorMessage = NSLocalizedString("There is no trusted device to send message to", comment: "omemo encryption error");
                        default:
                            break;
                        }
                        completionHandler(.failure(.unexpected_request(errorMessage)));
                        callback();
                    }
                })
            }
        })
    }

    public override func isLocal(sender: ConversationEntrySender) -> Bool {
        switch sender {
        case .me(_):
            return true;
        default:
            return false;
        }
    }
}

typealias ConversationOptionsProtocol = ChatOptionsProtocol

public struct ChatOptions: Codable, ConversationOptionsProtocol, Equatable {
    
    var encryption: ChatEncryption?;
    public var notifications: ConversationNotification = .always;
    public var confirmMessages: Bool = true;
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        if let val = try container.decodeIfPresent(String.self, forKey: .encryption) {
            encryption = ChatEncryption(rawValue: val);
        }
        notifications = ConversationNotification(rawValue: try container.decodeIfPresent(String.self, forKey: .notifications) ?? "") ?? .always;
        confirmMessages = try container.decodeIfPresent(Bool.self, forKey: .confirmMessages) ?? true;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        if encryption != nil {
            try container.encode(encryption!.rawValue, forKey: .encryption);
        }
        if notifications != .always {
            try container.encode(notifications.rawValue, forKey: .notifications);
        }
        try container.encode(confirmMessages, forKey: .confirmMessages);
    }
    
    public func equals(_ options: ChatOptionsProtocol) -> Bool {
        guard let options = options as? ChatOptions else {
            return false;
        }
        return options == self;
    }
    
    enum CodingKeys: String, CodingKey {
        case encryption = "encrypt"
        case notifications = "notifications";
        case confirmMessages = "confirmMessages"
    }
}
