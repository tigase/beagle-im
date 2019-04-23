//
// ChatViewController.swift
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

import AppKit
import TigaseSwift
import TigaseSwiftOMEMO

class ChatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate {

    @IBOutlet var buddyAvatarView: AvatarViewWithStatus!
    @IBOutlet var buddyNameLabel: NSTextFieldCell!
    @IBOutlet var buddyJidLabel: NSTextFieldCell!
    @IBOutlet var buddyStatusLabel: NSTextFieldCell!;
    
    fileprivate var lastTextChange: Date = Date();
    fileprivate var lastTextChangeTimer: Foundation.Timer?;
    
    @IBOutlet var audioCall: NSButton!
    @IBOutlet var videoCall: NSButton!
    @IBOutlet var infoButton: NSButton!;
    
    @IBOutlet var scriptsButton: NSPopUpButton!;
    
    @IBOutlet var encryptButton: NSPopUpButton!;
    
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
        scriptsButton.isHidden = true;
        
        let cgRef = infoButton.image!.cgImage(forProposedRect: nil, context: nil, hints: nil);
        let representation = NSBitmapImageRep(cgImage: cgRef!);
        let newRep = representation.converting(to: .genericGray, renderingIntent: .default);
        infoButton.image = NSImage(cgImage: newRep!.cgImage!, size: infoButton.frame.size);
        
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(omemoAvailabilityChanged), name: MessageEventHandler.OMEMO_AVAILABILITY_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
        buddyNameLabel.title = buddyName;
        buddyJidLabel.title = jid.stringValue;
        buddyAvatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        buddyAvatarView.name = buddyName;
        buddyAvatarView.update(for: jid, on: account);
        let presenceModule: PresenceModule? = XmppService.instance.getClient(for: account)?.modulesManager.getModule(PresenceModule.ID);
        buddyStatusLabel.title = presenceModule?.presenceStore.getBestPresence(for: jid)?.status ?? "";
        
        let itemsCount = self.scriptsButton.menu?.items.count ?? 0;
        if itemsCount > 1 {
            for _ in 1..<itemsCount {
                self.scriptsButton.menu?.removeItem(at: 1)
            }
        }
        if let scripts = ScriptsManager.instance.contactScripts() {
            scripts.forEach { (script) in
                let item = NSMenuItem(title: script.name, action: #selector(scriptActivated(sender:)), keyEquivalent: "");
                item.target = self;
                self.scriptsButton.menu?.addItem(item);
            }
        }
        self.scriptsButton.isHidden = ScriptsManager.instance.contactScripts() == nil;
        
        self.updateCapabilities();
        
        super.viewWillAppear();
        lastTextChangeTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (timer) in
            if self.lastTextChange.timeIntervalSinceNow < -10.0 {
                self.change(chatState: .active);
            }
        });
        
        refreshEncryptionStatus();
    }
    
    @objc func omemoAvailabilityChanged(_ notification: Notification) {
        guard let event = notification.object as? OMEMOModule.AvailabilityChangedEvent else {
            return;
        }
        guard event.account == self.account && self.jid == event.jid else {
            return;
        }
        refreshEncryptionStatus();
    }
    
    @objc func scriptActivated(sender: NSMenuItem) {
        ScriptsManager.instance.contactScripts()?.first(where: { (item) -> Bool in
            return item.name == sender.title;
        })?.execute(account: self.account, jid: JID(self.jid));
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
            self.buddyAvatarView.name = self.buddyName;
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
        let encryption = self.chat.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!;
        if encryption == ChatEncryption.omemo {
            return self.sendEncryptedMessage(body: body, url: url);
        } else {
            return self.sendUnencryptedMessage(body: body, url: url);
        }
    }
    
    fileprivate func createMessage(body: String?, url: String?) -> (Message,MessageModule)? {
        guard let msg = body ?? url else {
            return nil;
        }

        guard let messageModule: MessageModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageModule.ID) else {
            return nil;
        }
        
        guard let chat = messageModule.chatManager.getChat(with: JID(jid), thread: nil) else {
            return nil;
        }
        
        let message = chat.createMessage(msg);
        message.messageDelivery = MessageDeliveryReceiptEnum.request;
        return (message, messageModule);
    }
    
    fileprivate func sendUnencryptedMessage(body: String?, url: String?) -> Bool {
        guard let (message, messageModule) = createMessage(body: body, url: url) else {
            return false;
        }

        let msg = message.body!;
        message.oob = url;
        messageModule.context.writer?.write(message);
        let stanzaId = message.id;
        
        DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing, type: .message, timestamp: Date(), stanzaId: stanzaId, data: msg, encryption: MessageEncryption.none, encryptionFingerprint: nil, completionHandler: nil);
        
        return true;
    }
    
    fileprivate func sendEncryptedMessage(body: String?, url: String?) -> Bool {
        guard let (message, messageModule) = createMessage(body: body, url: url) else {
            return false;
        }
        
        let msg = message.body!;

        guard let omemoModule: OMEMOModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(OMEMOModule.ID) else {
            print("NO OMEMO MODULE!");
            return false;
        }
        let account = self.account!;
        let jid = self.jid!;
        let completionHandler: ((EncryptionResult<Message, SignalError>)->Void)? = { (result) in
            switch result {
            case .failure(let error):
                switch error {
                case .noSession:
                    let alert = NSAlert();
                    alert.messageText = "Could not send message"
                    alert.informativeText = "It was not possible to send encrypted message as there is no trusted device.\n\nWould you like to disable encryption for this chat and send a message?"
                    alert.addButton(withTitle: "No")
                    alert.addButton(withTitle: "Yes")
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                        switch response {
                        case .alertSecondButtonReturn:
                            DBChatStore.instance.changeChatEncryption(for: account, with: jid, to: ChatEncryption.none, completionHandler: {
                                DispatchQueue.main.async {
                                    self.refreshEncryptionStatus();
                                    self.sendUnencryptedMessage(body: body, url: url);
                                }
                            })
                        default:
                            return;
                        }
                    })
                default:
                    let alert = NSAlert();
                    alert.messageText = "Could not send message"
                    alert.informativeText = "It was not possible to send encrypted message due to encryption error";
                    alert.addButton(withTitle: "OK")
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    break;
                }
                break;
            case .successMessage(let encryptedMessage, let fingerprint):
                self.messageField.reset();
                self.updateMessageFieldSize();
                let stanzaId = message.id;
                
                DBChatHistoryStore.instance.appendItem(for: account, with: jid, state: .outgoing, type: .message, timestamp: Date(), stanzaId: stanzaId, data: msg, encryption: .decrypted, encryptionFingerprint: fingerprint, completionHandler: nil);
            }
        };
        
        return omemoModule.send(message: message, completionHandler: completionHandler!);
    }
    
    fileprivate func updateCapabilities() {
        let supported = JingleManager.instance.support(for: JID(jid), on: account);
        DispatchQueue.main.async {
            self.audioCall.isHidden = !(VideoCallController.hasAudioSupport && (supported.contains(.audio) || Settings.ignoreJingleSupportCheck.bool()));
            self.videoCall.isHidden = !(VideoCallController.hasAudioSupport && VideoCallController.hasVideoSupport && (supported.contains(.video) || Settings.ignoreJingleSupportCheck.bool()));
        }
    }
    
    @IBAction func audioCallClicked(_ sender: Any) {
        VideoCallController.call(jid: jid, from: account, withAudio: true, withVideo: false);
    }
    
    @IBAction func videoCallClicked(_ sender: NSButton) {
        VideoCallController.call(jid: jid, from: account, withAudio: true, withVideo: true);
    }
    
    @IBAction func encryptionChanged(_ sender: NSPopUpButton) {
        var encryption: ChatEncryption? = nil;
        switch sender.indexOfSelectedItem {
        case 2:
            encryption = ChatEncryption.none;
        case 3:
            encryption = ChatEncryption.omemo;
        default:
            encryption = nil;
        }
        
        DBChatStore.instance.changeChatEncryption(for: account, with: jid, to: encryption) {
            DispatchQueue.main.async {
                self.refreshEncryptionStatus();
            }
        }
    }
    
    @objc func settingsChanged(_ notification: Notification) {
        guard let setting = notification.object as? Settings else {
            return;
        }
        
        if setting == Settings.messageEncryption {
            refreshEncryptionStatus();
        }
    }
    
    fileprivate func refreshEncryptionStatus() {
        DispatchQueue.main.async {
            guard let account = self.account, let jid = self.jid else {
                return;
            }
            let omemoModule: OMEMOModule? = XmppService.instance.getClient(for: account)?.modulesManager.getModule(OMEMOModule.ID);
            self.encryptButton.isEnabled = omemoModule?.isAvailable(for: jid) ?? false//!DBOMEMOStore.instance.allDevices(forAccount: account!, andName: jid!.stringValue, activeAndTrusted: false).isEmpty;
            if !self.encryptButton.isEnabled {
                self.encryptButton.item(at: 0)?.image = NSImage(named: NSImage.lockUnlockedTemplateName);
            } else {
                let encryption = self.chat.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!;
                let locked = encryption == ChatEncryption.omemo;
                self.encryptButton.item(at: 0)?.image = locked ? NSImage(named: NSImage.lockLockedTemplateName) : NSImage(named: NSImage.lockUnlockedTemplateName);
            }
        }
    }
    
    @IBAction func showInfoClicked(_ sender: NSButton) {
        guard let viewController = storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ContactDetailsViewController")) as? ContactDetailsViewController else {
            return;
        }
        viewController.account = self.account;
        viewController.jid = self.jid;
        
        let popover = NSPopover();
        popover.contentViewController = viewController;
        popover.behavior = .semitransient;
        popover.animates = true;
        let rect = sender.convert(sender.bounds, to: self.view.window!.contentView!);
        popover.show(relativeTo: rect, of: self.view.window!.contentView!, preferredEdge: .minY);
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
    
    let encryption: MessageEncryption;
    let encryptionFingerprint: String?;
    
    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, message: String, authorNickname: String?, authorJid: BareJID?, encryption: MessageEncryption, encryptionFingerprint: String?, preview: [String:String]? = nil) {
        self.id = id;
        self.timestamp = timestamp;
        self.account = account;
        self.message = message;
        self.jid = jid;
        self.state = state;
        self.authorNickname = authorNickname;
        self.authorJid = authorJid;
        self.preview = preview;
        self.encryption = encryption;
        self.encryptionFingerprint = encryptionFingerprint;
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
