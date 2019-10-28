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

class GroupchatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate {

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
            return self.chat as! DBChatStore.DBRoom;
        }
        set {
            self.chat = newValue;
            self.participantsContainer?.room = newValue;
        }
    }
    
    override func viewDidLoad() {
        self.dataSource = ChatViewDataSource();
        self.tableView.delegate = self;
        
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
        guard let viewController = storyboard.instantiateController(withIdentifier: "ConversationDetailsViewController") as? ConversationDetailsViewController else {
            return;
        }
        viewController.account = self.account;
        viewController.jid = self.jid;
        viewController.showSettings = true;

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
        guard let item = dataSource.getItem(at: row) as? ChatMessage else {
            guard let item = dataSource.getItem(at: row) as? SystemMessage else {
                return nil;
            }
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MucMessageSystemCellView"), owner: nil) as? ChatMessageSystemCellView {
                cell.message.stringValue = "Unread messages";
                return cell;
            }
            return nil;
        }
        let prevItem = row >= 0 && (row + 1) < dataSource.count ? dataSource.getItem(at: row + 1) : nil;
        let continuation = prevItem != nil && item.isMergeable(with: prevItem!);
        
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "MucMessageContinuationCellView" : "MucMessageCellView"), owner: nil) as? BaseChatMessageCellView {
                        
            cell.id = item.id;
            if let c = cell as? ChatMessageCellView {
                if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                    c.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                } else if let nickname = item.authorNickname, let photoHash = self.room.presences[nickname]?.presence.vcardTempPhoto {
                    c.set(avatar: AvatarManager.instance.avatar(withHash: photoHash));
                } else {
                    c.set(avatar: nil);
                }
                c.set(senderName: item.authorNickname ?? "From \(item.jid.stringValue)");
            }
            cell.set(message: item, nickname: self.room.nickname, keywords: self.keywords);
            
            return cell;
        }
        
        return nil;
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
        guard (XmppService.instance.getClient(for: account)?.state ?? .disconnected) == .connected else {
            return false;
        }
        guard room.state == .joined else {
            return false;
        }
        let message = room.createMessage(msg);
        message.oob = url;
        room.context.writer?.write(message);
        return true;
    }
    
    var lastRange = 0;

    override func textDidChange(_ obj: Notification) {
        super.textDidChange(obj);
        if lastRange < messageField.rangeForUserCompletion.length {
            self.messageField.complete(nil);
        }
        lastRange = messageField.rangeForUserCompletion.length;
    }
        
    func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        
        let tmp = textView.string;
        let start = tmp.index(tmp.startIndex, offsetBy: charRange.lowerBound);
        let end = tmp.index(tmp.startIndex, offsetBy: charRange.upperBound);
        let query = textView.string[start..<end].uppercased();
        
        print("tmp:", tmp, "start:", start, "end:", end, "query:", query);
        
        guard start != tmp.startIndex, tmp[tmp.index(before: start)] == "@" else {
            return [];
        }
        
        let suggestions = self.room?.presences.keys.filter({ (key) -> Bool in
            return key.uppercased().contains(query);
        }).sorted() ?? [];

        index?.initialize(to: suggestions.isEmpty ? -1 : 0);

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
                    if let view = self.tableView.view(atColumn: 0, row: i, makeIfNecessary: false) as? ChatMessageCellView {
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
                    if let view = self.tableView.view(atColumn: 0, row: i, makeIfNecessary: false) as? ChatMessageCellView {
                        view.set(avatar: AvatarManager.instance.avatar(withHash: avatarHash));
                    }
                }
            }
        }
    }

}

class GroupchatParticipantsContainer: NSObject, NSTableViewDelegate, NSTableViewDataSource {

    weak var tableView: NSTableView?;
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
            if let jid = participant.jid {
                view.avatar.avatar = AvatarManager.instance.avatar(for: jid.bareJid, on: room!.account);
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
