//
// ChatViewController.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift

class ChatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate {

    @IBOutlet var buddyAvatarView: AvatarViewWithStatus!
    @IBOutlet var buddyNameLabel: NSTextFieldCell!
    @IBOutlet var buddyJidLabel: NSTextFieldCell!
    @IBOutlet var buddyStatusLabel: NSTextFieldCell!;
    
    fileprivate var lastTextChange: Date = Date();
    fileprivate var lastTextChangeTimer: Foundation.Timer?;
    
    @IBOutlet var audioCall: NSButton!
    @IBOutlet var videoCall: NSButton!
    
    override var chat: DBChatProtocol! {
        didSet {
            if let sessionObject = XmppService.instance.getClient(for: account)?.sessionObject {
                buddyName = RosterModule.getRosterStore(sessionObject).get(for: JID(jid))?.name ?? jid.stringValue;
            } else {
                buddyName = jid.stringValue;
            }
        }
    };
    fileprivate var buddyName: String! = "";
    
    override func viewDidLoad() {
        self.dataSource = ChatViewDataSource();
        self.tableView.delegate = self;
        
        super.viewDidLoad();
        
        audioCall.isHidden = true;
        videoCall.isHidden = true;
        
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
        buddyNameLabel.title = buddyName;
        buddyJidLabel.title = jid.stringValue;
        buddyAvatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        buddyAvatarView.update(for: jid, on: account);
        let presenceModule: PresenceModule? = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID);
        buddyStatusLabel.title = presenceModule?.presenceStore.getBestPresence(for: jid)?.status ?? "";
        
        self.updateCapabilities();
        
        super.viewWillAppear();
        lastTextChangeTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (timer) in
            if self.lastTextChange.timeIntervalSinceNow < -10.0 {
                self.change(chatState: .active);
            }
        });
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear();
        lastTextChangeTimer?.invalidate();
        lastTextChangeTimer = nil;
        change(chatState: .active);
    }
    
    fileprivate func change(chatState: ChatState) {
        guard let message = (self.chat as? DBChatStore.DBChat)?.changeChatState(state: chatState) else {
            return;
        }
        guard let messageModule: MessageModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageModule.ID) else {
            return;
        }
        messageModule.context.writer?.write(message);
    }
    
    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification);
        lastTextChange = Date();
        self.change(chatState: .composing);
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {
            
            let item = dataSource.getItem(at: row) as! ChatMessage;
            if (row == dataSource.count-1) {
                DispatchQueue.main.async {
                    self.dataSource.loadItems(before: item.id, limit: 20)
                }
            }
            
            let senderJid = item.state.direction == .incoming ? item.jid : item.account;
            cell.id = item.id;
            cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
            cell.set(senderName: item.state.direction == .incoming ? buddyName : "Me");
            cell.set(message: item);
            
            return cell;
        }
        
        return nil;
    }
    
    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let item = e.rosterItem else {
            return;
        }
        
        DispatchQueue.main.async {
            guard self.account == account && self.jid == item.jid.bareJid else {
                return;
            }
            
            self.buddyName = ((e.action != .removed) ? item.name : nil) ?? self.jid.stringValue;
            self.buddyNameLabel.title = self.buddyName;
            self.itemsReloaded();
        }
    }
    
    @objc func avatarChanged(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
            return;
        }
        guard self.account == account && (self.jid == jid || self.account == jid) else {
            return;
        }
        DispatchQueue.main.async {
            self.buddyAvatarView.avatar = AvatarManager.instance.avatar(for: jid, on: account);
            self.tableView.reloadData();
        }
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let jid = e.presence.from?.bareJid else {
            return;
        }

        guard account == self.account && jid == self.jid else {
            return;
        }
        
        DispatchQueue.main.async {
            self.buddyAvatarView.update(for: jid, on: account);
            self.buddyStatusLabel.title = e.presence.status ?? "";

//            NSAnimationContext.runAnimationGroup({ (_) in
//                NSAnimationContext.current.duration = 0.5;
//                self.buddyStatusLabel.controlView!.animator().alphaValue = 0;
//            }, completionHandler: { () in
//                self.buddyStatusLabel.title = e.presence.status ?? "";
//                NSAnimationContext.runAnimationGroup({ (_) in
//                    NSAnimationContext.current.duration = 0.5;
//                    self.buddyStatusLabel.controlView!.animator().alphaValue = 1;
//                }, completionHandler: nil);
//            });
        }
        
        self.updateCapabilities();
    }
    
    override func sendMessage(body: String? = nil, url: String? = nil) -> Bool {
        guard let msg = body ?? url else {
            return false;
        }
        guard let messageModule: MessageModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageModule.ID) else {
            return false;
        }
        
        guard let chat = messageModule.chatManager.getChat(with: JID(jid), thread: nil) else {
            return false;
        }

        let message = chat.createMessage(msg);
        message.oob = url;
        message.messageDelivery = MessageDeliveryReceiptEnum.request;
        
        messageModule.context.writer?.write(message);
        
        let stanzaId = message.id;
        
        DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing, type: .message, timestamp: Date(), stanzaId: stanzaId, data: msg, completionHandler: nil);

        return true;
    }
    
    fileprivate func updateCapabilities() {
        let supported = JingleManager.instance.support(for: JID(jid), on: account);
        DispatchQueue.main.async {
            self.audioCall.isHidden = !supported.contains(.audio);
            self.videoCall.isHidden = !supported.contains(.video);
        }
    }
    
    @IBAction func audioCallClicked(_ sender: Any) {
        VideoCallController.call(jid: jid, from: account, withAudio: true, withVideo: false);
    }
    
    @IBAction func videoCallClicked(_ sender: NSButton) {
        VideoCallController.call(jid: jid, from: account, withAudio: true, withVideo: true);
    }
    
}

class ChatMessage: ChatViewItemProtocol {
    
    let id: Int;
    let timestamp: Date;
    let account: BareJID;
    let message: String;
    let jid: BareJID;
    let state: MessageState;
    let authorNickname: String?;
    let authorJid: BareJID?;
    let preview: [String:String]?;
    
    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, message: String, authorNickname: String?, authorJid: BareJID?, preview: [String:String]? = nil) {
        self.id = id;
        self.timestamp = timestamp;
        self.account = account;
        self.message = message;
        self.jid = jid;
        self.state = state;
        self.authorNickname = authorNickname;
        self.authorJid = authorJid;
        self.preview = preview;
    }
    
}

public enum MessageState: Int {
    
    // x % 2 == 0 - incoming
    // x % 2 == 1 - outgoing
    case incoming = 0
    case outgoing = 1

    case incoming_unread = 2
    case outgoing_unsent = 3

    case incoming_error = 4
    case outgoing_error = 5

    case incoming_error_unread = 6
    case outgoing_error_unread = 7

    case outgoing_delivered = 9
    case outgoing_read = 11

    var direction: MessageDirection {
        switch self {
        case .incoming, .incoming_unread, .incoming_error, .incoming_error_unread:
            return .incoming;
        case .outgoing, .outgoing_unsent, .outgoing_delivered, .outgoing_read, .outgoing_error_unread, .outgoing_error:
            return .outgoing;
        }
    }
    
    var isError: Bool {
        switch self {
        case .incoming_error, .incoming_error_unread, .outgoing_error, .outgoing_error_unread:
            return true;
        default:
            return false;
        }
    }
    
    var isUnread: Bool {
        switch self {
        case .incoming_unread, .incoming_error_unread, .outgoing_error_unread:
            return true;
        default:
            return false;
        }
    }
    
}

public enum MessageDirection: Int {
    case incoming = 0
    case outgoing = 1
}

class ChatViewTableView: NSTableView {
    override open var isFlipped: Bool {
        return false;
    }
    
}

class ChatViewStatusView: NSTextField {
    
}
