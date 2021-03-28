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
import Combine

class GroupchatParticipantsTableView: NSTableView {
    
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
    @IBOutlet var participantsTableView: NSTableView!;
    
    fileprivate var participantsContainer: GroupchatParticipantsContainer?;
    
    private var pmPopupPositioningView: NSView!;
    
    private var cancellables: Set<AnyCancellable> = [];
    var room: Room! {
        get {
            return (self.conversation as! Room);
        }
    }
    
    private var role: MucRole = .none {
        didSet {
            self.refreshPermissions();
        }
    }
    private var affiliation: MucAffiliation = .none {
        didSet {
            self.refreshPermissions();
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
        self.participantsContainer?.tableView = self.participantsTableView;
        self.participantsTableView.delegate = participantsContainer;
        self.participantsTableView.dataSource = participantsContainer;

        super.viewDidLoad();
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
        jidView.stringValue = room.roomJid.stringValue;

        sidebarWidthConstraint.constant = Settings.showRoomDetailsSidebar ? 200 : 0;
        avatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        self.participantsContainer?.room = self.room;
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear();
        cancellables.removeAll();
    }
    
    override func createSharingAvailablePublisher() -> AnyPublisher<Bool, Never>? {
        guard let publisher = super.createSharingAvailablePublisher() else {
            return nil;
        }

        return room.$state.combineLatest(publisher, { (state, available) in
            return available && state == .joined;
        }).eraseToAnyPublisher();
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
    override func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int) {
        super.prepareConversationLogContextMenu(dataSource: dataSource, menu: menu, forRow: row);
        if row != NSNotFound || !(self.conversationLogController?.selectionManager.hasSingleSender ?? false) {
            let reply = menu.addItem(withTitle: "Reply with PM", action: #selector(replySelectedMessagesViaPM), keyEquivalent: "");
            reply.target = self
            reply.tag = row;
        }
        if let item = dataSource.getItem(at: row), item.state.direction == .outgoing {
            switch item.payload {
            case .message(_, _), .attachment(_, _):
                if item.state.isError {
                } else {
                    if item.isMessage(), !dataSource.isAnyMatching({ $0.state.direction == .outgoing && $0.isMessage() }, in: 0..<row) {
                        let correct = menu.addItem(withTitle: "Correct message", action: #selector(correctMessage), keyEquivalent: "");
                        correct.target = self;
                        correct.tag = item.id;
                    }
                
                    if room.state == .joined {
                        let retract = menu.addItem(withTitle: "Retract message", action: #selector(retractMessage), keyEquivalent: "");
                        retract.target = self;
                        retract.tag = item.id;
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
        alert.messageText = "Are you sure you want to retract that message?"
        alert.informativeText = "That message will be removed immediately and it's receives will be asked to remove it as well.";
        alert.addButton(withTitle: "Retract");
        alert.addButton(withTitle: "Cancel");
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

    override func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            if suggestionsController?.window?.isVisible ?? false {
                suggestionsController?.moveUp(textView);
                return true
            } else {
                return super.textView(textView, doCommandBy: commandSelector);
            }
        case #selector(NSResponder.moveDown(_:)):
            if suggestionsController?.window?.isVisible ?? false {
                suggestionsController?.moveDown(textView);
                return true
            } else {
                return super.textView(textView, doCommandBy: commandSelector);
            }
        case #selector(NSResponder.cancelOperation(_:)):
            if suggestionsController?.window?.isVisible ?? false {
                suggestionsController?.cancelSuggestions();
                return true;
            } else {
                return false;
            }
        case #selector(NSResponder.insertNewline(_:)):
            if let controller = suggestionsController, controller.window?.isVisible ?? false {
                suggestionItemSelected(sender: controller);
                return true;
            } else {
                return super.textView(textView, doCommandBy: commandSelector);
            }
        case #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteBackward(_:)):
            return super.textView(textView, doCommandBy: commandSelector);
        default:
            return super.textView(textView, doCommandBy: commandSelector);
        }
    }
        
    override func textDidChange(_ obj: Notification) {
        super.textDidChange(obj);
        self.messageField.complete(nil);
    }
    
    var suggestionsController: SuggestionsWindowController<MucOccupant>?;
    
    func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        guard charRange.length != 0 && charRange.location != NSNotFound else {
            suggestionsController?.cancelSuggestions();
            return [];
        }

        let tmp = textView.string;
        let utf16 = tmp.utf16;
        let start = utf16.index(utf16.startIndex, offsetBy: charRange.lowerBound);
        let end = utf16.index(utf16.startIndex, offsetBy: charRange.upperBound);
        guard let query = String(utf16[start..<end])?.uppercased() else {
            suggestionsController?.cancelSuggestions();
            return [];
        }

        let suggestions: [MucOccupant] = self.room.occupants.filter({ $0.nickname.uppercased().starts(with: query) }).sorted(by: { p1, p2 -> Bool in p1.nickname < p2.nickname });

        index?.initialize(to: -1);//suggestions.isEmpty ? -1 : 0);

        if suggestions.isEmpty {
            suggestionsController?.cancelSuggestions();
        } else {
            if suggestionsController == nil {
                suggestionsController = SuggestionsWindowController(viewProvider: MucOccupantSuggestionItemView.self, edge: .top);
                suggestionsController?.backgroundColor = NSColor.textBackgroundColor;
                suggestionsController?.target = self;
                suggestionsController?.action = #selector(self.suggestionItemSelected(sender:))
            }
            let range = NSRange(location: charRange.location - 1, length: charRange.length + 1)
            DispatchQueue.main.async {
                self.suggestionsController?.beginFor(textView: textView, range: range);
                self.suggestionsController?.update(suggestions: suggestions);
            }
        }
        
        return [];
    }
    
    @objc func suggestionItemSelected(sender: Any) {
        guard let item = (sender as? SuggestionsWindowController<MucOccupant>)?.selected, let range = (sender as? SuggestionsWindowController<MucOccupant>)?.range else {
            return;
        }
        
        print("selected item: \(item.jid?.stringValue ?? "nil") with nickname: \(item.nickname)")
        // how to know where we should place it? should we store location in message view somehow?
        self.messageField.replaceCharacters(in: range, with: "@\(item.nickname) ");
        suggestionsController?.cancelSuggestions();
    }

}

class GroupchatParticipantsContainer: NSObject, NSTableViewDelegate, NSTableViewDataSource {

    private var cancellables: Set<AnyCancellable> = [];
    
    weak var tableView: NSTableView? {
        didSet {
            tableView?.usesAutomaticRowHeights = false;
            tableView?.rowHeight = 28;
            tableView?.menu = self.prepareContextMenu();
            tableView?.menu?.delegate = self;
        }
    }
    var room: Room? {
        didSet {
            cancellables.removeAll();
            self.tableView?.isHidden = true;
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
//                self.room?.occupantsPublisher.receive(on: self.dispatcher.queue).sink(receiveValue:{ [weak self] value in
//                    self?.update(participants: value);
//                }).store(in: &self.cancellables);
//            }
            room?.occupantsPublisher.receive(on: self.dispatcher.queue).sink(receiveValue:{ [weak self] value in
                    self?.update(participants: value);
            }).store(in: &cancellables);
        }
    }
    private var participants: [MucOccupant] = [];
    
    weak var delegate: GroupchatViewController?;
    
    private var dispatcher = QueueDispatcher(label: "GroupchatParticipantsContainer");
    
    init(delegate: GroupchatViewController) {
        self.delegate = delegate;
        super.init();
    }
    
    private func update(participants: [MucOccupant]) {
        let oldParticipants = self.participants;
        let newParticipants = participants.sorted(by: { (i1,i2) -> Bool in i1.nickname.lowercased() < i2.nickname.lowercased() });
        let changes = newParticipants.calculateChanges(from: oldParticipants);
            
        let initialReload = oldParticipants.isEmpty;
        DispatchQueue.main.sync {
            self.participants = newParticipants;
            self.tableView?.beginUpdates();
            self.tableView?.removeRows(at: changes.removed, withAnimation: initialReload ? [] : .effectFade);
            self.tableView?.insertRows(at: changes.inserted, withAnimation: initialReload ? [] : .effectFade);
            self.tableView?.endUpdates();
            self.tableView?.isHidden = false;
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return participants.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let participant = participants[row];
        if let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("GroupchatParticipantCellView"), owner: nil) as? GroupchatParticipantCellView {
            
            view.set(occupant: participant, in: room!);
            view.identifier = NSUserInterfaceItemIdentifier("GroupchatParticipantCellView")
                    
            return view;
        }
        return nil;
    }
    
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
        
        let label = NSTextField(wrappingLabelWithString: "Send private message to \(occupant.nickname):")
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
        let sendButton = NSButton(title: "Send", target: self, action: #selector(sendPM));
        sendButton.translatesAutoresizingMaskIntoConstraints = false;
        sendButton.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        view.addSubview(sendButton);
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(self.close));
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
        print("sending PM:" + textView.string);
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
    
    public static func roleToEmoji(_ role: MucRole) -> String {
        switch role {
        case .none, .visitor:
            return "";
        case .participant:
            return "⭐";
        case .moderator:
            return "🌟";
        }
    }
    
    private var occupant: MucOccupant? {
        didSet {
            cancellables.removeAll();

            if let occupant = occupant {
                let nickname = occupant.nickname;
                label.stringValue = occupant.nickname;
                
                occupant.$presence.map({ $0.show }).receive(on: DispatchQueue.main).assign(to: \.status, on: avatar).store(in: &cancellables);
                occupant.$presence.map(XMucUserElement.extract(from: )).map({ $0?.role ?? .none }).map({ "\(nickname) \(GroupchatParticipantCellView.roleToEmoji($0))" }).receive(on: DispatchQueue.main).assign(to: \.stringValue, on: label).store(in: &cancellables);
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
            if let jid = self.jid?.bareJid {
                return AvatarManager.instance.avatarPublisher(for: .init(account: room.account, jid: jid, mucNickname: nil));
            } else {
                return AvatarManager.instance.avatarPublisher(for: .init(account: room.account, jid: room.jid, mucNickname: nickname));
            }
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
                mucModule.setRoomAffiliations(to: room, changedAffiliations: [MucModule.RoomAffiliation(jid: jid.withoutResource, affiliation: .outcast)], completionHandler: { result in
                    switch result {
                    case .success(_):
                        break;
                    case .failure(let error):
                        DispatchQueue.main.async {
                            let alert = NSAlert();
                            alert.icon = NSImage(named: NSImage.cautionName);
                            alert.messageText = "Banning user \(participant.nickname) failed";
                            alert.informativeText = "Server returned an error: \(error.message ?? error.description)";
                            alert.addButton(withTitle: "OK");
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

class MucOccupantSuggestionItemView: SuggestionItemView<MucOccupant> {
    
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
