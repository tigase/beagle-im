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
import Martin
import MartinOMEMO
import Combine

class GroupchatParticipantsTableView: NSOutlineView {
    
    override func prepareContent(in rect: NSRect) {
        super.prepareContent(in: self.visibleRect);
    }
    
}

class GroupchatViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate, ConversationLogContextMenuDelegate, NSMenuItemValidation {

    @IBOutlet var avatarView: AvatarViewWithStatus!;
    @IBOutlet var titleView: NSTextField!;
    @IBOutlet var jidView: NSTextField!;
    @IBOutlet var subjectView: NSTextField!;
    
    @IBOutlet var inviteButton: NSButton!;
    @IBOutlet var participantsButton: NSButton!;
    @IBOutlet var infoButton: NSButton!;
    @IBOutlet var settingsButtin: NSPopUpButton!;
    @IBOutlet var settingsButtinLeadingConstraint : NSLayoutConstraint!;
    
    @IBOutlet var sidebarWidthConstraint: NSLayoutConstraint!;
    @IBOutlet var participantsTableView: NSOutlineView!;
    
    fileprivate var participantsContainer: GroupchatParticipantsContainer?;
    
    private var pmPopupPositioningView: NSView!;
    
    private var encryptButton: DropDownButton!;
    
    private var cancellables: Set<AnyCancellable> = [];
    var room: Room! {
        get {
            return (self.conversation as! Room);
        }
    }
    
    private var role: MucRole = .none {
        didSet {
            DispatchQueue.main.async {
                self.refreshPermissions();
            }
        }
    }
    private var affiliation: MucAffiliation = .none {
        didSet {
            DispatchQueue.main.async {
                self.refreshPermissions();
            }
        }
    }
    
    override func viewDidLoad() {
        if #available(macOS 11.0, *) {
            self.participantsTableView.style = .fullWidth;
        } else {
            NSLayoutConstraint.activate([self.settingsButtin.widthAnchor.constraint(equalToConstant: 40)]);
            settingsButtinLeadingConstraint.constant = 0;
        }
        self.participantsContainer = GroupchatParticipantsContainer(delegate: self);
        self.participantsContainer?.outlineView = self.participantsTableView;
        self.participantsTableView.delegate = participantsContainer;
        self.participantsTableView.dataSource = participantsContainer;
        self.participantsContainer?.expandAll();

        self.participantsTableView.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) });
        
        super.viewDidLoad();

        self.encryptButton = createEncryptButton();
        bottomView.addView(self.encryptButton, in: .trailing)
                
        suggestionProviders.append(MucOccupantSuggestionItemView.Provider());
    }
    
    
    func createEncryptButton() -> DropDownButton {
        let buttonSize = NSFont.systemFontSize * 2;
        let encryptButton = DropDownButton();
        let menu = NSMenu(title: "");
        let unencrypedItem = NSMenuItem(title: NSLocalizedString("Unencrypted", comment: "encryption option"), action: #selector(encryptionChanged(_:)), keyEquivalent: "");
        unencrypedItem.image = NSImage(named: "lock.open.fill");//?.scaled(maxWidthOrHeight: buttonSize);
        unencrypedItem.image?.size = NSSize(width: 16, height: 16);
        menu.addItem(unencrypedItem);
        let defaultItem = NSMenuItem(title: NSLocalizedString("Default", comment: "encryption option"), action: #selector(encryptionChanged(_:)), keyEquivalent: "");
        defaultItem.image = NSImage(named: "lock.circle");//?.scaled(maxWidthOrHeight: buttonSize);
        defaultItem.image?.size = NSSize(width: 16, height: 16);
        menu.addItem(defaultItem);
        let omemoItem = NSMenuItem(title: NSLocalizedString("OMEMO", comment: "encryption option"), action: #selector(encryptionChanged(_:)), keyEquivalent: "");
        omemoItem.image = NSImage(named: "lock.fill");//?.scaled(maxWidthOrHeight: buttonSize);
        omemoItem.image?.size = NSSize(width: 16, height: 16);
        menu.addItem(omemoItem);
        encryptButton.menu = menu;
        encryptButton.bezelStyle = .regularSquare;
        NSLayoutConstraint.activate([encryptButton.widthAnchor.constraint(equalToConstant: buttonSize), encryptButton.widthAnchor.constraint(equalTo: encryptButton.heightAnchor)]);
        
        encryptButton.isBordered = false;
        encryptButton.isEnabled = false;
        encryptButton.image = NSImage(named: "lock.open.fill");

        return encryptButton;
    }
    
    override func viewWillAppear() {
        pmPopupPositioningView = NSView();
        view.addSubview(pmPopupPositioningView!, positioned: .below, relativeTo: messageFieldScroller);
        super.viewWillAppear();
        
        self.conversationLogController?.contextMenuDelegate = self;

        
        room.displayNamePublisher.assign(to: \.stringValue, on: titleView).store(in: &cancellables);
        room.displayNamePublisher.map({ $0 as String? }).assign(to: \.name, on: avatarView).store(in: &cancellables);
        avatarView.displayableId = conversation;
        room.statusPublisher.map({ $0 != nil }).assign(to: \.isEnabled, on: sharingButton).store(in: &cancellables);
        room.descriptionPublisher.map({ $0 ?? "" }).receive(on: DispatchQueue.main).assign(to: \.stringValue, on: subjectView).store(in: &cancellables);
        room.descriptionPublisher.receive(on: DispatchQueue.main).assign(to: \.toolTip, on: subjectView).store(in: &cancellables);
        room.$affiliation.receive(on: DispatchQueue.main).assign(to: \.affiliation, on: self).store(in: &cancellables);
        room.$role.receive(on: DispatchQueue.main).assign(to: \.role, on: self).store(in: &cancellables);
        room.$roomFeatures.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] _ in self?.refreshPermissions(); }).store(in: &cancellables);
        room.$features.combineLatest(Settings.$messageEncryption).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (features, defEncryption) in
            self?.refreshEncryptionStatus(features: features, defEncryption: defEncryption);
        }).store(in: &cancellables);
        jidView.stringValue = room.roomJid.stringValue;

        sidebarWidthConstraint.constant = Settings.showRoomDetailsSidebar ? 200 : 0;
        avatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        self.participantsContainer?.room = self.room;
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear();
        cancellables.removeAll();
    }
        
    @objc func encryptionChanged(_ menuItem: NSMenuItem) {
        var encryption: ChatEncryption? = nil;
        let idx = encryptButton.menu?.items.firstIndex(where: { $0.title == menuItem.title }) ?? 0;
        switch idx {
        case 0:
            encryption = ChatEncryption.none;
        case 1:
            encryption = nil;
        case 2:
            encryption = ChatEncryption.omemo;
        default:
            encryption = nil;
        }

        room.updateOptions({ (options) in
            options.encryption = encryption;
        });
        DispatchQueue.main.async {
            self.refreshEncryptionStatus(features: self.room.features, defEncryption: Settings.messageEncryption);
        }
    }
    
    private func refreshEncryptionStatus(features: [ConversationFeature], defEncryption: ConversationEncryption) {
        self.encryptButton.isEnabled = features.contains(.omemo);
        if !self.encryptButton.isEnabled {
            self.encryptButton.image = NSImage(named: "lock.open.fill");
        } else {
            let encryption = self.room.options.encryption ?? defEncryption;
            let locked = encryption == ChatEncryption.omemo;
            self.encryptButton.image = NSImage(named: locked ? "lock.fill" : "lock.open.fill");
        }
    }
    
    fileprivate func refreshPermissions() {
        let presence = self.room.occupant(nickname: self.room.nickname);
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
        Settings.showRoomDetailsSidebar = currWidth == 0 ? true : false;
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
    
    override func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int) {
        super.prepareConversationLogContextMenu(dataSource: dataSource, menu: menu, forRow: row);
        if row != NSNotFound || !(self.conversationLogController?.selectionManager.hasSingleSender ?? false) {
            if room.canSendPrivateMessage() {
                let reply = menu.addItem(withTitle: NSLocalizedString("Reply with PM", comment: "context menu item"), action: #selector(replySelectedMessagesViaPM), keyEquivalent: "");
                reply.target = self
                reply.tag = row;
                if #available(macOS 11.0, *) {
                    reply.image = NSImage(systemSymbolName: "arrowshape.turn.up.left.circle", accessibilityDescription: "reply with PM");
                }
            }
        }
        if let item = dataSource.getItem(at: row), item.state.direction == .outgoing {
            switch item.payload {
            case .message(_, _), .attachment(_, _):
                if item.state.isError {
                } else {
                    if item.isMessage(), !dataSource.isAnyMatching({ $0.state.direction == .outgoing && $0.isMessage() }, in: 0..<row) {
                        let correct = menu.addItem(withTitle: NSLocalizedString("Correct message", comment: "context menu item"), action: #selector(correctMessage), keyEquivalent: "");
                        correct.target = self;
                        correct.tag = item.id;
                        if #available(macOS 11.0, *) {
                            correct.image = NSImage(systemSymbolName: "pencil.circle", accessibilityDescription: "correct")
                        }
                    }
                
                    if room.state == .joined {
                        let retract = menu.addItem(withTitle: NSLocalizedString("Retract message", comment: "context menu item"), action: #selector(retractMessage), keyEquivalent: "");
                        retract.target = self;
                        retract.tag = item.id;
                        if #available(macOS 11.0, *) {
                            retract.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "retract")
                        }
                    }
                }
            case .location(_):
                if item.state.isError {
                } else {
                    let showMap = menu.insertItem(withTitle: NSLocalizedString("Show map", comment: "context menu item"), action: #selector(showMap), keyEquivalent: "", at: 0);
                    showMap.target = self;
                    showMap.tag = item.id;
                    if #available(macOS 11.0, *) {
                        showMap.image = NSImage(systemSymbolName: "map", accessibilityDescription: "show map")
                    }
                    if room.state == .joined {
                        let retract = menu.addItem(withTitle: NSLocalizedString("Retract message", comment: "context menu item"), action: #selector(retractMessage), keyEquivalent: "");
                        retract.target = self;
                        retract.tag = item.id;
                        if #available(macOS 11.0, *) {
                            retract.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "retract")
                        }
                    }
                }
            default:
                break;
            }
        }
    }
    
    @objc func replySelectedMessagesViaPM(_ sender: NSMenuItem) {
        guard let selection = self.conversationLogController?.selectionManager.selection else {
            return;
        }
        
        guard let nickname = selection.items.first?.entry.sender.nickname, let occupant = room.occupant(nickname: nickname) else {
            return;
        }
        let texts = selection.selectedTexts;
        
        // need to insert "> " on any "\n"
        let text: String = prepareReply(from: texts);
        
        showSendPMPopover(for: occupant, withText: text);
    }
    
    func showSendPMPopover(for occupant: MucOccupant, withText: String?) {
        pmPopupPositioningView?.frame = NSRect(origin: NSPoint(x: self.messageFieldScroller.frame.origin.x + self.messageFieldScroller.contentInsets.left, y: 0), size: NSSize(width: self.messageField.frame.size.width, height: 1));
        
        let text = withText != nil ? "\(withText!)\n" : "";
        
        let popover = GroupchatPMPopover(room: room, occupant: occupant, text: text, size: self.messageField.visibleRect.size);
        popover.show(relativeTo: .zero, of: self.pmPopupPositioningView!, preferredEdge: .maxY);
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
            if let item = dataSource.getItem(at: i), item.state.direction == .outgoing, case .message(let message, _) = item.payload {
                DBChatHistoryStore.instance.originId(for: self.conversation, id: item.id, completionHandler: { [weak self] originId in
                    self?.startMessageCorrection(message: message, originId: originId);
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
     
        guard let item = dataSource.getItem(withId: tag), case .message(let message, _) = item.payload else {
            return;
        }
        
        DBChatHistoryStore.instance.originId(for: self.conversation, id: item.id, completionHandler: { [weak self] originId in
            self?.startMessageCorrection(message: message, originId: originId);
        })
    }
    
    @objc func retractMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
        
        guard let item = dataSource.getItem(withId: tag), item.sender != .none, let chat = self.conversation as? Room else {
            return;
        }
        
        let alert = NSAlert();
        alert.messageText = NSLocalizedString("Are you sure you want to retract that message?", comment: "alert window title")
        alert.informativeText = NSLocalizedString("That message will be removed immediately and it's receives will be asked to remove it as well.", comment: "alert window message");
        alert.addButton(withTitle: NSLocalizedString("Retract", comment: "Button"));
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
            switch result {
            case .alertFirstButtonReturn:
                chat.retract(entry: item);
            default:
                break;
            }
        })
    }
    
    override func send(message: String, correctedMessageOriginId: String?) -> Bool {
        guard (room.context?.isConnected ?? false) && room.state == .joined else {
            return false;
        }
        
        room.sendMessage(text: message, correctedMessageOriginId: correctedMessageOriginId);
        return true;
    }
        
    override func textDidChange(_ obj: Notification) {
        super.textDidChange(obj);
    }
    
    override func prepareCompletions(for query: String) -> [Any] {
        guard query.first == "@" else {
            return super.prepareCompletions(for: query);
        }
        
        let prefix = query.dropFirst().uppercased();
        guard !prefix.isEmpty else {
            return [];
        }
        return self.room.occupants.filter({ $0.nickname.uppercased().starts(with: prefix) }).sorted(by: { p1, p2 -> Bool in p1.nickname < p2.nickname });
    }
    
    override func suggestionSelected(item: Any, range: NSRange) {
        switch item {
        case let occupant as MucOccupant:
            self.messageField.replaceCharacters(in: range, with: "@\(occupant.nickname) ");
        default:
            super.suggestionSelected(item: item, range: range);
        }
    }

}

class GroupchatParticipantsContainer: NSObject, NSOutlineViewDelegate, NSOutlineViewDataSource {

    private class ParticipantsGroup: Equatable, Hashable {
        static func == (lhs: ParticipantsGroup, rhs: ParticipantsGroup) -> Bool {
            return lhs.role == rhs.role;
        }
        
        let role: MucRole;
        var participants: [MucOccupant];
        
        func hash(into hasher: inout Hasher) {
            hasher.combine(role);
        }
        
        @available(macOS 11.0, *)
        var image: NSImage? {
            switch role {
            case .moderator:
                return NSImage(systemSymbolName: "rosette", accessibilityDescription: nil);
            case .participant:
                return NSImage(systemSymbolName: "person.3", accessibilityDescription: nil);
            case .visitor:
                return NSImage(systemSymbolName: "theatermasks", accessibilityDescription: nil);
            case .none:
                return nil;
            }
        }
        
        var label: String {
            switch role {
            case .moderator:
                return NSLocalizedString("Moderators", comment: "list of users with this role");
            case .participant:
                return NSLocalizedString("Participants", comment: "list of users with this role");
            case .visitor:
                return NSLocalizedString("Visitors", comment: "list of users with this role");
            case .none:
                return NSLocalizedString("None", comment: "list of users with this role");
            }
        }
        
        var labelAttributedString: NSAttributedString {
            if #available(macOS 11.0, *) {
                let text = NSMutableAttributedString(string: "");
                if let image = self.image {
                    let att = NSTextAttachment();
                    att.image = image;
                    text.append(NSAttributedString(attachment: att));
                }
                text.append(NSAttributedString(string: self.label.uppercased()));
                return text;
            } else {
                return NSAttributedString(string: self.label);
            }
        }
        
        init(role: MucRole, participants: [MucOccupant] = []) {
            self.role = role;
            self.participants = participants;
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    
    weak var outlineView: NSOutlineView? {
        didSet {
            outlineView?.menu = self.prepareContextMenu();
            outlineView?.menu?.delegate = self;
        }
    }
    var room: Room? {
        didSet {
            cancellables.removeAll();
            self.outlineView?.isHidden = true;
            room?.occupantsPublisher.throttle(for: 0.1, scheduler: self.dispatcher.queue, latest: true).sink(receiveValue:{ [weak self] value in
                    self?.update(participants: value);
            }).store(in: &cancellables);
        }
    }

    private let allGroups: [MucRole: ParticipantsGroup] = [
        .moderator: ParticipantsGroup(role: .moderator),
        .participant: ParticipantsGroup(role: .participant),
        .visitor: ParticipantsGroup(role: .visitor)
    ];
    private var groups: [ParticipantsGroup] = [
    ];
    
    weak var delegate: GroupchatViewController?;
    
    private var dispatcher = QueueDispatcher(label: "GroupchatParticipantsContainer");
    
    private var initialized = false;
    
    init(delegate: GroupchatViewController) {
        self.delegate = delegate;
        super.init();
    }
    
    private let allRoles: [MucRole] = [.moderator, .participant, .visitor];
    
    private enum GroupChanges {
        case groupAdded(role: MucRole)
        case groupRemoved(role: MucRole)
        case groupModified(role: MucRole, changes: Array<MucOccupant>.IndexSetChanges)
    }
    
    private func update(participants: [MucOccupant]) {
        let oldGroups = self.groups;
        let newGroups = allRoles.map({ role in ParticipantsGroup(role: role, participants: participants.filter({ $0.role == role }).sorted(by: { (i1,i2) -> Bool in i1.nickname.lowercased() < i2.nickname.lowercased() })) }).filter({ !$0.participants.isEmpty });

        let allChanges = newGroups.calculateChanges(from: oldGroups);
//
        let allChanges2 = newGroups.compactMap({ newGroup -> (ParticipantsGroup,ParticipantsGroup)? in
            guard let oldGroup = oldGroups.first(where: { $0.role == newGroup.role }) else {
                return nil;
            }
            return (oldGroup, newGroup);
        }).map({ (old, new) in
            return (old, new.participants.calculateChanges(from: old.participants));
        })
        
        DispatchQueue.main.sync {
            //self.groups = newGroups;

            self.groups = newGroups.map({ newGroup in
                let group = allGroups[newGroup.role]!;
                group.participants = newGroup.participants;
                return group;
            })
            
            self.outlineView?.beginUpdates();

            if (!initialized) {
                initialized = true;
                outlineView?.reloadData();
                outlineView?.expandItem(nil, expandChildren: true);
                //self.expandAll();
            } else {
                if !allChanges.removed.isEmpty {
                    outlineView?.removeItems(at: allChanges.removed, inParent: nil, withAnimation: .effectFade);
                }
                if !allChanges.inserted.isEmpty {
                    outlineView?.insertItems(at: allChanges.inserted, inParent: nil, withAnimation: .effectFade);
                    for idx in allChanges.inserted {
                        outlineView?.expandItem(groups[idx], expandChildren: true);
                    }
                }
                
                for (group, changes) in allChanges2 {
                    self.outlineView?.removeItems(at: changes.removed, inParent: group, withAnimation: .effectFade);
                    self.outlineView?.insertItems(at: changes.inserted, inParent: group, withAnimation: .effectFade);
                }
            }
            self.outlineView?.endUpdates();
            self.outlineView?.isHidden = false;
        }
    }
    
    func expandAll() {
        for group in groups {
            self.outlineView?.expandItem(group, expandChildren: true);
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        return item is ParticipantsGroup;
    }

    func outlineView(_ outlineView: NSOutlineView, shouldExpandItem item: Any) -> Bool {
        return item is ParticipantsGroup;
    }
        
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? ParticipantsGroup {
            return group.participants[index];
        } else {
            return groups[index];
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let group = item as? ParticipantsGroup {
            return group.participants.count;
        } else {
            return groups.count;
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch item {
        case let participant as MucOccupant:
            guard let view = outlineView.makeView(withIdentifier:NSUserInterfaceItemIdentifier("GroupchatParticipantCellView"), owner: nil) as? GroupchatParticipantCellView else{
                return nil;
            }
            
            view.set(occupant: participant, in: room!);
            view.identifier = NSUserInterfaceItemIdentifier("GroupchatParticipantCellView")
                    
            return view;
        case let group as ParticipantsGroup:
            guard let view = outlineView.makeView(withIdentifier:NSUserInterfaceItemIdentifier("GroupchatGroupCellView"), owner: nil) as? GroupchatGroupCellView else{
                return nil;
            }
            view.label.attributedStringValue = group.labelAttributedString;
//            view.image.image = group.image;
            return view;
        default:
            return nil;
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, shouldShowOutlineCellForItem item: Any) -> Bool {
        return false;
    }
}

class GroupchatGroupCellView: NSTableCellView {
 
    @IBOutlet var label: NSTextField!;
 //   @IBOutlet var image: NSImageView!;
    
}

class GroupchatPMPopover: NSPopover {

    let scrollView: NSScrollView!;
    let textView: AutoresizingTextView!;
    
    let room: Room!;
    let occupant: MucOccupant!;
    
    init(room: Room, occupant: MucOccupant, text: String, size: NSSize) {
        self.room = room;
        self.occupant = occupant;
        textView = AutoresizingTextView(frame: NSRect(origin: .zero, size: NSSize(width: size.width-20, height: size.height)));
        textView.setup();
        scrollView = RoundedScrollView(frame: NSRect(origin: .zero, size: size));
        scrollView.translatesAutoresizingMaskIntoConstraints = false;
        scrollView.hasVerticalScroller = true;
        scrollView.hasHorizontalScroller = false;
        scrollView.documentView = textView;
        scrollView.drawsBackground = true;
        
        scrollView.contentInsets = NSEdgeInsets(top: 4, left: 11, bottom: 4, right: 11);
        let maxHeightConstraint = scrollView.heightAnchor.constraint(lessThanOrEqualToConstant: 108);
        maxHeightConstraint.priority = .required;
        let heightConstraint = scrollView.heightAnchor.constraint(equalTo: textView.heightAnchor, constant: 8);
        heightConstraint.priority = .defaultHigh;
        NSLayoutConstraint.activate([maxHeightConstraint, heightConstraint, scrollView.widthAnchor.constraint(equalTo: textView.widthAnchor, constant: 20)]);
        
        super.init();
        let viewController = NSViewController();
        
        let label = NSTextField(wrappingLabelWithString: String.localizedStringWithFormat(NSLocalizedString("Send private message to %@", comment: "context menu item"), occupant.nickname));
        label.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize);
        label.translatesAutoresizingMaskIntoConstraints = false;
        label.setContentHuggingPriority(.defaultLow, for: .horizontal);
        
        scrollView.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        scrollView.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
        scrollView.translatesAutoresizingMaskIntoConstraints = false;
        textView.drawsBackground = false;
        textView.isRichText = false;
        
        let view = NSView(frame: .zero);
        view.addSubview(label);
        view.addSubview(scrollView);
        let sendButton = NSButton(title: NSLocalizedString("Send", comment: "context menu item"), target: self, action: #selector(sendPM));
        sendButton.translatesAutoresizingMaskIntoConstraints = false;
        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.addSubview(sendButton);
        let cancelButton = NSButton(title: NSLocalizedString("Cancel", comment: "context menu item"), target: self, action: #selector(self.close));
        cancelButton.translatesAutoresizingMaskIntoConstraints = false;
        cancelButton.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.addSubview(cancelButton);
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: label.topAnchor, constant: -10),
            view.leadingAnchor.constraint(equalTo: label.leadingAnchor, constant: -20),
            view.trailingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 20),
            scrollView.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 10),
            view.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: -20),
            view.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: 20),
            sendButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            cancelButton.centerYAnchor.constraint(equalTo: sendButton.centerYAnchor, constant: 0),
            cancelButton.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -10),
            cancelButton.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
//            view.leadingAnchor.constraint(greaterThanOrEqualTo: sendButton.leadingAnchor, constant: -20),
            view.trailingAnchor.constraint(equalTo: sendButton.trailingAnchor, constant: 20),
            view.bottomAnchor.constraint(equalTo: sendButton.bottomAnchor, constant: 10)
        ]);
        view.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
        textView.string = text;
        
        viewController.view = view;
        self.contentViewController = viewController;
        self.behavior = .semitransient;
        self.animates = true;
    }
    
    required init?(coder: NSCoder) {
        self.room = nil;
        self.occupant = nil;
        textView = nil;
        scrollView = nil;
        super.init(coder: coder)
    }
    
    @objc func sendPM(_ sender: NSButton) {
        room.sendPrivateMessage(to: occupant, text: textView.string)
        self.close();
    }
        
}

class GroupchatParticipantCellView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarViewWithStatus! {
        didSet {
            avatar.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        }
    }
    @IBOutlet var label: NSTextField!;
   
    private var cancellables: Set<AnyCancellable> = [];
    
    private var occupant: MucOccupant? {
        didSet {
            cancellables.removeAll();

            if let occupant = occupant {
                label.stringValue = occupant.nickname;
                
                occupant.$presence.map({ $0.show }).receive(on: DispatchQueue.main).assign(to: \.status, on: avatar).store(in: &cancellables);
            }
        }
    }
    private var avatarObj: Avatar? {
        didSet {
            let name = self.label.stringValue;
            avatarObj?.avatarPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] image in
                self?.avatar.avatarView.set(name: name, avatar: image);
            }).store(in: &cancellables);
        }
    }
    
    func set(occupant: MucOccupant, in room: Room) {
        self.occupant = occupant;
        self.avatarObj = occupant.avatar;
    }
    
}


extension MucOccupant {
        
    var avatar: Avatar? {
        if let room = self.room {
            return AvatarManager.instance.avatarPublisher(for: .init(account: room.account, jid: room.jid, mucNickname: nickname));
        } else {
            return nil;
        }
    }
    
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
        menu.addItem(MenuItemWithOccupant(title: NSLocalizedString("Private message", comment: "context menu item"), action: #selector(privateMessage(_:)), keyEquivalent: ""));
        menu.addItem(MenuItemWithOccupant(title: NSLocalizedString("Ban user", comment: "context menu item"), action: #selector(banUser(_:)), keyEquivalent: ""));
        return menu;
    }
    
    func numberOfItems(in menu: NSMenu) -> Int {
        return menu.items.count;
    }
 
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool {
        guard let clickedRow = self.outlineView?.clickedRow, clickedRow > 0, let participant = self.outlineView?.item(atRow: clickedRow) as? MucOccupant, let nickname = self.room?.nickname else {
            item.isHidden = true;
            return true;
        }
                
        switch item.action {
        case #selector(privateMessage(_:)):
            guard room?.canSendPrivateMessage() ?? false else {
                item.isHidden = true;
                return true;
            }
        case #selector(banUser(_:)):
            guard let affiliation = self.room?.occupant(nickname: nickname)?.affiliation, (affiliation == .admin || affiliation == .owner) else {
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
        guard let participant = (menuItem as? MenuItemWithOccupant)?.occupant, let jid = participant.jid, let room = self.room, let mucModule = room.context?.module(.muc) else {
            return;
        }
        
        guard let window = self.outlineView?.window else {
            return;
        }
        
        let alert = NSAlert();
        alert.icon = NSImage(named: NSImage.cautionName);
        alert.messageText = String.localizedStringWithFormat(NSLocalizedString("Do you wish to ban user %@?", comment: "alert window title"), participant.nickname);
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("No", comment: "Button"))
        alert.beginSheetModal(for: window, completionHandler: { response in
            switch response {
            case .alertFirstButtonReturn:
                // we need to ban the user
                mucModule.setRoomAffiliations(to: room, changedAffiliations: [MucModule.RoomAffiliation(jid: jid.withoutResource, affiliation: .outcast)], completionHandler: { result in
                    switch result {
                    case .success(_):
                        break;
                    case .failure(let error):
                        DispatchQueue.main.async {
                            let alert = NSAlert();
                            alert.icon = NSImage(named: NSImage.cautionName);
                            alert.messageText = String.localizedStringWithFormat(NSLocalizedString("Banning user %@ failed", comment: "alert window title"), participant.nickname);
                            alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "alert window message"), error.localizedDescription);
                            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                            alert.beginSheetModal(for: window, completionHandler: { response in
                                //we do not care about the response
                            })
                        }
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
        guard let participant = (menuItem as? MenuItemWithOccupant)?.occupant else {
            return;
        }
        
        self.delegate?.showSendPMPopover(for: participant, withText: nil);
    }
    
    
    class MenuItemWithOccupant: NSMenuItem {
        
        weak var occupant: MucOccupant?;
        
    }
}

class MucOccupantSuggestionItemView: SuggestionItemViewBase<MucOccupant> {
    
    struct Provider: SuggestionItemViewProvider {
        
        func view(for item: Any) -> SuggestionItemView? {
            guard item is MucOccupant else {
                return nil;
            }
            return MucOccupantSuggestionItemView();
        }
        
    }
    
    let avatar: AvatarView;
    let label: NSTextField;
    let stack: NSStackView;
    
    private var cancellables: Set<AnyCancellable> = [];
    private var avatarPublisher: Avatar?;
    
    override var itemHeight: Int {
        return 24;
    }
    
    override var item: MucOccupant? {
        didSet {
            cancellables.removeAll();
            label.stringValue = item?.nickname ?? "";
            avatar.name = item?.nickname ?? "";
            self.avatarPublisher = item?.avatar;
            avatarPublisher?.avatarPublisher.assign(to: \.avatar, on: avatar).store(in: &cancellables);
        }
    }
    
    required init() {
        avatar = AvatarView(frame: NSRect(origin: .zero, size: NSSize(width: 16, height: 16)));

        label = NSTextField(labelWithString: "");
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium);
        label.cell?.truncatesLastVisibleLine = true;
        label.cell?.lineBreakMode = .byTruncatingTail;
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack = NSStackView(views: [avatar, label]);
        stack.translatesAutoresizingMaskIntoConstraints = false;
        stack.spacing = 6;
        stack.alignment = .centerY;
        stack.orientation = .horizontal;
        stack.distribution = .fill;
//            stack.setHuggingPriority(.defaultHigh, for: .vertical);
        stack.setHuggingPriority(.defaultHigh, for: .horizontal);
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack.visibilityPriority(for: label);
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4);
        NSLayoutConstraint.activate([
            avatar.heightAnchor.constraint(equalToConstant: 20),
            avatar.widthAnchor.constraint(equalToConstant: 20),
            avatar.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 1.0, constant: -2 * 2),
            label.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2)
        ])
        
        super.init();
        
        addSubview(stack);
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            self.topAnchor.constraint(equalTo: stack.topAnchor),
            self.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
