//
// ChatsListView.swift
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

enum ChatsListStyle: String {
    case minimal
    case small
    case large
}

protocol ChatsListViewDataSourceDelegate: class {
    
    func beginUpdates()
    
    func endUpdates()

    func itemsInserted(at: IndexSet, inParent: Any?);
    
    func itemsRemoved(at: IndexSet, inParent: Any?);
    
    func itemChanged(item: Any?);
    
    func itemMoved(from: Int, fromParent: Any?, to: Int, toParent: Any?);
    
    func reload();
}


class ChatsListViewController: NSViewController, NSOutlineViewDataSource, ChatsListViewDataSourceDelegate, NSSearchFieldDelegate {
    
    static let CHAT_SELECTED = Notification.Name("chatSelected");
    static let CLOSE_SELECTED_CHAT = Notification.Name("chatSelectedClose");
    
    @IBOutlet var searchField: NSSearchField!;
    
    @IBOutlet var outlineView: ChatsListView!;
    
    var groups: [ChatsListGroupProtocol] = [];
    
    var invitationGroup: InvitationGroup?;

    private var cancellables: Set<AnyCancellable> = [];
    private var suggestionsController: SuggestionsWindowController<DisplayableIdWithKeyProtocol>?;
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        if suggestionsController == nil {
            suggestionsController = SuggestionsWindowController(viewProvider: ChatsListSuggestionItemView.self, edge: .bottom);
            suggestionsController?.backgroundColor = NSColor(named: "sidebarBackgroundColor")
            suggestionsController?.target = self;
            suggestionsController?.action = #selector(self.suggestionItemSelected(sender:))
        }
//        suggestionsController?.beginFor(textField: self.searchField!);
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if searchField.stringValue.count < 2 {
            suggestionsController?.cancelSuggestions();
        } else {
            let query = searchField.stringValue.lowercased();
            
            let conversations: [DisplayableIdWithKeyProtocol] = DBChatStore.instance.conversations.filter({ $0.displayName.lowercased().contains(query) || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) });

            let keys = Set(conversations.map({ Contact.Key(account: $0.account, jid: $0.jid, type: .buddy) }));
            
            let contacts: [DisplayableIdWithKeyProtocol] = DBRosterStore.instance.items.filter({ $0.name?.lowercased().contains(searchField.stringValue) ?? false || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) }).compactMap({ item -> Contact? in
                guard let account = item.context?.userBareJid, !keys.contains(.init(account: account, jid: item.jid.bareJid, type: .buddy)) else {
                    return nil;
                }
                return ContactManager.instance.contact(for: .init(account: account, jid: item.jid.bareJid, type: .buddy))
            });
            
            
            let items: [DisplayableIdWithKeyProtocol] = (contacts + conversations).sorted(by: { c1, c2 -> Bool in c1.displayName < c2.displayName });
            
            if !items.isEmpty {
                if !(suggestionsController?.window?.isVisible ?? false) {
                    suggestionsController?.beginFor(textField: self.searchField!);
                }
            }
            
            suggestionsController?.update(suggestions: items);
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        suggestionsController?.cancelSuggestions();
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            suggestionsController?.moveUp(textView);
            return true
        case #selector(NSResponder.moveDown(_:)):
            suggestionsController?.moveDown(textView);
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if let controller = self.suggestionsController {
                suggestionItemSelected(sender: controller);
            }
        case #selector(NSResponder.complete(_:)):
            suggestionsController?.cancelSuggestions();
            return true;
        default:
            break;
        }
        return false;
    }
    
    @objc func suggestionItemSelected(sender: Any) {
        guard let item = (sender as? SuggestionsWindowController<DisplayableIdWithKeyProtocol>)?.selected else {
            return;
        }
        
        self.searchField.stringValue = "";
        
        print("selected item: \(item.jid) in \(item.account)")
        
        if let conversation = DBChatStore.instance.conversation(for: item.account, with: item.jid) {
            // we have conversation, select it to open
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: conversation);
        } else if item is Contact {
            guard let client = XmppService.instance.getClient(for: item.account) else {
                return;
            }
            
            if let chat = client.modulesManager.module(.message).chatManager.createChat(for: client, with: item.jid) {
                NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: chat)
            }
        }
    }
    
    override func viewDidLoad() {
        if #available(macOS 11.0, *) {
            self.outlineView.style = .fullWidth;
        }
        self.invitationGroup = InvitationGroup(delegate: self);
        Settings.$commonChatsList.sink(receiveValue: { [weak self] value in
            guard let that = self else {
                return;
            }
            var newGroups: [ChatsListGroupProtocol] = [];
            if let invitationGroup = that.invitationGroup, !invitationGroup.items.isEmpty {
                newGroups.append(invitationGroup)
            }

            if value {
                newGroups.append(contentsOf: [ChatsListGroupCommon(delegate: that)]);
            } else {
                newGroups.append(contentsOf: [ChatsListGroupGroupchat(delegate: that), ChatsListGroupChat(delegate: that)])
            }
            newGroups.append(ChatsListGroupChatUnknown(delegate: that));
            that.groups = newGroups;
            that.reload();
            for group in that.groups {
                that.outlineView.expandItem(group);
            }
        }).store(in: &cancellables)
        Settings.$chatslistStyle.dropFirst().receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] _ in
            self?.reload()
        }).store(in: &cancellables);

        outlineView.reloadData();
                
        NotificationCenter.default.addObserver(self, selector: #selector(chatSelected), name: ChatsListViewController.CHAT_SELECTED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(closeSelectedChat), name: ChatsListViewController.CLOSE_SELECTED_CHAT, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(invitationClicked(_:)), name: InvitationManager.INVITATION_CLICKED, object: nil);
        searchField.delegate = self;
    }
    
    override func viewWillAppear() {
//        self.view.window!.acceptsMouseMovedEvents = true;
        searchField.appearance = NSAppearance(named: .darkAqua);
        super.viewWillAppear();
        outlineView.expandItem(nil, expandChildren: true);
        self.view.layer?.backgroundColor = NSColor(named: "sidebarBackgroundColor")!.cgColor;
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let group = item as? ChatsListGroupProtocol {
            return group.count;
        }
        return groups.count;
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? ChatsListGroupProtocol {
            return group.getItem(at: index)!;
        }
        return groups[index];
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard item is ChatsListGroupProtocol else {
            return false;
        }
        return true;
    }
    
    func reload() {
        outlineView.reloadData();
    }
    
    func beginUpdates() {
        outlineView.beginUpdates();
    }
    
    func endUpdates() {
        outlineView.endUpdates();
    }
    
    func itemsInserted(at: IndexSet, inParent: Any?) {
        outlineView.insertItems(at: at, inParent: inParent, withAnimation: .slideLeft);
    }
    
    func itemsRemoved(at: IndexSet, inParent: Any?) {
        outlineView.removeItems(at: at, inParent: inParent, withAnimation: .slideRight);
    }
    
    func itemMoved(from: Int, fromParent: Any?, to: Int, toParent: Any?) {
        outlineView.moveItem(at: from, inParent: fromParent, to: to, inParent: toParent);
    }
    
    func itemChanged(item: Any?) {
        outlineView.reloadItem(item);
    }
    
    func invitationGroup(show: Bool) {
        if show {
            groups.insert(invitationGroup!, at: 0);
            outlineView.insertItems(at: IndexSet(integer: 0), inParent: nil)
            outlineView.expandItem(invitationGroup!);
        } else {
            groups.remove(at: 0);
            outlineView.removeItems(at: IndexSet(integer: 0), inParent: nil)
        }
    }
    
    @IBAction func openNewChatClicked(_ sender: NSButton) {
        print("open new chat cliecked");
        guard let group = (sender as? OutlineGroupItemButton)?.group else {
            return;
        }
        
        print("clicked button for", group.name);
        
        switch group {
        case is ChatsListGroupGroupchat:
            self.openChannel(self);
        case is ChatsListGroupChat:
            self.openChat(self);
        case is ChatsListGroupCommon:
            let menu = NSMenu(title: "");
            menu.addItem(withTitle: "Open chat", action: #selector(self.openChat(_:)), keyEquivalent: "").image = NSImage(named: NSImage.userName)?.square(20);
            menu.addItem(withTitle: "Open channel", action: #selector(self.openChannel(_:)), keyEquivalent: "").image = NSImage(named: NSImage.userGroupName)?.square(20);
            for item in menu.items {
                item.target = self;
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.frame.height), in: sender);
        default:
            return;
        }
    }
    
    @objc func openChat(_ sender: Any) {
        guard let windowController = storyboard?.instantiateController(withIdentifier: "Open1On1ChatController") as? NSWindowController else {
            return;
        }
        view.window?.beginSheet(windowController.window!, completionHandler: nil);
    }

    @objc func openChannel(_ sender: Any) {
        guard let windowController = storyboard?.instantiateController(withIdentifier:"OpenChannelWindowController") as? NSWindowController else {
            return;
        }
        view.window?.beginSheet(windowController.window!, completionHandler: nil);
    }

    @objc func closeSelectedChat(_ notification: Notification) {
        print("closing chats for: \(self.outlineView.selectedRowIndexes)");
        let toClose = self.outlineView.selectedRowIndexes;
        toClose.forEach { (row) in
            guard let item = self.outlineView.item(atRow: row) as? ConversationItem else {
                return;
            }
            
            self.close(chat: item);
        }
    }
    
    private var scrollChatToMessageWithId: Int?;
    
    @objc func chatSelected(_ notification: Notification) {
        let messageId = notification.userInfo?["messageId"] as? Int;
        guard let chat = notification.object as? Conversation else {
            guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
                self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
                return;
            }
            self.groups.forEach { group in
                group.forChat(account: account, jid: jid) { item in
                    DispatchQueue.main.async {
                        let row = self.outlineView.row(forItem: item);
                        guard row >= 0 else {
                            return;
                        }
                        self.view.window?.windowController?.showWindow(self);
                        self.scrollChatToMessageWithId = messageId;
                        self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
                        self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false);
                    }
                }
            }
            return;
        }

        self.groups.forEach { group in
            group.forChat(chat) { item in
                DispatchQueue.main.async {
                    let row = self.outlineView.row(forItem: item);
                    guard row >= 0 else {
                        return;
                    }
                    self.view.window?.windowController?.showWindow(self);
                    self.scrollChatToMessageWithId = messageId;
                    self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
                    self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false);
                }
            }
        }
    }
    
    @objc func invitationClicked(_ notification: Notification) {
        guard let invitation = notification.object as? InvitationItem else {
            return;
        }
        
        if self.invitationGroup?.items.firstIndex(of: invitation) != nil {
            let row = self.outlineView.row(forItem: invitation);
            guard row >= 0 else {
                return;
            }
            self.view.window?.windowController?.showWindow(self);
            self.outlineView.selectRowIndexes(IndexSet(), byExtendingSelection: false);
            self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false);
        }
    }
    
}

extension ChatsListViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if item is ChatsListGroupProtocol {
            if outlineView.isItemExpanded(item) {
                //                outlineView.collapseItem(item);
            } else {
                outlineView.expandItem(item);
            }
            return false;
        }
        if item is ConversationItem {
            return true;
        }
        if item is InvitationItem {
            return true;
        }
        return false;
    }
    
    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        return item is ChatsListGroupProtocol;
    }
    
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return ChatsListTableRowView(frame: NSRect.zero);
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        if self.outlineView.selectedRowIndexes.count <= 1 {
            self.outlineView.selectionDirection = .unknown;
        }
        
        let selected = self.outlineView.selectedRow;
        let item = self.outlineView.selectedRowIndexes.count == 1 ? self.outlineView.item(atRow: selected) : nil;

        print("selected row: \(selected), item: \(String(describing: item)), selectedRowIndexes: \(self.outlineView.selectedRowIndexes.count)");
        if let splitController = self.outlineView.window?.contentViewController as? NSSplitViewController {
            if let conversation = (item as? ConversationItem)?.chat {
                let controller = self.conversationController(for: conversation);
                if let conversationController = controller as? AbstractChatViewController {
                    conversationController.conversation = conversation;
                    _ = conversationController.view;
                    if let msgId = self.scrollChatToMessageWithId {
                        conversationController.dataSource.loadItems(.with(id: msgId, overhead: conversationController.dataSource.defaultPageSize));
                    } else {
                        conversationController.dataSource.loadItems(.unread(overhead: conversationController.dataSource.defaultPageSize));
                    }
                    self.scrollChatToMessageWithId = nil;
                }

                let item = NSSplitViewItem(viewController: controller);
                if splitController.splitViewItems.count == 1 {
                    splitController.addSplitViewItem(item);
                } else {
                    splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    splitController.addSplitViewItem(item);
                }
            } else {
                if let invitation = item as? InvitationItem, invitation.type == .presenceSubscription {
                    let controller = NSStoryboard(name: "Roster", bundle: nil).instantiateController(withIdentifier: "PresenceAuthorizationRequestView") as! PresenceAuthorizationRequestController;
                    controller.invitation = invitation;
                    if splitController.splitViewItems.count > 1 {
                        splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    }
                    splitController.addSplitViewItem(NSSplitViewItem(viewController: controller));
                } else {
                    let controller = self.storyboard!.instantiateController(withIdentifier: "EmptyViewController") as! NSViewController;
                    if splitController.splitViewItems.count > 1 {
                        splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    }
                    splitController.addSplitViewItem(NSSplitViewItem(viewController: controller));
                    if let invitation = item as? InvitationItem {
                        InvitationManager.instance.handle(invitation: invitation, window: self.view.window!);
                    }
                }
            }
        } else {
            print("could not find NSSplitViewController: \(String(describing: self.outlineView.window?.contentView))")
        }
    }
    
    private func conversationController(for conversation: Any) -> NSViewController {
        switch conversation {
        case is Chat:
            return self.storyboard!.instantiateController(withIdentifier: "ChatViewController") as! ChatViewController;
        case is Room:
            return self.storyboard!.instantiateController(withIdentifier: "GroupchatViewController") as! GroupchatViewController;
        case is Channel:
            return NSStoryboard(name: "MIX", bundle: nil).instantiateController(withIdentifier: "ChannelViewController") as! ChannelViewController;
        default:
            print("undefined conversation type: \(conversation.self) \(String(describing: conversation))")
            return self.storyboard!.instantiateController(withIdentifier: "EmptyViewController") as! NSViewController;
        }
    }

    enum ViewType {
        case conversation
        case invitation
    }
    
    func viewIdentifier(for type: ViewType) -> NSUserInterfaceItemIdentifier {
        switch Settings.chatslistStyle {
        case .minimal:
            return NSUserInterfaceItemIdentifier("ChatMinimalCell");
        case .small:
            return NSUserInterfaceItemIdentifier("ChatSmallCell");
        case .large:
            return NSUserInterfaceItemIdentifier("ChatLargeCell");
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        //var view: NSTableCellView?
//        guard tableColumn?.identifier.rawValue == "ITEM1" else {
//            return nil;
//        }
        
        if let group = item as? ChatsListGroupProtocol {
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ChatGroupCell"), owner: nil) as? NSTableCellView;
            if let textField = view?.textField {
                textField.stringValue = group.name;
                //textField.sizeToFit();
            }
            if let button = view?.subviews[1] as? OutlineGroupItemButton {
                button.group = group;
                button.isHidden = !group.canOpenChat;
            }
            return view;
        } else if let chat = item as? ConversationItem {
            let view = outlineView.makeView(withIdentifier: self.viewIdentifier(for: .conversation), owner: nil) as? ChatCellView;

//            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(chat.chat.jid.localPart == "int" ? "ChatBigCell" : "ChatSmallCell"), owner: nil) as? ChatCellView;
            view?.avatar.backgroundColor = NSColor(named: "sidebarBackgroundColor");
            view?.update(from: chat);
//            view?.lastMessage.preferredMaxLayoutWidth = self.outlineView.outlineTableColumn!.width - 66;
            view?.closeFunction = { [weak self] in
                self?.close(chat: chat);
            }
            view?.setMouseHovers(false);
            return view;
        } else if let invitation = item as? InvitationItem {
            let view = outlineView.makeView(withIdentifier: self.viewIdentifier(for: .conversation), owner: nil) as? ChatCellView;
//            view?.avatar.image = AvatarManager.instance.avatar(for: invitation.jid.bareJid, on: invitation.account) ?? AvatarManager.instance.defaultAvatar;
//            view?.label.stringValue = DBRosterStore.instance.item(for: invitation.account, jid: invitation.jid)?.name ?? invitation.jid.stringValue;
//            view?.message.maximumNumberOfLines = 2;
//            view?.message.stringValue = invitation.name;
            view?.update(from: invitation);
            return view;
        }
        return nil;
    }
        
    func close(chat: ConversationItem) {
        switch chat.chat {
        case let c as Chat:
            _ = DBChatStore.instance.close(chat: c);
        case let r as Room:
            guard let mucModule = r.context?.module(.muc) else {
                return;
            }
            
            if r.occupant(nickname: r.nickname)?.affiliation == .owner {
                let alert = NSAlert();
                alert.alertStyle = .warning;
                alert.messageText = "Delete group chat?"
                alert.informativeText = "You are leaving the group chat \(r.name ?? r.jid.stringValue)";
                alert.addButton(withTitle: "Delete chat")
                alert.addButton(withTitle: "Leave chat")
                alert.addButton(withTitle: "Cancel")
                alert.beginSheetModal(for: self.view.window!) { (response) in
                    switch response {
                    case .alertFirstButtonReturn:
                        mucModule.destroy(room: r);
                        PEPBookmarksModule.remove(from: r.account, bookmark: Bookmarks.Conference(name: r.name ?? r.roomJid.stringValue, jid: JID(r.jid), autojoin: false));
                    case .alertSecondButtonReturn:
                        mucModule.leave(room: r);
                        PEPBookmarksModule.remove(from: r.account, bookmark: Bookmarks.Conference(name: r.name ?? r.roomJid.stringValue, jid: JID(r.jid), autojoin: false));
                    default:
                        // cancel, nothing to do..
                        break;
                    }
                };
            } else {
                mucModule.leave(room: r);
                PEPBookmarksModule.remove(from: r.account, bookmark: Bookmarks.Conference(name: r.name ?? r.roomJid.stringValue, jid: JID(r.jid), autojoin: false));
            }
        case let c as Channel:
            guard let mixModule = c.context?.module(.mix) else {
                return;
            }
            mixModule.leave(channel: c, completionHandler: { result in
                switch result {
                case .success(_):
                    _ = DBChatStore.instance.close(channel: c);
                case .failure(_):
                    break;
                }
            })
        default:
            print("unknown type of chat!");
        }
    }
}

class ChatsListView: NSOutlineView {
    
    var trackingArea: NSTrackingArea?;
    var mouseOverRow = -1;
    var mouseInside = false;
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect);
        trackingArea = NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited,.mouseMoved,.activeAlways], owner: self, userInfo: nil);
        self.addTrackingArea(trackingArea!);
        
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { (event) -> NSEvent? in
            guard event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.first?.unicodeScalars.first?.value == UInt32(NSBackspaceCharacter) else {
                return event;
            }
            
            // we detected shortcut!!
            return nil;
        }
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();
    }
    
    deinit {
    }
    
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        return NSRect.zero;
    }
    
    override func mouseEntered(with event: NSEvent) {
        print("mouse entered");
        mouseInside = true;
        updateMouseOver(from: event);
        super.mouseEntered(with: event);
    }
    
    override func mouseExited(with event: NSEvent) {
        print("mouse exited");
        mouseInside = false;
        updateMouseOver(from: event);
        super.mouseExited(with: event);
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard mouseInside else {
            return;
        }

        updateMouseOver(from: event);
        super.mouseMoved(with: event);
    }
    
    enum SelectionDirection {
        case up
        case down
        case unknown
    }
    
    var selectionDirection: SelectionDirection = .unknown;
    
    override func keyDown(with event: NSEvent) {
        print("got event: \(event)");
        
        let sorted = selectedRowIndexes.sorted();
        guard !sorted.isEmpty else {
            super.keyDown(with: event);
            return;
        }
        
        let first = sorted.first!;
        let last = sorted.last!;
        
        let move = !event.modifierFlags.contains(.shift);
        
        switch Int(event.charactersIgnoringModifiers?.first?.unicodeScalars.first?.value ?? 0) {
        case NSDownArrowFunctionKey:
            switch selectionDirection {
            case .down, .unknown:
                selectionDirection = .down;
                let newLast = last.advanced(by: 1);
                guard newLast < numberOfRows else {
                    return;
                }
                
                if move {
                    self.updateRowSelection(IndexSet(integer: newLast), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: first...newLast), byExtendingSelection: false);
                }
            case .up:
                let newFirst = first.advanced(by: 1);
                guard newFirst <= last else {
                    self.selectionDirection = .unknown;
                    self.keyDown(with: event);
                    return;
                }
                if move {
                    self.updateRowSelection(IndexSet(integer: newFirst), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: newFirst...last), byExtendingSelection: false);
                }
            }
        case NSUpArrowFunctionKey:
            switch selectionDirection {
            case .down:
                let newLast = last.advanced(by: -1);
                guard newLast >= first else {
                    selectionDirection = .unknown;
                    self.keyDown(with: event);
                    return;
                }
                if move {
                    self.updateRowSelection(IndexSet(integer: newLast), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: first...newLast), byExtendingSelection: false);
                }
            case .up, .unknown:
                selectionDirection = .up;
                let newFirst = first.advanced(by: -1);
                guard newFirst >= 0 else {
                    return;
                }
                if move {
                    self.updateRowSelection(IndexSet(integer: newFirst), byExtendingSelection: false);
                } else {
                    self.updateRowSelection(IndexSet(integersIn: newFirst...last), byExtendingSelection: false);
                }
            }
        default:
            break;
        }
    }
    
    override func insertItems(at indexes: IndexSet, inParent parent: Any?, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        super.insertItems(at: indexes, inParent: parent, withAnimation: animationOptions);
        updateMouseOver(at: NSEvent.mouseLocation);
    }
    
    override func removeItems(at indexes: IndexSet, inParent parent: Any?, withAnimation animationOptions: NSTableView.AnimationOptions = []) {
        super.removeItems(at: indexes, inParent: parent, withAnimation: animationOptions);
        updateMouseOver(at: NSEvent.mouseLocation);
    }
    
    override func moveItem(at fromIndex: Int, inParent oldParent: Any?, to toIndex: Int, inParent newParent: Any?) {
        super.moveItem(at: fromIndex, inParent: oldParent, to: toIndex, inParent: newParent);
        updateMouseOver(at: NSEvent.mouseLocation);
    }
    
    fileprivate func updateMouseOver(from event: NSEvent) {
        updateMouseOver(at: event.locationInWindow);
    }
    
    fileprivate func updateMouseOver(at point: NSPoint, force: Bool = false) {
        let prevMouseOverRow = self.mouseOverRow;
        self.mouseOverRow = self.row(at: self.convert(point, from: nil));
        guard mouseOverRow != prevMouseOverRow else {
            return;
        }
        if prevMouseOverRow >= 0 {
            if prevMouseOverRow < self.numberOfRows {
                if let chatView = self.rowView(atRow: prevMouseOverRow, makeIfNecessary: false)?.subviews.last as? ChatCellView {
                    chatView.setMouseHovers(false);
                }
            }
        }
        if mouseOverRow >= 0 && mouseOverRow < self.numberOfRows {
            if let chatView = self.rowView(atRow: mouseOverRow, makeIfNecessary: false)?.subviews.last as? ChatCellView {
                chatView.setMouseHovers(true);
            }
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas();
        if trackingArea != nil {
            self.removeTrackingArea(trackingArea!);
        }
        self.trackingArea = NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited,.mouseMoved,.activeAlways], owner: self, userInfo: nil);
        self.addTrackingArea(trackingArea!);
    }

    func updateRowSelection(_ indexes: IndexSet, byExtendingSelection extend: Bool) {
        selectRowIndexes(indexes, byExtendingSelection: extend);
        DispatchQueue.main.async {
            self.window?.makeFirstResponder(self);
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        let selectedRow = self.selectedRow;
        if event.modifierFlags.contains(.shift) {
            if selectedRow != -1 {
                let endRow = self.row(at: self.convert(event.locationInWindow, from: nil));
                let range = selectedRow < endRow ? selectedRow...endRow : endRow...selectedRow;
            
                print("changing selection!");
                self.updateRowSelection(IndexSet(integersIn: range), byExtendingSelection: false);
                //NotificationCenter.default.post(name: NSOutlineView.selectionDidChangeNotification, object: nil);
            } else {
                let row = self.row(at: self.convert(event.locationInWindow, from: nil));

                print("changing selection!");
                if row != -1 {
                    self.updateRowSelection(IndexSet(integersIn: row...row), byExtendingSelection: false);
                }
                //NotificationCenter.default.post(name: NSOutlineView.selectionDidChangeNotification, object: nil);
            }
        } else {
            
            if let isKey = self.window?.isKeyWindow, !isKey {
                print("mouse down event!", event, self.window as Any, "list", NSApplication.shared.windows, "key:", self.window?.isKeyWindow as Any, "can:", self.window?.canBecomeKey as Any, "main:", self.window?.isMainWindow as Any, "can:", self.window?.canBecomeMain as Any, "isActive:", NSApp.isActive, "isRunning:", NSApp.isRunning, "isHidden:", NSApp.isHidden);
                NSApplication.shared.windows.forEach { (win) in
                    print("win:", win, "isMain:", win.isMainWindow, win.canBecomeMain, "isKey:", win.isKeyWindow, win.canBecomeKey, "sheet:", win.isSheet, "visible:", win.isVisible, "title:", win.title, "modal:", NSApp.modalWindow as Any)
                }
                
                NSApp.activate(ignoringOtherApps: true);
                self.window?.makeKey();
            }

            super.mouseDown(with: event);
        }
    }
    
}
