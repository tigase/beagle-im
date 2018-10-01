//
//  ChatViewController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 13.04.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ChatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate {

    @IBOutlet var buddyAvatarView: AvatarViewWithStatus!
    @IBOutlet var buddyNameLabel: NSTextFieldCell!
    @IBOutlet var buddyJidLabel: NSTextFieldCell!
    @IBOutlet var buddyStatusLabel: NSTextFieldCell!;
    
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
        buddyNameLabel.title = buddyName;
        buddyJidLabel.title = jid.stringValue;
        buddyAvatarView.backgroundColor = NSColor.white;
        buddyAvatarView.update(for: jid, on: account);
        let presenceModule: PresenceModule? = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID);
        buddyStatusLabel.title = presenceModule?.presenceStore.getBestPresence(for: jid)?.status ?? "";
        
        super.viewWillAppear();
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
            cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
            cell.set(senderName: item.state.direction == .incoming ? buddyName : "Me");
            cell.set(message: item.message, timestamp: item.timestamp, state: item.state);
            
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
    }
    
    @IBAction func enterInInputTextField(_ sender: NSTextField) {
        let msg = sender.stringValue
        guard !msg.isEmpty else {
            return;
        }
        
        
        guard sendMessage(body: msg) else {
            return;
        }
        
        (sender as? AutoresizingTextField)?.reset();
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
    
    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, message: String, authorNickname: String?, authorJid: BareJID?) {
        self.id = id;
        self.timestamp = timestamp;
        self.account = account;
        self.message = message;
        self.jid = jid;
        self.state = state;
        self.authorNickname = authorNickname;
        self.authorJid = authorJid;
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
