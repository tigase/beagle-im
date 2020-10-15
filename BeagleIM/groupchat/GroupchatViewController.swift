//
// GroupchatViewController.swift
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

class GroupchatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate, ConversationLogContextMenuDelegate, NSMenuItemValidation {

    @IBOutlet var avatarView: AvatarViewWithStatus!;
    @IBOutlet var titleView: NSTextField!;
    @IBOutlet var jidView: NSTextField!;
    @IBOutlet var subjectView: NSTextField!;
    
    @IBOutlet var inviteButton: NSButton!;
    @IBOutlet var participantsButton: NSButton!;
    @IBOutlet var infoButton: NSButton!;
    @IBOutlet var settingsButtin: NSPopUpButton!;
    
    @IBOutlet var sidebarWidthConstraint: NSLayoutConstraint!;
    @IBOutlet var participantsTableView: NSTableView!;
    
    fileprivate var participantsContainer: GroupchatParticipantsContainer?;
    
    private var keywords: [String]? = Settings.markKeywords.stringArrays();
    
    override var isSharingAvailable: Bool {
        return super.isSharingAvailable && room.state == .joined;
    }
    
    var room: DBChatStore.DBRoom! {
        get {
            return (self.chat as! DBChatStore.DBRoom);
        }
        set {
            self.chat = newValue;
            self.participantsContainer?.room = newValue;
        }
    }

    override func conversationTableViewDelegate() -> NSTableViewDelegate? {
        return self;
    }
    
    override func viewDidLoad() {
        self.participantsContainer = GroupchatParticipantsContainer();
        self.participantsContainer?.tableView = self.participantsTableView;
        self.participantsContainer?.room = self.room;
        self.participantsContainer?.registerNotifications();
        self.participantsTableView.delegate = participantsContainer;
        self.participantsTableView.dataSource = participantsContainer;

        super.viewDidLoad();
        
        NotificationCenter.default.addObserver(self, selector: #selector(roomStatusChanged), name: MucEventHandler.ROOM_STATUS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(roomOccupantsChanged), name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(roomStatusChanged(_:)), name: MucEventHandler.ROOM_NAME_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarForHashChanged), name: AvatarManager.AVATAR_FOR_HASH_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        sidebarWidthConstraint.constant = Settings.showRoomDetailsSidebar.bool() ? 200 : 0;
        avatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        buttonToGrayscale(button: participantsButton, template: true);
        buttonToGrayscale(button: infoButton, template: false);
        refreshRoomDetails();
    }
    
    private func buttonToGrayscale(button: NSButton, template: Bool) {
        let cgRef = button.image!.cgImage(forProposedRect: nil, context: nil, hints: nil);
        let representation = NSBitmapImageRep(cgImage: cgRef!);
        let newRep = representation.converting(to: .genericGray, renderingIntent: .default);
        let img = NSImage(cgImage: newRep!.cgImage!, size: button.frame.size);
        img.isTemplate = template;
        button.image = img;
    }
    
    @objc func avatarChanged(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
            return;
        }
        guard room.roomJid == jid && room.account == account else {
            return;
        }
        DispatchQueue.main.async {
            self.avatarView.update(for: jid, on: account, orDefault: NSImage(named: NSImage.userGroupName));
        }
    }
        
    @objc func roomStatusChanged(_ notification: Notification) {
        guard let room = notification.object as? DBChatStore.DBRoom else {
            return;
        }
        guard self.room.id == room.id else {
            return;
        }
        DispatchQueue.main.async {
            self.refreshRoomDetails();
        }
    }
    
    fileprivate func refreshRoomDetails() {
        avatarView.update(for: room.roomJid, on: room.account, orDefault: NSImage(named: NSImage.userGroupName));
        avatarView.status = room.state == .joined ? .online : (room.state == .requested ? .away : nil);
        titleView.stringValue = room.name ?? room.roomJid.localPart ?? "";
        jidView.stringValue = room.roomJid.stringValue;
        subjectView.stringValue = room.subject ?? "";
        subjectView.toolTip = room.subject;
        
        refreshPermissions();

        self.sharingButton.isEnabled = self.isSharingAvailable;
    }
    
    fileprivate func refreshPermissions() {
        let presence = self.room.presences[self.room.nickname];
        let currentRole = presence?.role ?? MucRole.none;
        let currentAffiliation = presence?.affiliation ?? MucAffiliation.none;
        
        self.settingsButtin.item(at: 2)?.isEnabled = currentRole == .participant || currentRole == .moderator;
        self.settingsButtin.item(at: 1)?.isEnabled = currentAffiliation == .admin || currentAffiliation == .owner;
        
        var anyActive = false;
        for i in 1..<self.settingsButtin.numberOfItems {
            anyActive = anyActive || (self.settingsButtin.item(at: i)?.isEnabled ?? false);
        }
        self.settingsButtin.isEnabled = anyActive;
        self.inviteButton.isEnabled = currentRole != .none;
    }
    
    @IBAction func participantsClicked(_ sender: NSButton) {
        let currWidth = self.sidebarWidthConstraint.constant;
        Settings.showRoomDetailsSidebar.set(value: currWidth == 0 ? true : false);
        NSAnimationContext.runAnimationGroup { (context) in
            context.duration = 0.25;
            context.allowsImplicitAnimation = true;
            self.sidebarWidthConstraint.animator().constant = currWidth != 0 ? 0 : 200;
        }
    }
    
    @IBAction func configureClicked(_ sender: NSMenuItem) {
        guard room.state == .joined else {
            return;
        }
        
        guard let configRoomController = storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ConfigureRoomViewController")) as? ConfigureRoomViewController else {
            return;
        }
        
        let window = NSWindow(contentViewController: configRoomController);
        configRoomController.account = room.account;
        configRoomController.mucComponent = BareJID(room.roomJid.domain);
        configRoomController.roomJid = room.roomJid;
        view.window?.beginSheet(window, completionHandler: nil);
    }
    
    @IBAction func manageMembersClicked(_ sender: NSMenuItem) {
        guard room.state == .joined else {
            return;
        }
        
        guard let affilsViewController = storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ManageAffiliationsViewController")) as? ManageAffiliationsViewController else {
            return;
        }
        
        let window = NSWindow(contentViewController: affilsViewController);
        affilsViewController.room = room;
        view.window?.beginSheet(window, completionHandler: nil);
    }
    
    @IBAction func showInfoClicked(_ sender: NSButton) {
        let storyboard = NSStoryboard(name: "ConversationDetails", bundle: nil);
        guard let viewController = storyboard.instantiateController(withIdentifier: "ContactDetailsViewController") as? ContactDetailsViewController else {
            return;
        }
        viewController.account = self.account;
        viewController.jid = self.jid;
        viewController.viewType = .groupchat;

        let popover = NSPopover();
        popover.contentViewController = viewController;
        popover.behavior = .semitransient;
        popover.animates = true;
        let rect = sender.convert(sender.bounds, to: self.view.window!.contentView!);
        popover.show(relativeTo: rect, of: self.view.window!.contentView!, preferredEdge: .minY);
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender);
        if let id = segue.identifier {
            switch id {
            case "InviteToGroupchat":
                if let controller = segue.destinationController as? InviteToGroupchatController {
                    controller.room = self.room;
                }
            default:
                break;
            }
        }
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
                cell.message.attributedString = NSAttributedString(string: "Unread messages", attributes: [.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]);
                return cell;
            }
            return nil;
        case let item as ChatMessage:
            if item.message.starts(with: "/me ") {
                if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMeSystemCellView"), owner: nil) as? ChatMeMessageCellView {
                    cell.set(item: item, nickname: item.authorNickname);
                    return cell;
                }
                return nil;
            } else {
                if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                    cell.id = item.id;
                    if cell.hasHeader {
                        if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account, let avatar = AvatarManager.instance.avatar(for: senderJid, on: item.account) {
                            cell.set(avatar: avatar);
                        } else if let nickname = item.authorNickname, let photoHash = self.room.presences[nickname]?.presence.vcardTempPhoto {
                            cell.set(avatar: AvatarManager.instance.avatar(withHash: photoHash));
                        } else {
                            cell.set(avatar: nil);
                        }
                        
                        let sender = item.authorNickname ?? "From \(item.jid.stringValue)";
                        if let author = item.authorNickname, let recipient = item.recipientNickname {
                            let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(author) " : "To \(recipient)  ");
                            let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: cell.senderName!.font!.pointSize - 2), toHaveTrait: [.italicFontMask, .smallCapsFontMask, .unboldFontMask]);
                            val.append(NSAttributedString(string: " (private message)", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]));

                            cell.set(senderName: sender, attributedSenderName: val);
                        } else {
                            cell.set(senderName: sender);
                        }
                    }
                    cell.set(message: item, nickname: room.nickname, keywords: keywords);

                    return cell;
                }
                return nil;
            }
        case let item as ChatAttachment:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatAttachmentContinuationCellView" : "ChatAttachmentCellView"), owner: nil) as? ChatAttachmentCellView {
                if cell.hasHeader {
                    if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account, let avatar = AvatarManager.instance.avatar(for: senderJid, on: item.account) {
                        cell.set(avatar: avatar);
                    } else if let nickname = item.authorNickname, let photoHash = self.room.presences[nickname]?.presence.vcardTempPhoto {
                        cell.set(avatar: AvatarManager.instance.avatar(withHash: photoHash));
                    } else {
                        cell.set(avatar: nil);
                    }
                    let sender = item.authorNickname ?? "From \(item.jid.stringValue)";
                    if let author = item.authorNickname, let recipient = item.recipientNickname {
                        let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(author) " : "To \(recipient)  ");
                        let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: cell.senderName!.font!.pointSize - 2), toHaveTrait: [.italicFontMask, .smallCapsFontMask, .unboldFontMask]);
                        val.append(NSAttributedString(string: " (private message)", attributes: [.font: font]));

                        cell.set(senderName: sender, attributedSenderName: val);
                    } else {
                        cell.set(senderName: sender);
                    }
                }
                cell.set(item: item);
                return cell;
            }
            return nil;
        case let item as ChatLinkPreview:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatLinkPreviewCellView"), owner: nil) as? ChatLinkPreviewCellView {
                cell.set(item: item, fetchPreviewIfNeeded: true);
                return cell;
            }
            return nil;
        case let item as ChatInvitation:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatInvitationCellView"), owner: nil) as? ChatInvitationCellView {
                if cell.hasHeader {
                    if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account, let avatar = AvatarManager.instance.avatar(for: senderJid, on: item.account) {
                        cell.set(avatar: avatar);
                    } else if let nickname = item.authorNickname, let photoHash = self.room.presences[nickname]?.presence.vcardTempPhoto {
                        cell.set(avatar: AvatarManager.instance.avatar(withHash: photoHash));
                    } else {
                        cell.set(avatar: nil);
                    }
                    
                    let sender = item.authorNickname ?? "From \(item.jid.stringValue)";
                    if let author = item.authorNickname, let recipient = item.recipientNickname {
                        let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(author) " : "To \(recipient)  ");
                        let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: cell.senderName!.font!.pointSize - 2), toHaveTrait: [.italicFontMask, .smallCapsFontMask, .unboldFontMask]);
                        val.append(NSAttributedString(string: " (private message)", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]));

                        cell.set(senderName: sender, attributedSenderName: val);
                    } else {
                        cell.set(senderName: sender);
                    }
                }
                cell.set(invitation: item);
                return cell;
            }
            return nil;
        default:
            return nil;
        }
    }
    
//    @IBAction func enterInInputTextField(_ sender: NSTextField) {
//        let msg = sender.stringValue
//        guard !msg.isEmpty else {
//            return;
//        }
//        
//        guard send(message: msg, correctedMessageOriginId: self.correctedMessageOriginId) else {
//            return;
//        }
//        
//        (sender as? AutoresizingTextField)?.reset();
//    }
    override func prepareConversationLogContextMenu(dataSource: ChatViewDataSource, menu: NSMenu, forRow row: Int) {
        super.prepareConversationLogContextMenu(dataSource: dataSource, menu: menu, forRow: row);
        if let item = dataSource.getItem(at: row), item.state.direction == .outgoing && (item is ChatMessage || item is ChatAttachment) {
            if item.state.isError {
            } else {
                if item is ChatMessage, !dataSource.isAnyMatching({ $0.state.direction == .outgoing && $0 is ChatMessage }, in: 0..<row) {
                    let correct = menu.addItem(withTitle: "Correct message", action: #selector(correctMessage), keyEquivalent: "");
                    correct.target = self;
                    correct.tag = item.id;
                }
                
                if (chat as? Room)?.state ?? .not_joined == .joined {
                    let retract = menu.addItem(withTitle: "Retract message", action: #selector(retractMessage), keyEquivalent: "");
                    retract.target = self;
                    retract.tag = item.id;
                }

            }
        }
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(correctLastMessage(_:)):
            return messageField.string.isEmpty;
        default:
            return true;
        }
    }
    
    @IBAction func correctLastMessage(_ sender: AnyObject) {
        for i in 0..<dataSource.count {
            if let item = dataSource.getItem(at: i) as? ChatMessage, item.state.direction == .outgoing {
                DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
                    self?.startMessageCorrection(message: item.message, originId: originId);
                })
                return;
            }
        }
    }
    
    @objc func correctMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
     
        guard let item = dataSource.getItem(withId: tag) as? ChatMessage else {
            return;
        }
        
        DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
            self?.startMessageCorrection(message: item.message, originId: originId);
        })
    }
    
    @objc func retractMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
        
        guard let item = dataSource.getItem(withId: tag) as? ChatEntry, let chat = self.chat as? Room else {
            return;
        }
        
        let alert = NSAlert();
        alert.messageText = "Are you sure you want to retract that message?"
        alert.informativeText = "That message will be removed immediately and it's receives will be asked to remove it as well.";
        alert.addButton(withTitle: "Retract");
        alert.addButton(withTitle: "Cancel");
        alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
            switch result {
            case .alertFirstButtonReturn:
                DBChatHistoryStore.instance.originId(for: item.account, with: item.jid, id: item.id, completionHandler: { [weak self] originId in
                    let message = chat.createMessageRetraction(forMessageWithId: originId);
                    message.id = UUID().uuidString;
                    message.originId = message.id;
                    guard let client = XmppService.instance.getClient(for: item.account), client.state == .connected else {
                        return;
                    }
                    client.context.writer?.write(message);
                    DBChatHistoryStore.instance.retractMessage(for: item.account, with: item.jid, stanzaId: originId, authorNickname: item.authorNickname, participantId: item.participantId, retractionStanzaId: message.id, retractionTimestamp: Date(), serverMsgId: nil, remoteMsgId: nil);
                })
            default:
                break;
            }
        })
    }
    
    override func send(message: String, correctedMessageOriginId: String?) -> Bool {
        guard (XmppService.instance.getClient(for: account)?.state ?? .disconnected) == .connected else {
            return false;
        }
        guard room.state == .joined else {
            return false;
        }
        let message = room.createMessage(message);
        if let id = message.id, UUID(uuidString: id) != nil {
            message.originId = id;
        }
        if correctedMessageOriginId != nil {
            message.lastMessageCorrectionId = correctedMessageOriginId;
        }
        room.context.writer?.write(message);
        return true;
    }
    
    override func sendAttachment(originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?) -> Bool {
        guard (XmppService.instance.getClient(for: account)?.state ?? .disconnected) == .connected else {
            return false;
        }
        guard room.state == .joined else {
            return false;
        }
        let message = room.createMessage(uploadedUrl.absoluteString);
        if let id = message.id, UUID(uuidString: id) != nil {
            message.originId = id;
        }
        message.oob = uploadedUrl.absoluteString;
        room.context.writer?.write(message);
        return true;
    }
        
    private var skipNextSuggestion = false;
    private var forceSuggestion = false;

    override func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            self.skipNextSuggestion = true;
            return false;
            //return super.textView(textView, doCommandBy: commandSelector);
        case #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteBackward(_:)):
            self.skipNextSuggestion = true;
            return super.textView(textView, doCommandBy: commandSelector);
        default:
            return super.textView(textView, doCommandBy: commandSelector);
        }
    }
        
    override func textDidChange(_ obj: Notification) {
        super.textDidChange(obj);
        if !skipNextSuggestion {
            self.messageField.complete(nil);
        } else {
            skipNextSuggestion = false;
        }
    }
        
    func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        guard charRange.length != 0 && charRange.location != NSNotFound else {
            return [];
        }
        
        let tmp = textView.string;
        let utf16 = tmp.utf16;
        let start = utf16.index(utf16.startIndex, offsetBy: charRange.lowerBound);
        let end = utf16.index(utf16.startIndex, offsetBy: charRange.upperBound);
        guard let query = String(utf16[start..<end])?.uppercased() else {
            return [];
        }
                
        let occupantNicknames:[String] = self.room?.presences.keys.map({ $0 }) ?? [];
        let suggestions = occupantNicknames.filter({ (key) -> Bool in
            return key.uppercased().starts(with: query);
        }).sorted();

        index?.initialize(to: -1);//suggestions.isEmpty ? -1 : 0);

        return suggestions.map({ name in "\(name) "});
    }
    
    @objc func avatarForHashChanged(_ notification: Notification) {
        guard let avatarHash = notification.object as? String else {
            return;
        }
        
        guard let occupant = room.presences.values.first(where: { (occupant) -> Bool in
            guard let hash = occupant.presence.vcardTempPhoto else {
                return false;
            }
            return hash == avatarHash;
        }) else {
            return;
        }
        
        let nickname = occupant.nickname;
        DispatchQueue.main.async {
            for i in 0..<self.dataSource.count {
                if let item = self.dataSource.getItem(at: i) as? ChatMessage, item.authorNickname != nil && item.authorNickname! == nickname {
                    if let view = self.conversationLogController?.tableView.view(atColumn: 0, row: i, makeIfNecessary: false) as? ChatMessageCellView {
                        view.set(avatar: AvatarManager.instance.avatar(withHash: avatarHash));
                    }
                }
            }
        }
    }
    
    @objc func roomOccupantsChanged(_ notification: Notification) {
        guard let e = notification.object as? MucModule.AbstractOccupantEvent else {
            return;
        }
        
        guard let room = e.room as? DBChatStore.DBRoom, self.room.id == room.id else {
            return;
        }
        
        if (e.nickname ?? "") == self.room.nickname && e is MucModule.OccupantChangedPresenceEvent {
            DispatchQueue.main.async {
                self.refreshPermissions();
            }
        }

        guard let avatarHash = e.occupant.presence.vcardTempPhoto else {
            return;
        }
        DispatchQueue.main.async {
            for i in 0..<self.dataSource.count {
                if let item = self.dataSource.getItem(at: i) as? ChatMessage, item.authorNickname != nil && item.authorNickname! == e.occupant.nickname {
                    if let view = self.conversationLogController?.tableView.view(atColumn: 0, row: i, makeIfNecessary: false) as? ChatMessageCellView {
                        view.set(avatar: AvatarManager.instance.avatar(withHash: avatarHash));
                    }
                }
            }
        }
    }

}

class GroupchatParticipantsContainer: NSObject, NSTableViewDelegate, NSTableViewDataSource {

    weak var tableView: NSTableView? {
        didSet {
            tableView?.menu = self.prepareContextMenu();
            tableView?.menu?.delegate = self;
        }
    }
    var room: DBChatStore.DBRoom? {
        didSet {
            self.participants.removeAll();
            room?.presences.values.forEach { occupant in
                self.participants.append(occupant);
            }
            self.participants.sort(by: { (i1, i2) -> Bool in
                return i1.nickname.caseInsensitiveCompare(i2.nickname) == .orderedAscending;
            });
            tableView?.reloadData();
        }
    }
    var participants: [MucOccupant] = [];
    
    func registerNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(roomStatusChanged), name: MucEventHandler.ROOM_STATUS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(occupantsChanged), name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarForHashChanged), name: AvatarManager.AVATAR_FOR_HASH_CHANGED, object: nil);
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return participants.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let participant = participants[row];
        if let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("GroupchatParticipantCellView"), owner: self) as? GroupchatParticipantCellView {
            
            let name = participant.nickname + "" + roleToEmoji(participant.role);
            
            view.avatar.name = name;
            if let jid = participant.jid, let avatar = AvatarManager.instance.avatar(for: jid.bareJid, on: room!.account) {
                view.avatar.avatar = avatar;
            } else {
                if let photoHash = participant.presence.vcardTempPhoto {
                    view.avatar.avatar = AvatarManager.instance.avatar(withHash: photoHash);
                } else {
                    view.avatar.avatar = nil;
                }
            }
            view.avatar.backgroundColor = NSColor(named: "chatBackgroundColor")!;
            view.avatar.status = participant.presence.show;
            view.label.stringValue = name;
            
            return view;
        }
        return nil;
    }
    
    fileprivate func roleToEmoji(_ role: MucRole) -> String {
        switch role {
        case .none, .visitor:
            return "";
        case .participant:
            return "⭐";
        case .moderator:
            return "🌟";
        }
    }
    
    @objc func occupantsChanged(_ notification: Notification) {
        guard let event = notification.object as? MucModule.AbstractOccupantEvent else {
            return;
        }
        guard let room = self.room, (event.room as? DBChatProtocol)?.id == room.id else {
            return;
        }
        
        switch event {
        case let e as MucModule.OccupantComesEvent:
            DispatchQueue.main.async {
                var tmp = self.participants;
                if let idx = tmp.firstIndex(where: { (i) -> Bool in
                    i.nickname == e.occupant.nickname;
                }) {
                    tmp[idx] = e.occupant;
                    self.participants = tmp;
                    self.tableView?.reloadData(forRowIndexes: IndexSet(integer: idx), columnIndexes: IndexSet(integer: 0));
                } else {
                    tmp.append(e.occupant);
                    tmp.sort(by: { (i1, i2) -> Bool in
                        return i1.nickname.caseInsensitiveCompare(i2.nickname) == .orderedAscending;
                    })
                    guard let idx = tmp.firstIndex(where: { (i) -> Bool in
                        i.nickname == e.occupant.nickname;
                    }) else {
                        return;
                    }
                    self.participants = tmp;
                    self.tableView?.insertRows(at: IndexSet(integer: idx), withAnimation: .slideLeft);
                }
            }
        case let e as MucModule.OccupantLeavedEvent:
            DispatchQueue.main.async {
                var tmp = self.participants;
                guard let idx = tmp.firstIndex(where: { (i) -> Bool in
                    i.nickname == e.occupant.nickname;
                }) else {
                    return;
                }
                tmp.remove(at: idx);
                self.participants = tmp;
                self.tableView?.removeRows(at: IndexSet(integer: idx), withAnimation: .slideRight);
            }
        case let e as MucModule.OccupantChangedPresenceEvent:
            DispatchQueue.main.async {
                var tmp = self.participants;
                guard let idx = tmp.firstIndex(where: { (i) -> Bool in
                    i.nickname == e.occupant.nickname;
                }) else {
                    return;
                }
                tmp[idx] = e.occupant;
                self.participants = tmp;
                self.tableView?.reloadData(forRowIndexes: IndexSet(integer: idx), columnIndexes: IndexSet(integer: 0));
            }
        case let e as MucModule.OccupantChangedNickEvent:
            DispatchQueue.main.async {
                var tmp = self.participants;
                guard let oldIdx = tmp.firstIndex(where: { (i) -> Bool in
                    i.nickname == e.nickname;
                }) else {
                    return;
                }
                tmp.remove(at: oldIdx);
                tmp.append(e.occupant);
                tmp.sort(by: { (i1, i2) -> Bool in
                    return i1.nickname.caseInsensitiveCompare(i2.nickname) == .orderedAscending;
                })
                guard let newIdx = tmp.firstIndex(where: { (i) -> Bool in
                    i.nickname == e.occupant.nickname;
                }) else {
                    return;
                }
                
                self.participants = tmp;
                self.tableView?.moveRow(at: oldIdx, to: newIdx);
                self.tableView?.reloadData(forRowIndexes: IndexSet(integer: newIdx), columnIndexes: IndexSet(integer: 0));
            }
        default:
            break;
        }
    }
    
    @objc func roomStatusChanged(_ notification: Notification) {
        guard let room = notification.object as? DBChatStore.DBRoom, (self.room?.id ?? 0) == room.id else {
            return;
        }
        
        if room.state != .joined {
            DispatchQueue.main.async {
                self.participants.removeAll();
                self.tableView?.reloadData();
            }
        }
    }
    
    @objc func avatarForHashChanged(_ notification: Notification) {
        guard let hash = notification.object as? String else {
            return;
        }
        DispatchQueue.main.async {
            for (idx, participant) in self.participants.enumerated() {
                if let photoHash = participant.presence.vcardTempPhoto, photoHash == hash {
                    self.tableView?.reloadData(forRowIndexes: IndexSet(integer: idx), columnIndexes: IndexSet(integer: 0));
                    return;
                }
            }
        }
    }
}

class GroupchatParticipantCellView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarViewWithStatus!;
    @IBOutlet var label: NSTextField!;
    
}

class SettingsPopUpButton: NSPopUpButton {
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect);
     
        NSGraphicsContext.saveGraphicsState();
        
        NSGraphicsContext.restoreGraphicsState();
    }
    
}

extension GroupchatParticipantsContainer: NSMenuDelegate {
    
    func prepareContextMenu() -> NSMenu {
        let menu = NSMenu();
        menu.autoenablesItems = true;
        menu.addItem(MenuItemWithOccupant(title: "Private message", action: #selector(privateMessage(_:)), keyEquivalent: ""));
        menu.addItem(MenuItemWithOccupant(title: "Ban user", action: #selector(banUser(_:)), keyEquivalent: ""));
        return menu;
    }
    
    func numberOfItems(in menu: NSMenu) -> Int {
        return menu.items.count;
    }
 
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool {
        guard let clickedRow = self.tableView?.clickedRow, clickedRow >= 0 && clickedRow < self.participants.count, let nickname = self.room?.nickname else {
            item.isHidden = true;
            return true;
        }
                
        let participant = self.participants[clickedRow];
        switch item.action {
        case #selector(privateMessage(_:)):
            break;
        case #selector(banUser(_:)):
            guard let affiliation = self.room?.presences[nickname]?.affiliation, (affiliation == .admin || affiliation == .owner) else {
                item.isHidden = true;
                return true;
            }
            guard participant.jid != nil else {
                item.isHidden = true;
                return true;
            }
        default:
            break;
        }
         
        item.isHidden = false;
        item.isEnabled = true;
        item.target = self;
        (item as? MenuItemWithOccupant)?.occupant = participant;
        
        return true;
    }
    
    @objc func banUser(_ menuItem: NSMenuItem?) {
        guard let participant = (menuItem as? MenuItemWithOccupant)?.occupant, let jid = participant.jid, let room = self.room, let mucModule: MucModule = XmppService.instance.getClient(for: room.account)?.modulesManager.getModule(MucModule.ID) else {
            return;
        }
        
        guard let window = self.tableView?.window else {
            return;
        }
        
        let alert = NSAlert();
        alert.icon = NSImage(named: NSImage.cautionName);
        alert.messageText = "Do you wish to ban user \(participant.nickname)?";
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")
        alert.beginSheetModal(for: window, completionHandler: { response in
            switch response {
            case .alertFirstButtonReturn:
                // we need to ban the user
                print("We need to ban user with jid: \(jid)");
                mucModule.setRoomAffiliations(to: room, changedAffiliations: [MucModule.RoomAffiliation(jid: jid.withoutResource, affiliation: .outcast)], completionHandler: { error in
                    guard let err = error else {
                        return;
                    }
                    DispatchQueue.main.async {
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.messageText = "Banning user \(participant.nickname) failed";
                        alert.informativeText = "Server returned an error: \(err.rawValue)";
                        alert.addButton(withTitle: "OK");
                        alert.beginSheetModal(for: window, completionHandler: { response in
                            //we do not care about the response
                        })
                    }
                })
                break;
            default:
                // action was cancelled
                break;
            }
        })
    }
    
    @objc func privateMessage(_ menuItem: NSMenuItem) {
        guard let participant = (menuItem as? MenuItemWithOccupant)?.occupant, let room = self.room else {
            return;
        }
        
        guard let window = self.tableView?.window else {
            return;
        }
        
        let alert = NSAlert();
        alert.icon = NSImage(named: NSImage.infoName);
        alert.messageText = "Enter message to send to \(participant.nickname):";
        let text = NSTextView(frame: NSRect(origin: .zero, size: CGSize(width: 300, height: 100)));
        text.isEditable = true;
        alert.accessoryView = text;
        alert.addButton(withTitle: "Send");
        alert.addButton(withTitle: "Cancel");
        alert.beginSheetModal(for: window, completionHandler: { result in
            switch result {
            case .alertFirstButtonReturn:
                MucEventHandler.instance.sendPrivateMessage(room: room, recipientNickname: participant.nickname, body: text.string);
            default:
                break;
            }
        })
    }
    
    
    class MenuItemWithOccupant: NSMenuItem {
        
        weak var occupant: MucOccupant?;
        
    }
}
