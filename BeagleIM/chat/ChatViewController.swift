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

class ChatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate, ConversationLogContextMenuDelegate {

    @IBOutlet var buddyAvatarView: AvatarViewWithStatus!
    @IBOutlet var buddyNameLabel: NSTextFieldCell!
    @IBOutlet var buddyJidLabel: NSTextFieldCell!
    @IBOutlet var buddyStatusLabel: NSTextField!;

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
                if let rosterItem = RosterModule.getRosterStore(sessionObject).get(for: JID(jid)) {
                    buddyName = rosterItem.name ?? jid.stringValue;
                    fetchPreviewIfNeeded = true;
                } else {
                    buddyName = jid.stringValue;
                }
            } else {
                buddyName = jid.stringValue;
            }
        }
    };
    fileprivate var buddyName: String! = "";
    private var fetchPreviewIfNeeded: Bool = false;

    override func conversationTableViewDelegate() -> NSTableViewDelegate? {
        return self;
    }
    
    override func viewDidLoad() {
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
        let status = presenceModule?.presenceStore.getBestPresence(for: jid)?.status;
        buddyStatusLabel.stringValue = status ?? "";
        buddyStatusLabel.toolTip = status;

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
        guard let item = dataSource.getItem(at: row) else {
            return nil;
        }
        
        let prevItem = row >= 0 && (row + 1) < dataSource.count ? dataSource.getItem(at: row + 1) : nil;
        let continuation = prevItem != nil && item.isMergeable(with: prevItem!);

        switch item {
        case is SystemMessage:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageSystemCellView"), owner: nil) as? ChatMessageSystemCellView {
                cell.message.stringValue = "Unread messages";
                return cell;
            }
            return nil;
        case let item as ChatMessage:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                cell.id = item.id;
                if cell.hasHeader {
                    let senderJid = item.state.direction == .incoming ? item.jid : item.account;
                    cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                    cell.set(senderName: item.state.direction == .incoming ? buddyName : "Me");
                }
                cell.set(message: item);

                return cell;
            }
            return nil;
        case let item as ChatLinkPreview:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatLinkPreviewCellView"), owner: nil) as? ChatLinkPreviewCellView {
                cell.set(item: item, fetchPreviewIfNeeded: fetchPreviewIfNeeded);
                return cell;
            }
            return nil;
        case let item as ChatAttachment:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatAttachmentContinuationCellView" : "ChatAttachmentCellView"), owner: nil) as? ChatAttachmentCellView {
                if cell.hasHeader {
                    let senderJid = item.state.direction == .incoming ? item.jid : item.account;
                    cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                    cell.set(senderName: item.state.direction == .incoming ? buddyName : "Me");
                }
                cell.set(item: item);
                return cell;
            }
            return nil;
        case let item as ChatInvitation:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatInvitationCellView"), owner: nil) as? ChatInvitationCellView {
                if cell.hasHeader {
                    let senderJid = item.state.direction == .incoming ? item.jid : item.account;
                    cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                    cell.set(senderName: item.state.direction == .incoming ? buddyName : "Me");
                }
                cell.set(invitation: item);
                return cell;
            }
            return nil;
        default:
            return nil;
        }
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
            self.fetchPreviewIfNeeded = e.action != .removed;
            self.buddyNameLabel.title = self.buddyName;
            self.buddyAvatarView.name = self.buddyName;
            self.dataSource.refreshDataNoReload();
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
            self.conversationLogController?.tableView.reloadData();
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
            let status = e.presence.status;
            self.buddyStatusLabel.stringValue = status ?? "";
            self.buddyStatusLabel.toolTip = status;
        }

        self.updateCapabilities();
    }

    func prepareConversationLogContextMenu(dataSource: ChatViewDataSource, menu: NSMenu, forRow row: Int) {
        if let item = dataSource.getItem(at: row) as? ChatMessage, item.state.direction == .outgoing && item.state.isError {
            let resend = menu.addItem(withTitle: "Resend message", action: #selector(resendMessage), keyEquivalent: "");
            resend.target = self;
            resend.tag = item.id;
        }
    }

    @objc func resendMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return;
        }

        guard let item = dataSource.getItem(withId: tag), let chat = self.chat as? DBChatStore.DBChat else {
            return;
        }

        switch item {
        case let item as ChatMessage:
            MessageEventHandler.sendMessage(chat: chat, body: item.message, url: nil);
            DBChatHistoryStore.instance.remove(item: item);
        case let item as ChatAttachment:
            let oldLocalFile = DownloadStore.instance.url(for: "\(item.id)");
            MessageEventHandler.sendAttachment(chat: chat, originalUrl: oldLocalFile, uploadedUrl: item.url, appendix: item.appendix, completionHandler: {
                DBChatHistoryStore.instance.remove(item: item);
            });
        default:
            break;
        }
    }

    override func send(message: String) -> Bool {
        guard let chat = self.chat as? DBChatStore.DBChat else {
            return false;
            
        }
        MessageEventHandler.sendMessage(chat: chat, body: message, url: nil);
        return true;
    }
    
    override func uploadFileToHttpServerWithErrorHandling(data: Data, filename: String, mimeType: String?, onSuccess: @escaping (AbstractChatViewControllerWithSharing.UploadResult) -> Void) {
        let encryption: ChatEncryption = (chat as? DBChatStore.DBChat)?.options.encryption ?? .none;
        switch encryption {
        case .none:
            super.uploadFileToHttpServerWithErrorHandling(data: data, filename: filename, mimeType: mimeType, onSuccess: onSuccess);
        case .omemo:
            let omemoModule: OMEMOModule = XmppService.instance.getClient(for: chat!.account)!.modulesManager.getModule(OMEMOModule.ID)!;
            let result = omemoModule.encryptFile(data: data);
            switch result {
            case .success(let (encryptedData, hash)):
                super.uploadFileToHttpServerWithErrorHandling(data: encryptedData, filename: filename, mimeType: mimeType, onSuccess: { uploadResult in
                    switch uploadResult {
                    case .success(let url, let filesize, let mimeType):
                        var parts = URLComponents(url: url, resolvingAgainstBaseURL: true)!;
                        parts.scheme = "aesgcm";
                        parts.fragment = hash;
                        let shareUrl = parts.url!;
                        
                        print("sending url:", shareUrl.absoluteString);
                        onSuccess(.success(url: shareUrl, filesize: filesize, mimeType: mimeType));
                    case .failure(let error, let errorMessage):
                        onSuccess(.failure(error: error, errorMessage: errorMessage));
                    }
                });
            case .failure(let err):
                onSuccess(.failure(error: err, errorMessage: nil));
            }
        }

    }
        
    override func sendAttachment(originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?) -> Bool {
        guard let chat = self.chat as? DBChatStore.DBChat else {
            return false;
        }
        
        var appendix = ChatAttachmentAppendix();
        appendix.state = .downloaded;
        appendix.filename = originalUrl.lastPathComponent;
        appendix.filesize = Int(filesize);
        appendix.mimetype = mimeType;
        MessageEventHandler.sendAttachment(chat: chat, originalUrl: originalUrl, uploadedUrl: uploadedUrl.absoluteString, appendix: appendix, completionHandler: nil);
        return false;
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

        guard let chat = self.chat as? DBChatStore.DBChat else {
            return;
        }
        chat.modifyOptions({ (options) in
            options.encryption = encryption;
        }, completionHandler: {
            DispatchQueue.main.async {
                self.refreshEncryptionStatus();
            }
        })
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
                let encryption = (self.chat as? DBChatStore.DBChat)?.options.encryption ?? ChatEncryption(rawValue: Settings.messageEncryption.string()!)!;
                let locked = encryption == ChatEncryption.omemo;
                self.encryptButton.item(at: 0)?.image = locked ? NSImage(named: NSImage.lockLockedTemplateName) : NSImage(named: NSImage.lockUnlockedTemplateName);
            }
        }
    }

    @IBAction func showInfoClicked(_ sender: NSButton) {
        let storyboard = NSStoryboard(name: "ConversationDetails", bundle: nil);
        guard let viewController = storyboard.instantiateController(withIdentifier: "ContactDetailsViewController") as? ContactDetailsViewController else {
            return;
        }
        viewController.account = self.account;
        viewController.jid = self.jid;
        viewController.viewType = .chat;

        let popover = NSPopover();
        popover.contentViewController = viewController;
        popover.behavior = .semitransient;
        popover.animates = true;
        let rect = sender.convert(sender.bounds, to: self.view.window!.contentView!);
        popover.show(relativeTo: rect, of: self.view.window!.contentView!, preferredEdge: .minY);
    }

}

enum MessageSendError: Error {
    case internalError
    case unknownError(String)

    var stanzaId: String? {
        switch self {
        case .unknownError(let stanzaId):
            return stanzaId;
        default:
            return nil;
        }
    }
}

public enum PreviewError: String, Error {
    case NoData = "no_data";
    case Error = "error";
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

    static let didScrollRowToVisible = Notification.Name("ChatViewTableView::didScrollRowToVisible");

    override open var isFlipped: Bool {
        return false;
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView);
        print("reflectScrolledClipView called!");
    }
    override func scrollRowToVisible(_ row: Int) {
        let numberOfRows = self.dataSource?.numberOfRows?(in: self) ?? 0;
        guard numberOfRows > row else {
            print("cannot scroll to row", row, "as data source has only", numberOfRows, "rows");
            return;
        }
        super.scrollRowToVisible(row);
        let visibleRows = self.rows(in: self.visibleRect);
        if !visibleRows.contains(row) {
            print("visible rows:", visibleRows, "need:", row);
            DispatchQueue.main.async {
                self.scrollRowToVisible(row);
            }
        } else {
            print("scrollRowToVisible called!");
            NotificationCenter.default.post(name: ChatViewTableView.didScrollRowToVisible, object: self);
        }
    }
}

class ChatViewStatusView: NSTextField {

}
