//
// DBChatHistoryStore.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
import TigaseSQLite3
import Combine

extension Query {
    static let messagesLastTimestampForAccount = Query("SELECT max(ch.timestamp) as timestamp FROM chat_history ch WHERE ch.account = :account AND ch.state <> \(ConversationEntryState.outgoing(.unsent).rawValue)");
    static let messageInsert = Query("INSERT INTO chat_history (account, jid, timestamp, item_type, data, stanza_id, state, author_nickname, author_jid, recipient_nickname, participant_id, error, encryption, fingerprint, appendix, server_msg_id, remote_msg_id, master_id, markable) VALUES (:account, :jid, :timestamp, :item_type, :data, :stanza_id, :state, :author_nickname, :author_jid, :recipient_nickname, :participant_id, :error, :encryption, :fingerprint, :appendix, :server_msg_id, :remote_msg_id, :master_id, :markable)");
    // if server has MAM:2 then use server_msg_id for checking
    // if there is no result, try to match using origin-id/stanza-id (if there is one in a form of UUID) and update server_msg_id if message is found
    // if there is was no origin-id/stanza-id then use old check with timestamp range and all of that..
    static let messageFindIdByServerMsgId = Query("SELECT id FROM chat_history WHERE account = :account AND server_msg_id = :server_msg_id");
    static let messageFindIdByRemoteMsgId = Query("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND remote_msg_id = :remote_msg_id");
    static let messageFindIdByOriginId = Query("SELECT id FROM chat_history WHERE account = :account AND jid = :jid AND (stanza_id = :stanza_id OR correction_stanza_id = :stanza_id) AND (:author_nickname IS NULL OR author_nickname = :author_nickname) AND (:participant_id IS NULL OR participant_id = :participant_id) ORDER BY timestamp DESC");
    static let messageUpdateServerMsgId = Query("UPDATE chat_history SET server_msg_id = :server_msg_id WHERE id = :id AND server_msg_id is null");
    static let messageFindLinkPreviewsForMessage = Query("SELECT id, account, jid, data FROM chat_history WHERE master_id = :master_id AND item_type = \(ItemType.linkPreview.rawValue)");
    static let messageDelete = Query("DELETE FROM chat_history WHERE id = :id");
    static let messageFindMessageOriginId = Query("select stanza_id from chat_history where id = :id");
    static let messagesFindUnsent = Query("SELECT ch.account as account, ch.jid as jid, ch.item_type as item_type, ch.data as data, ch.stanza_id as stanza_id, ch.encryption as encryption, ch.markable FROM chat_history ch WHERE ch.account = :account AND ch.state = \(ConversationEntryState.outgoing(.unsent).rawValue) ORDER BY timestamp ASC");
    static let messagesFindForChat = Query("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_timestamp, markable FROM chat_history WHERE account = :account AND jid = :jid AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.messageRetracted.rawValue), \(ItemType.attachment.rawValue))) ORDER BY timestamp DESC LIMIT :limit OFFSET :offset");
    static let messageFindPositionInChat = Query("SELECT count(id) FROM chat_history WHERE account = :account AND jid = :jid AND id <> :msgId AND (:showLinkPreviews OR item_type IN (\(ItemType.message.rawValue), \(ItemType.attachment.rawValue))) AND timestamp > (SELECT timestamp FROM chat_history WHERE id = :msgId)");
    static let messageSearchHistory = Query("SELECT chat_history.id as id, chat_history.account as account, chat_history.jid as jid, author_nickname, author_jid, participant_id,  chat_history.timestamp as timestamp, item_type, chat_history.data as data, state, preview, chat_history.encryption as encryption, fingerprint, markable FROM chat_history INNER JOIN chat_history_fts_index ON chat_history.id = chat_history_fts_index.rowid LEFT JOIN chats ON chats.account = chat_history.account AND chats.jid = chat_history.jid WHERE (chats.id IS NOT NULL OR chat_history.author_nickname is NULL) AND chat_history_fts_index MATCH :query AND (:account IS NULL OR chat_history.account = :account) AND (:jid IS NULL OR chat_history.jid = :jid) AND item_type = \(ItemType.message.rawValue) ORDER BY chat_history.timestamp DESC");
    static let messagesDeleteChatHistory = Query("DELETE FROM chat_history WHERE account = :account AND (:jid IS NULL OR jid = :jid)");
    static let messagesFindChatAttachments = Query("SELECT id, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_timestamp, markable FROM chat_history WHERE account = :account AND jid = :jid AND item_type = \(ItemType.attachment.rawValue) ORDER BY timestamp DESC");
    static let messageRetract = Query("UPDATE chat_history SET state = case state when \(ConversationEntryState.incoming_error(.received, errorMessage: nil).rawValue) then \(ConversationEntryState.incoming_error(.displayed, errorMessage: nil).rawValue) when \(ConversationEntryState.outgoing_error(.received, errorMessage: nil).rawValue) then \(ConversationEntryState.outgoing_error(.displayed, errorMessage: nil).rawValue) else \(ConversationEntryState.incoming(.displayed).rawValue) end, item_type = :item_type, correction_stanza_id = :correction_stanza_id, correction_timestamp = :correction_timestamp, remote_msg_id = :remote_msg_id, server_msg_id = COALESCE(:server_msg_id, server_msg_id) WHERE id = :id AND (correction_stanza_id IS NULL OR correction_stanza_id <> :correction_stanza_id) AND (correction_timestamp IS NULL OR correction_timestamp < :correction_timestamp)")
    static let messageCorrectLast = Query("UPDATE chat_history SET data = :data, state = :state, correction_stanza_id = :correction_stanza_id, correction_timestamp = :correction_timestamp, remote_msg_id = :remote_msg_id, server_msg_id = COALESCE(:server_msg_id, server_msg_id) WHERE id = :id AND (correction_stanza_id IS NULL OR correction_stanza_id <> :correction_stanza_id) AND (correction_timestamp IS NULL OR correction_timestamp < :correction_timestamp)");
    static let messageFind = Query("SELECT id, account, jid, author_nickname, author_jid, recipient_nickname, participant_id, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, correction_stanza_id, correction_timestamp, markable FROM chat_history WHERE id = :id");
    static let messagesUnreadBefore = Query("SELECT id, case when (recipient_nickname is null and (markable = 1 or author_nickname is not null)) then ifnull(remote_msg_id, stanza_id) else null end markable_id FROM chat_history WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(ConversationEntryState.incoming(.received).rawValue), \(ConversationEntryState.incoming_error(.received, errorMessage: nil).rawValue), \(ConversationEntryState.outgoing_error(.received, errorMessage: nil).rawValue)) order by timestamp asc");
    static let messagesMarkAsReadBefore = Query("UPDATE chat_history SET state = case state when \(ConversationEntryState.incoming_error(.received).rawValue) then \(ConversationEntryState.incoming_error(.displayed).rawValue) when \(ConversationEntryState.outgoing_error(.received).rawValue) then \(ConversationEntryState.outgoing_error(.displayed).rawValue) else \(ConversationEntryState.incoming(.displayed).rawValue) end WHERE account = :account AND jid = :jid AND timestamp <= :before AND state in (\(ConversationEntryState.incoming(.received).rawValue), \(ConversationEntryState.incoming_error(.received).rawValue), \(ConversationEntryState.outgoing_error(.received).rawValue))");
    static let messageUpdateState = Query("UPDATE chat_history SET state = :newState, timestamp = COALESCE(:newTimestamp, timestamp), error = COALESCE(:error, error) WHERE id = :id AND (:oldState IS NULL OR state = :oldState)");
    static let messageUpdate = Query("UPDATE chat_history SET appendix = :appendix WHERE id = :id");
    static let messagesCountUnread = Query("select count(id) from chat_history where account = :account and jid = :jid and timestamp >= (select min(timestamp) from chat_history where account = :account and jid = :jid and state in (\(ConversationEntryState.incoming(.received).rawValue),\(ConversationEntryState.incoming_error(.received).rawValue),\(ConversationEntryState.outgoing_error(.received).rawValue)))");
}

class DBChatHistoryStore {

    static let MESSAGE_NEW = Notification.Name("messageAdded");
    // TODO: it looks like it is not working as expected. We should remove this notification in the future
    static let MESSAGES_MARKED_AS_READ = Notification.Name("messagesMarkedAsRead");
    static let MESSAGE_UPDATED = Notification.Name("messageUpdated");
    static let MESSAGE_REMOVED = Notification.Name("messageRemoved");
    static var instance: DBChatHistoryStore = DBChatHistoryStore.init();
    
    static func convertToAttachments() {
        let diskCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!).appendingPathComponent("download", isDirectory: true);
        guard FileManager.default.fileExists(atPath: diskCacheUrl.path) else {
            return;
        }

        let previewsToConvert: [Int] = try! Database.main.reader({ database in
            try database.select("SELECT id FROM chat_history WHERE preview IS NOT NULL", cached: false).mapAll({ $0.int(for: "id") });
        })

        let removePreview = { (id: Int) in
            try! Database.main.writer({ database in
                try database.update("UPDATE chat_history SET preview = NULL WHERE id = ?", params: [id]);
            })
        };

        for id in previewsToConvert {
            guard let (item, previews, stanzaId) = try! Database.main.reader({ database in
                return try database.select("SELECT id, account, jid, author_nickname, author_jid, timestamp, item_type, data, state, preview, encryption, fingerprint, error, appendix, preview, stanza_id, correction_timestamp, markable FROM chat_history WHERE id = ?", cached: true, params: [id]).mapFirst({ cursor -> (ConversationEntry, [String:String], String?)? in
                    let account: BareJID = cursor["account"]!;
                    let jid: BareJID = cursor["jid"]!;
                    let key = ConversationKeyItem(account: account, jid: jid);
                    let stanzaId: String? = cursor["stanza_id"];
                    guard let item = DBChatHistoryStore.instance.itemFrom(cursor: cursor, for: key), let previewStr: String = cursor["preview"] else {
                        return nil;
                    }
                    var previews: [String:String] = [:];
                    previewStr.split(separator: "\n").forEach { (line) in
                        let tmp = line.split(separator: "\t").map({String($0)});
                        if (!tmp[1].starts(with: "ERROR")) && (tmp[1] != "NONE") {
                            previews[tmp[0]] = tmp[1];
                        }
                    }
                    return (item, previews, stanzaId);
                });
            }) else {
                return;
            }

            if previews.isEmpty {
                removePreview(item.id);
            } else {
                print("converting for:", item.conversation, "previews:", previews);
                if previews.count == 1 {
                    switch item.payload {
                    case .message(let message, let correctionTimestamp):
                        let isAttachmentOnly = URL(string: message) != nil;
                        
                        if isAttachmentOnly {
                            let appendix = ChatAttachmentAppendix();
                            DBChatHistoryStore.instance.appendItem(for: item.conversation, state: item.state, sender: item.sender, type: .attachment, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: message, appendix: appendix, options: item.options, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                DBChatHistoryStore.instance.remove(item: item);
                            });
                        } else {
                            DBChatHistoryStore.instance.appendItem(for: item.conversation, state: item.state, sender: item.sender, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: previews.keys.first ?? message, options: item.options, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                removePreview(item.id);
                            });
                        }
                    default:
                        break;
                    }
                } else {
                    let group = DispatchGroup();
                    group.enter();

                    group.notify(queue: DispatchQueue.main, execute: {
                        removePreview(item.id);
                    })

                    for (url, _) in previews {
                        group.enter();
                        DBChatHistoryStore.instance.appendItem(for: item.conversation, state: item.state, sender: item.sender, type: .linkPreview, timestamp: item.timestamp, stanzaId: stanzaId, serverMsgId: nil, remoteMsgId: nil, data: url, options: item.options, linkPreviewAction: .none, masterId: nil, completionHandler: { newId in
                                group.leave();
                        });
                    }
                    group.leave();
                }
            }
        }

        try? FileManager.default.removeItem(at: diskCacheUrl);
    }

    public enum MessageEvent {
        case added(ConversationEntry)
        case updated(ConversationEntry)
        case removed(ConversationEntry)
    }
    
    public let events = PassthroughSubject<MessageEvent, Never>();

    public init() {
        previewGenerationQueue.maxConcurrentOperationCount = 1;
    }

    open func process(chatState: ChatState, for conversation: ConversationKey) {
        self.process(chatState: chatState, for: conversation.account, with: conversation.jid);
    }
    
    open func process(chatState: ChatState, for account: BareJID, with jid: BareJID) {
        DBChatStore.instance.process(chatState: chatState, for: account, with: jid);
    }

    enum MessageSource {
        case stream
        case archive(source: BareJID, version: MessageArchiveManagementModule.Version, messageId: String, timestamp: Date)
        case carbons(action: MessageCarbonsModule.Action)
    }
    private var enqueuedItems = 0;
    
    open func append(for conversation: ConversationKey, message: Message, source: MessageSource) {
        let direction: MessageDirection = conversation.account == message.from?.bareJid ? .outgoing : .incoming;
        guard let jidFull = direction == .outgoing ? message.to : message.from else {
            // sender jid should always be there..
            return;
        }

        let jid = jidFull.withoutResource;

        let (decryptedBody, encryption, fingerprint) = MessageEventHandler.prepareBody(message: message, forAccount: conversation.account);
        let mixInvitation = message.mixInvitation;

        var itemType = MessageEventHandler.itemType(fromMessage: message);
        let stanzaId = message.originId ?? message.id;
        var stableIds = message.stanzaId;
        var fromArchive = false;

        var inTimestamp: Date?;

        switch source {
        case .archive(let source, let version, let messageId, let timestamp):
            if version == .MAM2 {
                if stableIds == nil {
                    stableIds = [source: messageId];
                } else {
                    stableIds?[source] = messageId;
                }
            }
            inTimestamp = timestamp;
            if message.type == .groupchat {
                fromArchive = false; //source != account;
            } else {
                fromArchive = true;
            }
        default:
            inTimestamp = message.delay?.stamp;
            break;
        }

        let serverMsgId: String? = stableIds?[conversation.account];
        let remoteMsgId: String? = stableIds?[jid.bareJid];

        guard let (sender, recipient) = MessageEventHandler.extractRealAuthor(from: message, for: conversation) else {
            return;
        }

        let state = MessageEventHandler.calculateState(direction: MessageEventHandler.calculateDirection(for: conversation, direction: direction, sender: sender), message: message, isFromArchive: fromArchive, isMuc: message.type == .groupchat && message.mix == nil);

        var appendix: AppendixProtocol? = nil;
        if itemType == .message, let mixInivation = mixInvitation {
            itemType = .invitation;
            appendix = ChatInvitationAppendix(mixInvitation: mixInivation);
        }

        let timestamp = Date(timeIntervalSince1970: Double(Int64((inTimestamp ?? Date()).timeIntervalSince1970 * 1000)) / 1000);

        guard let body = decryptedBody ?? (mixInvitation != nil ? "Invitation" : nil) else {
            if let retractedId = message.messageRetractionId, let originId = stanzaId {
                self.retractMessageSync(for: conversation, stanzaId: retractedId, sender: sender, retractionStanzaId: originId, retractionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
                return;
            }
            // only if carbon!!
            switch source {
            case .carbons(let action):
                if action == .received {
                    if (message.type ?? .normal) != .error, let chatState = message.chatState, message.delay == nil {
                        DBChatHistoryStore.instance.process(chatState: chatState, for: conversation);
                    }
                }
            default:
                if (message.type ?? .normal) != .error, let chatState = message.chatState, message.delay == nil {
                    DBChatHistoryStore.instance.process(chatState: chatState, for: conversation);
                }
                break;
            }
            return;
        }

        guard !state.isError || stanzaId == nil || !self.processOutgoingError(for: conversation, stanzaId: stanzaId!, errorCondition: message.errorCondition, errorMessage: message.errorText) else {
            return;
        }

        if let retractedId = message.messageRetractionId, let originId = stanzaId {
            self.retractMessageSync(for: conversation, stanzaId: retractedId, sender: sender, retractionStanzaId: originId, retractionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
            return;
        }
        if let originId = stanzaId, let correctedMessageId = message.lastMessageCorrectionId, self.correctMessageSync(for: conversation, stanzaId: correctedMessageId, sender: sender, data: body, correctionStanzaId: originId, correctionTimestamp: timestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, newState: state) {
            if let chatState = message.chatState {
                DBChatStore.instance.process(chatState: chatState, for: conversation.account, with: conversation.jid);
            }
            return;
        }

        if let stableId = serverMsgId, self.findItemId(for: conversation.account, serverMsgId: stableId) != nil {
            return;
        }

        if let originId = stanzaId, let existingMessageId = self.findItemId(for: conversation, originId: originId, sender: sender) {
            if let stableId = serverMsgId {
                try! Database.main.writer({ database in
                    try database.update(query: .messageUpdateServerMsgId, params: ["id": existingMessageId, "server_msg_id": stableId]);
                })
            }
            return;
        }
        
        let options = ConversationEntry.Options(recipient: recipient, encryption: .from(messageEncryption: encryption, fingerprint: fingerprint), isMarkable: message.isMarkable)

        self.appendItemSync(for: conversation, state: state, sender: sender, type: itemType, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: body, chatState: message.chatState, appendix: appendix, options: options, linkPreviewAction: .auto, masterId: nil, completionHandler: nil);

        if state.direction == .outgoing {
            self.markAsRead(for: conversation.account, with: conversation.jid, before: timestamp, sendMarkers: false);
        } else {
            if recipient == .none {
                switch sender {
                case .none, .me(_):
                    break
                case .buddy(_):
                    if let originId = stanzaId {
                        var receipts: [MessageEventHandler.ReceiptType] = options.isMarkable ? [.chatMarker] : [];
                        if let receipt = message.messageDelivery, case .request = receipt {
                            receipts.append(.deliveryReceipt);
                        }
                        MessageEventHandler.instance.sendReceived(for: conversation, timestamp: timestamp, stanzaId: originId, receipts: receipts);
                    }
                case .occupant(_,_), .participant(_, _, _):
                    if let stanzaId = remoteMsgId {
                        let receipts: [MessageEventHandler.ReceiptType] = options.isMarkable ? [.chatMarker] : [];
                        MessageEventHandler.instance.sendReceived(for: conversation, timestamp: timestamp, stanzaId: stanzaId, receipts: receipts);
                    }
                }
            }
        }
    }

    enum LinkPreviewAction {
        case auto
        case none
        case only
    }

    func findItemId(for conversation: ConversationKey, remoteMsgId: String) -> Int? {
        return try! Database.main.reader({ database -> Int? in
            return try database.select(query: .messageFindIdByRemoteMsgId, params: ["remote_msg_id": remoteMsgId, "account": conversation.account, "jid": conversation.jid]).mapFirst({ $0.int(for: "id") });
        })
    }

    private func findItemId(for account: BareJID, serverMsgId: String) -> Int? {
        return try! Database.main.reader({ database -> Int? in
            return try database.select(query: .messageFindIdByServerMsgId, params: ["server_msg_id": serverMsgId, "account": account]).mapFirst({ $0.int(for: "id") });
        })
    }

    func findItemId(for conversation: ConversationKey, originId: String, sender: ConversationEntrySender) -> Int? {
        var params: [String: Any?] = ["stanza_id": originId, "account": conversation.account, "jid": conversation.jid, "author_nickname": nil, "participant_id": nil];
        switch sender {
        case .none, .buddy(_), .me(_):
            break;
        case .occupant(let nickname, _):
            params["author_nickname"] = nickname;
        case .participant(let id, _, _):
            params["participant_id"] = id;
        }
        return try! Database.main.reader({ database -> Int? in
            return try database.select(query: .messageFindIdByOriginId, params: params).mapFirst({ $0.int(for: "id") });
        })
    }

//    private func findItemId(for account: BareJID, with jid: BareJID, timestamp: Date, direction: MessageDirection, itemType: ItemType, stanzaId: String?, authorNickname: String?, data: String?) -> Int? {
//        let range = stanzaId == nil ? 5.0 : 60.0;
//        let ts_from = timestamp.addingTimeInterval(-60 * range);
//        let ts_to = timestamp.addingTimeInterval(60 * range);
//
//        let params: [String: Any?] = ["account": account, "jid": jid, "ts_from": ts_from, "ts_to": ts_to, "item_type": itemType.rawValue, "direction": direction.rawValue, "stanza_id": stanzaId, "data": data, "author_nickname": authorNickname];
//
//        return try! self.findItemFallback.findFirst(params, map: { cursor -> Int? in
//            return cursor["id"];
//        })
//    }

    private func appendItemSync(for conversation: ConversationKey, state: ConversationEntryState, sender: ConversationEntrySender, type: ItemType, timestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState?,  appendix: AppendixProtocol?, options: ConversationEntry.Options, linkPreviewAction: LinkPreviewAction, masterId: Int? = nil, completionHandler: ((Int) -> Void)?) {
        var item: ConversationEntry?;
        if linkPreviewAction != .only {
            var params: [String:Any?] = ["account": conversation.account, "jid": conversation.jid, "timestamp": timestamp, "data": data, "item_type": type.rawValue, "state": state.code, "stanza_id": stanzaId, "author_nickname": nil, "author_jid": nil, "recipient_nickname": options.recipient.nickname, "participant_id": nil, "encryption": options.encryption.value.rawValue, "fingerprint": options.encryption.fingerprint, "error": state.errorMessage, "appendix": appendix, "server_msg_id": serverMsgId, "remote_msg_id": remoteMsgId, "master_id": masterId, "markable": options.isMarkable];

            switch sender {
            case .none, .me(_), .buddy(_):
                break;
            case .occupant(let nickname, let jid):
                params["author_nickname"] = nickname;
                params["author_jid"] = jid;
            case .participant(let id, let nickname, let jid):
                params["participant_id"] = id;
                params["author_nickname"] = nickname;
                params["author_jid"] = jid;
            }
            
            guard let id = try! Database.main.writer({ database -> Int? in
                try database.insert(query: .messageInsert, params: params);
                return database.lastInsertedRowId;
            }) else {
                return;
            }
            completionHandler?(id);

            var payload: ConversationEntryPayload?;
            
            switch type {
            case .message:
                payload = .message(message: data, correctionTimestamp: nil);
            case .invitation:
                payload = .invitation(message: data, appendix: appendix as! ChatInvitationAppendix);
            case .attachment:
                payload = .attachment(url: data, appendix: (appendix as? ChatAttachmentAppendix) ?? ChatAttachmentAppendix());
            case .linkPreview:
                if Settings.linkPreviews {
                    payload = .linkPreview(url: data)
                }
            case .messageRetracted, .attachmentRetracted:
                // nothing to do, as we do not want notifications for that (at least for now and no item of that type would be created in here!
                break;
            }
            
            if let payload = payload {
                let entry = ConversationEntry(id: id, conversation: conversation, timestamp: timestamp, state: state, sender: sender, payload: payload, options: options);
                
                DBChatStore.instance.newMessage(for: conversation.account, with: conversation.jid, timestamp: timestamp, itemType: type, message: options.encryption.message() ?? data, state: state, remoteChatState: state.direction == .incoming ? chatState : nil, senderNickname: sender.isGroupchat ? sender.nickname : nil) {
                    NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_NEW, object: entry);
                }
                
                self.events.send(.added(entry));
                NotificationManager.instance.newMessage(entry);

                item = entry;
            }
        }
        if linkPreviewAction != .none && type == .message, let id = item?.id {
            self.generatePreviews(forItem: id, conversation: conversation, state: state, sender: sender, timestamp: timestamp, data: data, options: options, action: .new);
        }
    }

    open func appendItem(for conversation: ConversationKey, state: ConversationEntryState, sender: ConversationEntrySender, type: ItemType, timestamp inTimestamp: Date, stanzaId: String?, serverMsgId: String?, remoteMsgId: String?, data: String, chatState: ChatState? = nil, appendix: AppendixProtocol? = nil, options: ConversationEntry.Options, linkPreviewAction: LinkPreviewAction, masterId: Int? = nil, completionHandler: ((Int) -> Void)?) {

        let timestamp = Date(timeIntervalSince1970: Double(Int64(inTimestamp.timeIntervalSince1970 * 1000)) / 1000);
        self.appendItemSync(for: conversation, state: state, sender: sender, type: type, timestamp: timestamp, stanzaId: stanzaId, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId, data: data, chatState: chatState, appendix: appendix, options: options, linkPreviewAction: linkPreviewAction, masterId: masterId, completionHandler: completionHandler);
    }

    open func removeHistory(for account: BareJID, with jid: JID?) {
        try! Database.main.writer({ database in
            try database.delete(query: .messagesDeleteChatHistory, cached: false, params: ["account": account, "jid": jid]);
        })
    }

    open func correctMessage(for conversation: ConversationKey, stanzaId: String, sender: ConversationEntrySender, data: String, correctionStanzaId: String?, correctionTimestamp: Date, newState: ConversationEntryState) {
        let timestamp = Date(timeIntervalSince1970: Double(Int64((correctionTimestamp).timeIntervalSince1970 * 1000)) / 1000);
        _ = self.correctMessageSync(for: conversation, stanzaId: stanzaId, sender: sender, data: data, correctionStanzaId: correctionStanzaId, correctionTimestamp: timestamp, serverMsgId: nil, remoteMsgId: nil, newState: newState);
    }

    // TODO: Is it not "the same" as message retraction? Maybe we should unify?
    private func correctMessageSync(for conversation: ConversationKey, stanzaId: String, sender: ConversationEntrySender, data: String, correctionStanzaId: String?, correctionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?, newState: ConversationEntryState) -> Bool {
        // we need to check participant-id/sender nickname to make it work correctly
        // moreover, stanza-id should be checked with origin-id for MUC/MIX (not message id)
        // MIX/MUC should send origin-id if they assume to use last message correction!
        if let oldItem = self.findItem(for: conversation, originId: stanzaId, sender: sender) {
            let itemId = oldItem.id;
            let params: [String: Any?] = ["id": itemId, "data": data, "state": newState.code, "correction_stanza_id": correctionStanzaId, "remote_msg_id": remoteMsgId, "server_msg_id": serverMsgId, "correction_timestamp": correctionTimestamp];
            let updated = try! Database.main.writer({ database -> Int in
                try! database.update(query: .messageCorrectLast, params: params);
                return database.changes;
            })
            if updated > 0 {
                markedAsRead.send(MarkedAsRead(account: conversation.account, jid: conversation.jid, messages: [.init(id: oldItem.id, markableId: nil)]));

                let newMessageState: ConversationEntryState = (oldItem.state.direction == .incoming) ? (oldItem.state.isUnread ? .incoming(.displayed) : .incoming(newState.isUnread ? .received : .displayed)) : (.outgoing(.sent));
                DBChatStore.instance.newMessage(for: conversation.account, with: conversation.jid, timestamp: oldItem.timestamp, itemType: .message, message: data, state: newMessageState, completionHandler: {
                })

                print("correcing previews for master id:", itemId);
                self.itemUpdated(withId: itemId, for: conversation);
                
                if case .outgoing(let state) = newState, state == .unsent {
                } else {
                    self.generatePreviews(forItem: itemId, conversation: conversation, state: newState, action: .update);
                }
            }
            return true;
        } else {
            return false;
        }
    }

    public func retractMessage(for conversation: Conversation, stanzaId: String, sender: ConversationEntrySender, retractionStanzaId: String?, retractionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?) {
        self.retractMessageSync(for: conversation, stanzaId: stanzaId, sender: sender, retractionStanzaId: retractionStanzaId, retractionTimestamp: retractionTimestamp, serverMsgId: serverMsgId, remoteMsgId: remoteMsgId);
    }

    private func retractMessageSync(for conversation: ConversationKey, stanzaId: String, sender: ConversationEntrySender, retractionStanzaId: String?, retractionTimestamp: Date, serverMsgId: String?, remoteMsgId: String?) {
        if let oldItem = self.findItem(for: conversation, originId: stanzaId, sender: sender) {
            let itemId = oldItem.id;
            var itemType: ItemType = .messageRetracted;
            if case .attachment(_,_) = oldItem.payload {
                itemType = .attachmentRetracted;
            }
            let params: [String: Any?] = ["id": itemId, "item_type": itemType.rawValue, "correction_stanza_id": retractionStanzaId, "remote_msg_id": remoteMsgId, "server_msg_id": serverMsgId, "correction_timestamp": retractionTimestamp];
            let updated = try! Database.main.writer({ database -> Int in
                try database.update(query: .messageRetract, params: params);
                return database.changes;
            })
            if updated > 0 {
                markedAsRead.send(MarkedAsRead(account: conversation.account, jid: conversation.jid, messages: [.init(id: oldItem.id, markableId: nil)]));

                // what should be sent to "newMessage" how to reatract message from there??
                let activity: LastChatActivity = DBChatStore.instance.lastActivity(for: conversation.account, jid: conversation.jid) ?? .message("", direction: .incoming, sender: nil);
                DBChatStore.instance.newMessage(for: conversation.account, with: conversation.jid, timestamp: oldItem.timestamp, lastActivity: activity, state: oldItem.state.direction == .incoming ? .incoming(.displayed) : .outgoing(.sent), completionHandler: {
                    print("chat store state updated with message retraction");
                })
                if oldItem.state.isUnread {
                    DBChatStore.instance.markAsRead(for: conversation.account, with: conversation.jid, count: 1);
                }

                self.itemUpdated(withId: itemId, for: conversation);
//                   self.itemRemoved(withId: itemId, for: account, with: jid);
                self.generatePreviews(forItem: itemId, conversation: conversation, state: oldItem.state, action: .remove);
            }
        }
    }

    private func findItem(for conversation: ConversationKey, originId: String, sender: ConversationEntrySender) -> ConversationEntry? {
        guard let itemId = findItemId(for: conversation, originId: originId, sender: sender) else {
            return nil;
        }
        return message(for: conversation, withId: itemId);
    }

    func message(for conversation: ConversationKey, withId msgId: Int) -> ConversationEntry? {
        return try! Database.main.writer({ database -> ConversationEntry? in
            return try database.select(query: .messageFind, params: ["id": msgId]).mapFirst({ cursor -> ConversationEntry? in
                return self.itemFrom(cursor: cursor, for: conversation);
            });
        });
    }

    private func generatePreviews(forItem masterId: Int, conversation: ConversationKey, state: ConversationEntryState, action: PreviewActon) {
        guard let item = self.message(for: conversation, withId: masterId), case .message(let message, _) = item.payload else {
            return;
        }

        self.generatePreviews(forItem: item.id, conversation: conversation, state: item.state, sender: item.sender, timestamp: item.timestamp, data: message, options: item.options, action: action);
    }

    private let previewGenerationQueue = OperationQueue();//QueueDispatcher(label: "chat_history_store", attributes: [.concurrent]);

    
    private enum PreviewActon {
        case new
        case update
        case remove
    }
    
    private func generatePreviews(forItem masterId: Int, conversation: ConversationKey, state entryState: ConversationEntryState, sender: ConversationEntrySender, timestamp: Date, data: String, options: ConversationEntry.Options, action: PreviewActon) {
        let operation = BlockOperation(block: {
            if action != .new {
                DBChatHistoryStore.instance.removePreviews(idOfRelatedToItem: masterId);
            }
            
            if action != .remove {
            print("generating previews for master id:", masterId);
            // if we may have previews, we should add them here..
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
                let matches = detector.matches(in: data, range: NSMakeRange(0, data.utf16.count));
                print("adding previews for master id:", masterId);
                let state = entryState == .incoming(.received) ? .incoming(.displayed) : entryState;
                let newOptions = ConversationEntry.Options(recipient: options.recipient, encryption: .none, isMarkable: false);
                for match in matches {
                    if let url = match.url, let scheme = url.scheme, ["https", "http"].contains(scheme) {
                        if (data as NSString).range(of: "http", options: .caseInsensitive, range: match.range).location == match.range.location {
                            DBChatHistoryStore.instance.appendItem(for: conversation, state: state, sender: sender, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: url.absoluteString, options: newOptions, linkPreviewAction: .none, masterId: masterId, completionHandler: nil);
                        }
                    }
                    if let address = match.components {
                        let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                        let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                        DBChatHistoryStore.instance.appendItem(for: conversation, state: state, sender: sender, type: .linkPreview, timestamp: timestamp, stanzaId: nil, serverMsgId: nil, remoteMsgId: nil, data: mapUrl.absoluteString, options: newOptions, linkPreviewAction: .none, masterId: masterId, completionHandler: nil);
                    }
                }
            }
            }
        });
        previewGenerationQueue.addOperation(operation);
    }

    fileprivate func processOutgoingError(for conversation: ConversationKey, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) -> Bool {
        guard let itemId = findItemId(for: conversation, originId: stanzaId, sender: .none) else {
            return false;
        }

        guard try! Database.main.writer({ database -> Int in
            try! database.update(query: .messageUpdateState, params: ["id": itemId, "newState": ConversationEntryState.outgoing_error(.received).rawValue, "error": errorMessage ?? errorCondition?.rawValue ?? "Unknown error"]);
            return database.changes;
        }) > 0 else {
            return false;
        }
        DBChatStore.instance.newMessage(for: conversation.account, with: conversation.jid, timestamp: Date(timeIntervalSince1970: 0), itemType: nil, message: nil, state: .outgoing_error(.received, errorMessage: errorMessage ?? errorCondition?.rawValue ?? "Unknown error")) {
            self.itemUpdated(withId: itemId, for: conversation);
        }
        return true;
    }

    open func markOutgoingAsError(for conversation: ConversationKey, stanzaId: String, errorCondition: ErrorCondition?, errorMessage: String?) {
        _ = self.processOutgoingError(for: conversation, stanzaId: stanzaId, errorCondition: errorCondition, errorMessage: errorMessage);
    }
    
    open func markAsRead(for conversation: Conversation, before: Date) {
        markAsRead(for: conversation.account, with: conversation.jid, before: before, sendMarkers: true);
    }

    let markedAsRead = PassthroughSubject<MarkedAsRead,Never>();
    
    struct MarkedAsRead {
        let account: BareJID;
        let jid: BareJID;
        let messages: [Message];
        
        struct Message {
            let id: Int;
            let markableId: String?;
        }
    }
    
    open func markAsRead(for account: BareJID, with jid: BareJID, before: Date, sendMarkers: Bool) {
        let updatedRecords = try! Database.main.writer({ database -> [MarkedAsRead.Message] in
            let markedAsRead = try database.select(query: .messagesUnreadBefore, params: ["account": account, "jid": jid, "before": before]).mapAll({ curor in MarkedAsRead.Message(id: curor.int(for: "id")!, markableId: sendMarkers ? curor.string(for: "markable_id") : nil) });
            if !markedAsRead.isEmpty {
                try database.update(query: .messagesMarkAsReadBefore, params: ["account": account, "jid": jid, "before": before]);
            }
            return markedAsRead;
        })
        
        if !updatedRecords.isEmpty {
            DBChatStore.instance.markAsRead(for: account, with: jid, count: updatedRecords.count);
            markedAsRead.send(MarkedAsRead(account: account, jid: jid, messages: updatedRecords));
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGES_MARKED_AS_READ, object: self, userInfo: ["account": account, "jid": jid]);
            }
        }
    }

//    open func getItemId(for conversation: ConversationKey, stanzaId: String) -> Int? {
//        return dispatcher.sync {
//            return self.findItemId(for: conversation, originId: stanzaId, authorNickname: nil, participantId: nil);
//        }
//    }

//    open func itemPosition(for account: BareJID, with jid: BareJID, msgId: Int) -> Int? {
//        return dispatcher.sync {
//            return try! Database.main.reader({ database in
//                return try database.select(query: .messageFindPositionInChat, params: ["account": account, "jid": jid, "msgId": msgId, "showLinkPreviews": linkPreviews]).mapFirst({ $0.int(at: 0) });
//            })
//        }
//    }

    open func updateItemState(for conversation: ConversationKey, stanzaId: String, from oldState: ConversationEntryState, to newState: ConversationEntryState, withTimestamp timestamp: Date? = nil) {
        guard let msgId = self.findItemId(for: conversation, originId: stanzaId, sender: .none) else {
            return;
        }

        self.updateItemState(for: conversation, itemId: msgId, from: oldState, to: newState, withTimestamp: timestamp);
    }

    open func updateItemState(for conversation: ConversationKey, itemId msgId: Int, from oldState: ConversationEntryState, to newState: ConversationEntryState, withTimestamp timestamp: Date?) -> Bool {
        guard try! Database.main.writer({ database -> Int in
            try database.update(query: .messageUpdateState, params:  ["id": msgId, "oldState": oldState.code, "newState": newState.code, "newTimestamp": timestamp]);
            return database.changes;
        }) > 0 else {
            return false;
        }
        self.itemUpdated(withId: msgId, for: conversation);
        if oldState == .outgoing(.unsent) && newState != .outgoing(.unsent) {
            self.generatePreviews(forItem: msgId, conversation: conversation, state: newState, action: .new);
        }
        return true;
    }
    
    open func remove(item: ConversationEntry) {
        guard try! Database.main.writer({ database in
            try database.delete(query: .messageDelete, cached: false, params: ["id": item.id]);
            return database.changes;
        }) > 0 else {
            return;
        }
        self.itemRemoved(withId: item.id, for: item.conversation);
        self.removePreviews(idOfRelatedToItem: item.id);
    }

    private func removePreviews(idOfRelatedToItem masterId: Int) {
        let linkPreviews = try! Database.main.reader({ database in
            return try database.select(query: .messageFindLinkPreviewsForMessage, cached: false, params: ["master_id": masterId]).mapAll({ cursor -> (Int, BareJID, BareJID)? in
                guard let id: Int = cursor["id"], let account: BareJID = cursor["account"], let jid: BareJID = cursor["jid"] else {
                    return nil;
                }
                return (id, account, jid);
            })
        })

        // for chat message we might have a link previews which we need to remove..
        guard !linkPreviews.isEmpty else {
            return;
        }
        for (id, account, jid) in linkPreviews {
            // this is a preview and needs to be removed..
            let removeLinkParams: [String: Any?] = ["id": id];
            if try! Database.main.writer({ database -> Int in
                try database.delete(query: .messageDelete, cached: false, params: removeLinkParams);
                return database.changes;
            }) > 0 {
                self.itemRemoved(withId: id, for: ConversationKeyItem(account: account, jid: jid));
            }
        }
    }

    func originId(for key: ConversationKey, id: Int, completionHandler: @escaping (String)->Void ){
        self.originId(for: key.account, with: key.jid, id: id, completionHandler: completionHandler);
    }
    
    func originId(for account: BareJID, with jid: BareJID, id: Int, completionHandler: @escaping (String)->Void ){
        if let stanzaId = try! Database.main.reader({ dataase in
            try dataase.select(query: .messageFindMessageOriginId, cached: false, params: ["id": id]).mapFirst({ $0.string(for: "stanza_id")});
        }) {
            DispatchQueue.main.async {
                completionHandler(stanzaId);
            }
        }
    }

    open func updateItem(for conversation: ConversationKey, id: Int, updateAppendix updateFn: @escaping (inout ChatAttachmentAppendix)->Void) {
        guard let oldItem = self.message(for: conversation, withId: id) else {
            return;
        }
        
        switch oldItem.payload {
        case .attachment(let url, var appendix):
            updateFn(&appendix);
            try! Database.main.writer({ database in
                try database.update(query: .messageUpdate, params: ["id": id, "appendix": appendix]);
            })
            let item = ConversationEntry(id: oldItem.id, conversation: oldItem.conversation, timestamp: oldItem.timestamp, state: oldItem.state, sender: oldItem.sender, payload: .attachment(url: url, appendix: appendix), options: oldItem.options);
            events.send(.updated(item));
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
            }
        default:
            return;
        }
    }

    func loadUnsentMessage(for account: BareJID, completionHandler: @escaping (BareJID,[UnsentMessage])->Void) {
        let messages = try! Database.main.reader({ database in
            try database.select(query: .messagesFindUnsent, cached: false, params: ["account": account]).mapAll(UnsentMessage.from(cursor: ))
        })
        completionHandler(account, messages);
    }

    fileprivate func itemUpdated(withId id: Int, for conversation: ConversationKey) {
        guard let item = self.message(for: conversation, withId: id) else {
            return;
        }
        events.send(.updated(item));
        NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_UPDATED, object: item);
    }

    fileprivate func itemRemoved(withId id: Int, for conversation: ConversationKey) {
        let entry = ConversationEntry(id: id, conversation: conversation, timestamp: Date(), state: .none, sender: .none, payload: .deleted, options: .none);
        events.send(.removed(entry));
        NotificationCenter.default.post(name: DBChatHistoryStore.MESSAGE_REMOVED, object: entry);
    }

    func lastMessageTimestamp(for account: BareJID) -> Date {
        return try! Database.main.reader({ database in
            return try database.select(query: .messagesLastTimestampForAccount, cached: false, params: ["account": account]).mapFirst({ $0.date(for: "timestamp") }) ?? Date(timeIntervalSince1970: 0);
        });
    }

    open func history(for conversation: Conversation, queryType: ConversationLoadType) -> [ConversationEntry] {
        return try! Database.main.reader({ database in
            switch queryType {
            case .with(let id, let overhead):
                let position = try database.count(query: .messageFindPositionInChat, cached: true, params: ["account": conversation.account, "jid": conversation.jid, "msgId": id, "showLinkPreviews": linkPreviews]);
                let cursor = try database.select(query: .messagesFindForChat, params: ["account": conversation.account, "jid": conversation.jid, "offset": 0, "limit": position + overhead, "showLinkPreviews": self.linkPreviews])
                return try cursor.mapAll({ cursor -> ConversationEntry? in self.itemFrom(cursor: cursor, for: conversation) });
            case .unread(let overhead):
                let unread = try database.count(query: .messagesCountUnread, cached: true, params: ["account": conversation.account, "jid": conversation.jid]);
                    
                let cursor = try database.select(query: .messagesFindForChat, params: ["account": conversation.account, "jid": conversation.jid, "offset": 0, "limit": unread + overhead, "showLinkPreviews": self.linkPreviews])
                return try cursor.mapAll({ cursor -> ConversationEntry? in self.itemFrom(cursor: cursor, for: conversation) });
            case .before(let item, let limit):
                let position = try database.count(query: .messageFindPositionInChat, cached: true, params: ["account": conversation.account, "jid": conversation.jid, "msgId": item.id, "showLinkPreviews": linkPreviews]);
                let cursor = try database.select(query: .messagesFindForChat, params: ["account": conversation.account, "jid": conversation.jid, "offset": position, "limit": limit, "showLinkPreviews": self.linkPreviews])
                return try cursor.mapAll({ cursor -> ConversationEntry? in self.itemFrom(cursor: cursor, for: conversation) });
            }
        })
    }

    open func searchHistory(for account: BareJID? = nil, with jid: JID? = nil, search: String, completionHandler: @escaping ([ConversationEntry])->Void) {
        // TODO: Remove this dispatch. async is OK but it is not needed to be done in a blocking maner
        let tokens = search.unicodeScalars.split(whereSeparator: { (c) -> Bool in
            return CharacterSet.punctuationCharacters.contains(c) || CharacterSet.whitespacesAndNewlines.contains(c);
        }).map({ (s) -> String in
            return String(s) + "*";
        });
        let query = tokens.joined(separator: " + ");
        print("searching for:", tokens, "query:", query);
        let items = try! Database.main.reader({ database in
            try database.select(query: .messageSearchHistory, params: ["account": account, "jid": jid, "query": query]).mapAll({ cursor -> ConversationEntry? in
                guard let account: BareJID = cursor["account"], let jid: BareJID = cursor["jid"] else {
                    return nil;
                }
                return self.itemFrom(cursor: cursor, for: ConversationKeyItem(account: account, jid: jid));
            })
        });
        completionHandler(items);
    }

    public func loadAttachments(for conversation: ConversationKey, completionHandler: @escaping ([ConversationEntry])->Void) {
        // TODO: Why it is done in async manner but on a single thread? what is the point here?
        let params: [String: Any?] = ["account": conversation.account, "jid": conversation.jid];
        let attachments = try! Database.main.reader({ database in
            return try database.select(query: .messagesFindChatAttachments, cached: false, params: params).mapAll({ cursor -> ConversationEntry? in
                return self.itemFrom(cursor: cursor, for: conversation);
            })
        })
        completionHandler(attachments);
    }

    fileprivate var linkPreviews: Bool {
        return Settings.linkPreviews;
    }

    private func itemFrom(cursor: Cursor, for conversation: ConversationKey) -> ConversationEntry? {
        let id: Int = cursor["id"]!;
        let state: ConversationEntryState = ConversationEntryState.from(cursor: cursor);
        let timestamp: Date = cursor["timestamp"]!;

        guard let entryType = ItemType(rawValue: cursor["item_type"]!) else {
            return nil;
        }

        var correctionTimestamp: Date? = cursor["correction_timestamp"];
        if correctionTimestamp?.timeIntervalSince1970 == 0 {
            correctionTimestamp = nil;
        }

        guard let sender = senderFrom(cursor: cursor, for: conversation, direction: state.direction) else {
            return nil;
        }
        
        let options = ConversationEntry.Options(recipient: recipientFrom(cursor: cursor), encryption: encryptionFrom(cursor: cursor), isMarkable: cursor.bool(for: "markable"));
        
        
        guard let payload = payloadFrom(cursor: cursor, entryType: entryType, correctionTimestamp: correctionTimestamp) else {
            return nil;
        }
        
        return .init(id: id, conversation: conversation, timestamp: timestamp, state: state, sender: sender, payload: payload, options: options);
    }
    
    private func payloadFrom(cursor: Cursor, entryType: ItemType, correctionTimestamp: Date?) -> ConversationEntryPayload? {
        switch entryType {
        case .message:
            guard let message: String = cursor["data"] else {
                return nil;
            }
            return .message(message: message, correctionTimestamp: correctionTimestamp);
        case .messageRetracted:
            return .messageRetracted;
        case .invitation:
            guard let appendix: ChatInvitationAppendix = cursor.object(for: "appendix")else {
                return nil;
            }
            return .invitation(message: cursor["data"], appendix: appendix);
        case .attachment:
            guard let url: String = cursor["data"] else {
                return nil;
            }
            let appendix = cursor.object(for: "appendix") ?? ChatAttachmentAppendix();
            return .attachment(url: url, appendix: appendix);
        case .attachmentRetracted:
            return nil;
        case .linkPreview:
            guard let url: String = cursor["data"] else {
                return nil;
            }
            return .linkPreview(url: url);
        }
    }
    
    private func recipientFrom(cursor: Cursor) -> ConversationEntryRecipient {
        guard let nickname = cursor.string(for: "recipient_nickname") else {
            return .none;
        }
        return .occupant(nickname: nickname);
    }
    
    private func senderFrom(cursor: Cursor, for conversation: ConversationKey, direction: MessageDirection) -> ConversationEntrySender? {
        // guessing based on conversation is not always possible, ie. for plain key (not Conversation)
        switch conversation {
        case is Chat:
            switch direction {
            case .outgoing:
                return .me(conversation: conversation);
            case .incoming:
                return .buddy(conversation: conversation);
            }
        case is Room:
            guard let nickname: String = cursor["author_nickname"] else {
                return nil;
            }
            return .occupant(nickname: nickname, jid: cursor["author_jid"]);
        case is Channel:
            guard let participantId: String = cursor["participant_id"], let nickname: String = cursor["author_nickname"] else {
                guard let nickname: String = cursor["author_nickname"] else {
                    return .buddy(nickname: "");
                }
                return .occupant(nickname: nickname, jid: cursor["author_jid"]);
            }
            return .participant(id: participantId, nickname: nickname, jid: cursor["author_jid"]);
        default:
            if let participantId: String = cursor["participant_id"], let nickname: String = cursor["author_nickname"] {
                return .participant(id: participantId, nickname: nickname, jid: cursor["author_jid"]);
            } else if let nickname: String = cursor["author_nickname"]  {
                return .occupant(nickname: nickname, jid: cursor["author_jid"]);
            } else {
                switch direction {
                case .outgoing:
                    return .me(conversation: conversation);
                case .incoming:
                    return .buddy(conversation: conversation);
                }
            }
        }
    }
    
    private func encryptionFrom(cursor: Cursor) -> ConversationEntryEncryption {
        switch MessageEncryption(rawValue: cursor["encryption"] ?? 0) ?? .none {
        case .none:
            return .none;
        case .decryptionFailed:
            return .decryptionFailed;
        case .notForThisDevice:
            return .notForThisDevice;
        case .decrypted:
            return .decrypted(fingerprint: cursor["fingerprint"]);
        }
    }

}

extension ConversationEntryState {
    
    static func from(cursor: Cursor) -> ConversationEntryState {
        let stateInt: Int = cursor["state"]!;
        return ConversationEntryState.from(code: stateInt, errorMessage: cursor["error"]);
    }
    
}

public enum ItemType: Int {
    case message = 0
    case attachment = 1
    // how about new type called link preview? this way we would have a far less data kept in a single item..
    // we could even have them separated to the new item/entry during adding message to the store..
    case linkPreview = 2
    // with that in place we can have separate metadata kept "per" message as it is only one, so message id can be id of associated metadata..
    case invitation = 3
    case messageRetracted = 4
    case attachmentRetracted = 5;
}

class UnsentMessage {
    let jid: BareJID;
    let type: ItemType;
    let data: String;
    let stanzaId: String;
    let encryption: MessageEncryption;
    let correctionStanzaId: String?;

    init(jid: BareJID, type: ItemType, data: String, stanzaId: String, encryption: MessageEncryption, correctionStanzaId: String?) {
        self.jid = jid;
        self.type = type;
        self.data = data;
        self.stanzaId = stanzaId;
        self.encryption = encryption;
        self.correctionStanzaId = correctionStanzaId;
    }

    static func from(cursor: Cursor) -> UnsentMessage? {
        guard let jid = cursor.bareJid(for: "jid"), let type = ItemType(rawValue: cursor.int(for: "item_type")!), let data = cursor.string(for: "data"), let stanzaId = cursor.string(for: "stanza_id"), let encryption = MessageEncryption(rawValue: cursor.int(for: "encryption") ?? 0) else {
            return nil;
        }
        return UnsentMessage(jid: jid, type: type, data: data, stanzaId: stanzaId, encryption: encryption, correctionStanzaId: cursor.string(for: "correction_stanza_id"));
    }
}
