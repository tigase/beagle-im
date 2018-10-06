//
//  GroupchatViewController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 21.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class GroupchatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate {

    @IBOutlet var avatarView: AvatarViewWithStatus!;
    @IBOutlet var titleView: NSTextField!;
    @IBOutlet var jidView: NSTextField!;
    @IBOutlet var subjectView: NSTextField!;
    
    @IBOutlet var infoButton: NSButton!;
    @IBOutlet var settingsButtin: NSPopUpButton!;
    
    @IBOutlet var sidebarWidthConstraint: NSLayoutConstraint!;
    @IBOutlet var participantsTableView: NSTableView!;
    
    fileprivate var participantsContainer: GroupchatParticipantsContainer?;
    
    override var isSharingAvailable: Bool {
        return super.isSharingAvailable && room.state == .joined;
    }
    
    var room: DBChatStore.DBRoom! {
        get {
            return self.chat as? DBChatStore.DBRoom
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
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        sidebarWidthConstraint.constant = Settings.showRoomDetailsSidebar.bool() ? 200 : 0;
        avatarView.backgroundColor = NSColor.white;
        let cgRef = infoButton.image!.cgImage(forProposedRect: nil, context: nil, hints: nil);
        let representation = NSBitmapImageRep(cgImage: cgRef!);
        let newRep = representation.converting(to: .genericGray, renderingIntent: .default);
        infoButton.image = NSImage(cgImage: newRep!.cgImage!, size: infoButton.frame.size);
        refreshRoomDetails();
    }
    
    @objc func roomOccupantsChanged(_ notification: Notification) {
        guard let e = notification.object as? MucModule.OccupantChangedPresenceEvent else {
            return;
        }
        guard let room = e.room as? DBChatStore.DBRoom, self.room.id == room.id && (e.nickname ?? "") == self.room.nickname else {
            return;
        }
        DispatchQueue.main.async {
            self.refreshPermissions();
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
        avatarView.avatar = NSImage(named: NSImage.userGroupName);
        avatarView.status = room.state == .joined ? .online : (room.state == .requested ? .away : nil);
        titleView.stringValue = room.roomJid.localPart ?? "";
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
    }
    
    @IBAction func infoClicked(_ sender: NSButton) {
        let currWidth = self.sidebarWidthConstraint.constant;
        Settings.showRoomDetailsSidebar.set(value: currWidth == 0 ? true : false);
        self.sidebarWidthConstraint.constant = currWidth != 0 ? 0 : 200;
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
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MucMessageCellView"), owner: nil) as? ChatMessageCellView {
            
            let item = dataSource.getItem(at: row) as! ChatMessage;
            if (row == dataSource.count-1) {
                DispatchQueue.main.async {
                    self.dataSource.loadItems(before: item.id, limit: 20)
                }
            }
            
            let senderJid = item.state.direction == .incoming ? (item.authorJid ?? item.jid) : item.account;
            cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
            cell.set(senderName: item.authorNickname ?? "From \(item.jid.stringValue)");
            cell.set(message: item.message, timestamp: item.timestamp, state: item.state);
            
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
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return participants.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let participant = participants[row];
        if let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("GroupchatParticipantCellView"), owner: self) as? GroupchatParticipantCellView {
            
            view.avatar.avatar = participant.jid != nil ? AvatarManager.instance.avatar(for: participant.jid!.bareJid, on: room!.account) : NSImage(named: NSImage.userName);
            view.avatar.backgroundColor = NSColor.white;
            view.avatar.status = participant.presence.show;
            view.label.stringValue = participant.nickname + "" + roleToEmoji(participant.role);
            
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
            guard let occupant = notification.object as? MucOccupant else {
                return;
            }
            DispatchQueue.main.async {
                var tmp = self.participants;
                tmp.append(occupant);
                tmp.sort(by: { (i1, i2) -> Bool in
                    return i1.nickname.caseInsensitiveCompare(i2.nickname) == .orderedAscending;
                })
                guard let idx = tmp.firstIndex(where: { (i) -> Bool in
                    i.nickname == occupant.nickname;
                }) else {
                    return;
                }
                self.participants = tmp;
                self.tableView?.insertRows(at: IndexSet(integer: idx), withAnimation: .slideLeft);
            }
            return;
        }
        guard let room = self.room, event.room === room else {
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
                    i.nickname == e.occupant.nickname ?? "";
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
}

class GroupchatParticipantCellView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarViewWithStatus!;
    @IBOutlet var label: NSTextField!;
    
}
