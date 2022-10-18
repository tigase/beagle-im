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
import Martin
import MartinOMEMO
import AppKit
import Combine
import Intents

public class Chat: ConversationBaseWithOptions<ChatOptions>, ChatProtocol, Conversation, @unchecked Sendable {
    
    public override var defaultMessageType: StanzaType {
        return .chat;
    }
    
    private var _localChatState: ChatState = .active;
    public var localChatState: ChatState {
        get {
            return withLock({
                return _localChatState;
            })
        }
    }
    @Published
    private(set) var remoteChatState: ChatState? = nil;
    
    public var automaticallyFetchPreviews: Bool {
        return DBRosterStore.instance.item(for: account, jid: JID(jid)) != nil;
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    public var debugDescription: String {
        return "Chat(account: \(account), jid: \(jid))";
    }
    
    init(context: Context, jid: BareJID, id: Int, lastActivity: LastConversationActivity, unread: Int, options: ChatOptions) {
        let contact = ContactManager.instance.contact(for: .init(account: context.userBareJid, jid: jid, type: .buddy));
        super.init(context: context, jid: jid, id: id, lastActivity: lastActivity, unread: unread, options: options, displayableId: contact);
        (context.module(.httpFileUpload) as! HttpFileUploadModule).isAvailablePublisher.combineLatest(context.$state, { isAvailable, state -> [ConversationFeature] in
            if case .connected(_) = state {
                return isAvailable ? [.httpFileUpload, .omemo] : [.omemo];
            } else {
                return [.omemo];
            }
        }).sink(receiveValue: { [weak self] value in
            self?.update(features: value);
        }).store(in: &cancellables);
    }
    
    public func isLocalParticipant(jid: JID) -> Bool {
        return account == jid.bareJid;
    }
    
    @discardableResult
    func update(localChatState state: ChatState) -> Bool {
        return withLock({
            guard _localChatState != state else {
                return false;
            }
            self._localChatState = state;
            return true;
        })
    }
    
    func changeChatState(state: ChatState) -> Message? {
        guard update(localChatState: state), remoteChatState != nil else {
            return nil;
        }
        
        let msg = Message(type: .chat, to: jid.jid());
        msg.chatState = state;
        return msg;
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
        withLock({
            self._localChatState = .active;
        })
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
        Task {
            try await self.send(message: message);
        }
    }
 
    public func prepareAttachment(url originalURL: URL) throws -> SharePreparedAttachment {
        let encryption = self.options.encryption ?? .none;
        switch encryption {
        case .none:
            return .init(url: originalURL, isTemporary: false, prepareShareURL: nil);
        case .omemo:
            let (encryptedData, hash) = try OMEMOModule.encryptFile(url: originalURL);
            let tmpFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString);
            try encryptedData.write(to: tmpFile);
            return .init(url: tmpFile, isTemporary: true, prepareShareURL: { url in
                var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                parts.scheme = "aesgcm";
                parts.fragment = hash;
                let shareUrl = parts.url!;

                return shareUrl;
            });
        }
    }
    
    public func sendMessage(text: String, correctedMessageOriginId: String?) async throws {
        let stanzaId = UUID().uuidString;
        let encryption = self.options.encryption ?? Settings.messageEncryption;
        
        if let correctedMessageId = correctedMessageOriginId {
            DBChatHistoryStore.instance.correctMessage(for: self, stanzaId: correctedMessageId, sender: .none, data: text, correctionStanzaId: stanzaId, correctionTimestamp: Date(), newState: .outgoing(.unsent));
        } else {
            var messageEncryption: ConversationEntryEncryption = .none;
            switch encryption {
            case .omemo:
                messageEncryption = .decrypted(fingerprint: DBOMEMOStore.instance.identityFingerprint(forAccount: self.account, andAddress: SignalAddress(name: self.account.description, deviceId: Int32(bitPattern: DBOMEMOStore.instance.localRegistrationId(forAccount: self.account)!))));
            case .none:
                break;
            }
            let options = ConversationEntry.Options(recipient: .none, encryption: messageEncryption, isMarkable: true)
            _ = DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.unsent), sender: .me(conversation: self), type: .message, timestamp: Date(), stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: text, appendix: nil, options: options, linkPreviewAction: .none);
        }
        
        try await resendMessage(content: text, isAttachment: false, encryption: encryption, stanzaId: stanzaId, correctedMessageOriginId: correctedMessageOriginId);
    }
    
    // we are only encrypting URL and not file content, it should be encoded prior uploading
    public func sendAttachment(url: String, appendix: ChatAttachmentAppendix, originalUrl: URL?) async throws {
        let stanzaId = UUID().uuidString;
        let encryption = self.options.encryption ?? Settings.messageEncryption;

        var messageEncryption: ConversationEntryEncryption = .none;
        switch encryption {
        case .omemo:
            messageEncryption = .decrypted(fingerprint: DBOMEMOStore.instance.identityFingerprint(forAccount: self.account, andAddress: SignalAddress(name: self.account.description, deviceId: Int32(bitPattern: DBOMEMOStore.instance.localRegistrationId(forAccount: self.account)!))));
        case .none:
            break;
        }
        let options = ConversationEntry.Options(recipient: .none, encryption: messageEncryption, isMarkable: true)
        if let msgId = DBChatHistoryStore.instance.appendItem(for: self, state: .outgoing(.unsent), sender: .me(conversation: self), type: .attachment, timestamp: Date(), stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: url, appendix: appendix, options: options, linkPreviewAction: .none) {
            if let url = originalUrl {
                _ = DownloadStore.instance.store(url, filename:  appendix.filename ?? url.lastPathComponent, with: "\(msgId)");
            }
        }
        try await resendMessage(content: url, isAttachment: true, encryption: encryption, stanzaId: stanzaId, correctedMessageOriginId: nil);
    }
    
    func resendMessage(content: String, isAttachment: Bool, encryption: ChatEncryption, stanzaId: String, correctedMessageOriginId: String?) async throws {
        let message = createMessage(text: content, id: stanzaId);
        if isAttachment {
            message.oob = content
        }
        message.lastMessageCorrectionId = correctedMessageOriginId;
        
        if #available(macOS 12.0, *) {
            let sender = INPerson(personHandle: INPersonHandle(value: account.description, type: .unknown), nameComponents: nil, displayName: AccountManager.account(for: self.account)?.nickname, image: AvatarManager.instance.avatar(for: self.account, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: account.description, isMe: true, suggestionType: .instantMessageAddress);
            let recipient = INPerson(personHandle: INPersonHandle(value: jid.description, type: .unknown), nameComponents: nil, displayName: self.displayName, image: AvatarManager.instance.avatar(for: self.jid, on: self.account)?.inImage(), contactIdentifier: nil, customIdentifier: jid.description, isMe: false, suggestionType: .instantMessageAddress);
            let intent = INSendMessageIntent(recipients: [recipient], outgoingMessageType: .outgoingMessageText, content: nil, speakableGroupName: nil, conversationIdentifier: "account=\(account.description)|sender=\(jid.description)", serviceName: "Beagle IM", sender: sender, attachments: nil);
            let interaction = INInteraction(intent: intent, response: nil);
            interaction.direction = .outgoing;
            try await interaction.donate();
        }
        
        do {
            try await send(message: message, encryption: encryption);
            DBChatHistoryStore.instance.updateItemState(for: self, stanzaId: correctedMessageOriginId ?? message.id!, from: .outgoing(.unsent), to: .outgoing(.sent), withTimestamp: correctedMessageOriginId != nil ? nil : Date());
        } catch let error as XMPPError {
            guard error.condition == .gone else {
                DBChatHistoryStore.instance.markOutgoingAsError(for: self, stanzaId: message.id!, error: error)
                throw error;
            }
        }
    }
    
    private func send(message: Message, encryption: ChatEncryption) async throws {
        try await XmppService.instance.tasksQueue.schedule(for: jid, operation: {
            switch encryption {
            case .none:
                try await super.send(message: message);
            case .omemo:
                guard let context = self.context as? XMPPClient, context.isConnected else {
                    throw XMPPError(condition: .gone);
                }

                let encryptedMessage = try await context.module(.omemo).encrypt(message: message);
                try await super.send(message: encryptedMessage.message);
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

