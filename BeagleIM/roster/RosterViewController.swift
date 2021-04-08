//
// RosterViewController.swift
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

class RosterViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    
    @IBOutlet var statusButton: NSPopUpButton!;
    @IBOutlet var statusView: NSTextField!;
    @IBOutlet var contactsTableView: NSTableView!;
    
    @IBOutlet var contactsFilterSelector: NSSegmentedControl?;
    @IBOutlet var addContactButton: NSButton!;
    
    fileprivate var items: [Item] = [];
    fileprivate let dispatcher = QueueDispatcher(label: "roster_view");
    fileprivate var prevSelection = -1;
    @Published
    private var showOnlyOnline: Bool = true;
    fileprivate var selectedStatus: StatusShow?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        self.addContactButton.isEnabled = false;
        
        self.contactsTableView.menu?.delegate = self;
        
        statusButton.setTitle(statusButton.itemTitle(at: 1));
        
        updateContactsFilterSelector();
    }
    
    override func viewWillAppear() {
        DBRosterStore.instance.$items.combineLatest($showOnlyOnline, PresenceStore.instance.$bestPresences).throttle(for: 0.1, scheduler: dispatcher.queue, latest: true).sink(receiveValue: { [weak self] (items, available, presences) in
            self?.update(items: Array(items), presences: presences, available: available);
        }).store(in: &cancellables);
        XmppService.instance.$currentStatus.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] status in self?.statusUpdated(status) }).store(in: &cancellables);
        super.viewWillAppear();
        self.statusUpdated(XmppService.instance.currentStatus);
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear();
        cancellables.removeAll();
    }
    
    private func update(items: [RosterItem], presences: [PresenceStore.Key: Presence], available: Bool) {
        let oldItems = self.items;
        
        var newItems = items.compactMap({ item -> Item? in
            guard let account = item.context?.userBareJid else {
                return nil;
            }
            
            return Item(account: account, jid: item.jid.bareJid, name: item.name, status: presences[.init(account: account, jid: item.jid.bareJid)]?.show);
        });
        if available {
            newItems = newItems.filter({ $0.status != nil });
        }
        newItems.sort();
        
        let diff = newItems.calculateChanges(from: oldItems);
        
        DispatchQueue.main.sync {
            self.items = newItems;
            if !diff.removed.isEmpty {
                self.contactsTableView.removeRows(at: diff.removed, withAnimation: .effectFade);
            }
            if !diff.inserted.isEmpty {
                self.contactsTableView.insertRows(at: diff.inserted, withAnimation: .effectFade);
            }
        }
    }
       
    func updateContactsFilterSelector() {
        contactsFilterSelector?.setSelected(true, forSegment: self.showOnlyOnline ? 1 : 0);
    }
    
    @IBAction func contactsFilterSelectorChanged(_ sender: NSSegmentedControl) {
        self.showOnlyOnline = sender.selectedSegment == 1;
    }
    
    @IBAction func statusChangeSelected(_ sender: NSPopUpButton) {
        guard let item = sender.selectedItem else {
            return;
        }
        
        if item.tag < 10 {
            let statusShow = StatusShow(rawValue: item.tag);
            if statusShow != nil {
                XmppService.instance.status = XmppService.instance.status.with(show: statusShow!.show, message: nil);
            } else {
                self.statusButton.setTitle(item.title);
                self.statusButton.item(at: 0)?.image = item.image;
                DispatchQueue.main.async {
                    self.setStatusViewEditable(true)
                }
            }
        } else {
            selectedStatus = StatusShow(rawValue: item.tag % 10);
            self.statusButton.setTitle(item.title);
            self.statusButton.item(at: 0)?.image = item.image;
            DispatchQueue.main.async {
                self.setStatusViewEditable(true)
            }
        }
    }
    
    @IBAction func statusMessageChanged(_ sender: NSTextField) {
        setStatusViewEditable(false);
        
        let message = self.statusView.stringValue;
        let show = self.selectedStatus?.show ?? XmppService.instance.status.show;
        
        XmppService.instance.status = XmppService.Status(show: show, message: message.isEmpty ? nil : message);
    }
    
    fileprivate func setStatusViewEditable(_ val: Bool) {
        if val {
            self.statusView.isEditable = true;
            self.statusView.isEnabled = true;
            self.statusView.isBezeled = true;
            self.statusView.bezelStyle = .roundedBezel;
            self.statusView.backgroundColor = NSColor.textBackgroundColor;
            self.statusView.drawsBackground = true;
            self.statusView.needsDisplay = true;
            self.statusView.window?.makeFirstResponder(self.statusView);
        } else {
            self.statusView.isEditable = false;
            self.statusView.isEnabled = false;
            self.statusView.isBezeled = false;
            //self.statusView.drawsBackground = false;
            self.statusView.backgroundColor = NSColor.controlColor;
            self.statusView.needsDisplay = true;
        }
    }
    
    fileprivate func statusUpdated(_ status: XmppService.Status?) {
        self.statusView.stringValue = status?.message ?? "";
        let show = StatusShow.from(show: status?.show);
        let menuItem = self.statusButton.item(at: self.statusShowToMenuItem(show))!;
        self.statusButton.title = menuItem.title;
        self.statusButton.item(at: 0)?.image = StatusHelper.imageFor(status: status?.show);
        self.statusView.placeholderString = show.name ?? "";
        self.addContactButton.isEnabled = status?.show != nil;
    }
    
    fileprivate func statusShowToMenuItem(_ show: StatusShow) -> Int {
        switch show {
        case .offline:
            return 1;
        case .chat:
            return 2;
        case .online:
            return 3;
        case .away:
            return 5;
        case .xa:
            return 6;
        case .dnd:
            return 8;
        }
    }
    
    func getItem(at: Int) -> Item {
        return self.items[at];
    }
    
    @IBAction func contactDoubleClicked(_ sender: NSTableView) {
        guard sender.clickedRow >= 0 else {
            return;
        }
        let selected = self.items[sender.clickedRow];
        
        guard let client = XmppService.instance.getClient(for: selected.account) else {
            return;
        }
        
        if let chat = client.module(.message).chatManager.createChat(for: client, with: selected.jid) {
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: chat)
        }
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }

    func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
        return false;
    }
    
    func tableView(_ tableView: NSTableView, objectValueFor tableColumn: NSTableColumn?, row: Int) -> Any? {
        return items[row];
    }
    
    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        return RosterRowView();
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
//        if prevSelection >= 0 {
//            self.contactsTableView.reloadData(forRowIndexes: IndexSet(integer: prevSelection), columnIndexes: IndexSet(integer: 0));
//        }
//        if self.contactsTableView.selectedRow >= 0 {
//            self.contactsTableView.reloadData(forRowIndexes: IndexSet(integer: self.contactsTableView.selectedRow), columnIndexes: IndexSet(integer: 0));
//        }
//        prevSelection = self.contactsTableView.selectedRow;
        
//        let selectedRow = self.contactsTableView.selectedRow;
//        guard selectedRow >= 0 else {
//            return;
//        }
        
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ContactsTableContactView"), owner: nil) as? RosterContactView else {
            return nil;
        }
        
        let item = self.tableView(tableView, objectValueFor: tableColumn, row: row) as! Item;
        let colorId = row % NSColor.controlAlternatingRowBackgroundColors.count;
        print("for row", row, "got color", colorId, NSColor.controlAlternatingRowBackgroundColors);
        view.backgroundColor = NSColor.controlAlternatingRowBackgroundColors[colorId];
        view.update(with: item);
        
        return view;
    }
    
    struct Item: Hashable, Comparable {
        static func < (lhs: RosterViewController.Item, rhs: RosterViewController.Item) -> Bool {
            return lhs.displayName.lowercased() < rhs.displayName.lowercased();
        }
        
        let account: BareJID;
        let jid: BareJID;
        var displayName: String;
        var status: Presence.Show?;
                
        init(account: BareJID, jid: BareJID, name: String?, status: Presence.Show?) {
            self.account = account;
            self.jid = jid;
            self.displayName = name ?? jid.stringValue;
            self.status = status;
        }
    }
    
    enum StatusShow: Int {
        case offline = 1;
        case chat = 2;
        case online = 3;
        case away = 4;
        case xa = 5;
        case dnd = 6;
        
        var show: Presence.Show? {
            switch self {
            case .offline:
                return nil;
            case .chat:
                return Presence.Show.chat;
            case .online:
                return Presence.Show.online;
            case .away:
                return Presence.Show.away;
            case .xa:
                return Presence.Show.xa;
            case .dnd:
                return Presence.Show.dnd;
            }
        }
        
        var name: String? {
            switch self {
            case .offline:
                return "Disconnected";
            case .away, .xa:
                return "Inactive";
            default:
                return "Connected";
            }
        }
        
        static func from(show: Presence.Show?) -> StatusShow {
            guard show != nil else {
                return .offline;
            }
            switch show! {
            case .chat:
                return .chat;
            case .online:
                return .online;
            case .away:
                return .away;
            case .xa:
                return .xa;
            case .dnd:
                return .dnd;
            }
        }
    }

}

class RosterRowView: NSTableRowView {
    
//    override var backgroundColor: NSColor {
//        didSet {
//            if let contactView = self.subviews.last as? RosterContactView {
//                contactView.avatar.backgroundColor = backgroundColor;
//                contactView.refresh();
//            }
//        }
//    }

    override var isSelected: Bool {
        didSet {
            if let contactView = self.subviews.last as? RosterContactView {
                if isSelected {
                    contactView.selectedBackgroundColor = isEmphasized ? NSColor.alternateSelectedControlColor : NSColor.secondarySelectedControlColor;
                } else {
                    contactView.selectedBackgroundColor = nil;
                }
            }
        }
    }
    
    override var isEmphasized: Bool {
        didSet {
            if let contactView = self.subviews.last as? RosterContactView {
                if isSelected {
                    contactView.selectedBackgroundColor = isEmphasized ? NSColor.alternateSelectedControlColor : NSColor.secondarySelectedControlColor;
                } else {
                    contactView.selectedBackgroundColor = nil;
                }
            }
        }
    }
}

import Combine

class RosterContactView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarViewWithStatus!;
    @IBOutlet var nameAndStatus: NSTextField!;
    
    private var cancellables: Set<AnyCancellable> = [];
    private var contact: Contact? {
        didSet {
            cancellables.removeAll();
            if let contact = contact {
                contact.$displayName.combineLatest(contact.$description, $hasDarkBackground.removeDuplicates(), { (name, status, hasDarkBackground) -> NSMutableAttributedString in
                    let label = NSMutableAttributedString(string: name, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium), NSAttributedString.Key.foregroundColor: (hasDarkBackground ? NSColor.alternateSelectedControlTextColor : NSColor.textColor)]);
                    if let status = status {
                        label.append(NSAttributedString(string: "\n"));
                        label.append(NSAttributedString(string: status, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor]));
                    }
                    return label;
                }).assign(to: \.attributedStringValue, on: nameAndStatus).store(in: &cancellables);
            }
            avatar.displayableId = contact;
        }
    }
    
    fileprivate var item: RosterViewController.Item!;
    
    var selectedBackgroundColor: NSColor? {
        didSet {
            avatar.backgroundColor = selectedBackgroundColor ?? backgroundColor;
            self.hasDarkBackground = self.selectedBackgroundColor != nil && self.selectedBackgroundColor! == NSColor.alternateSelectedControlColor;
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
            avatar.backgroundColor = selectedBackgroundColor ?? backgroundColor;
            self.hasDarkBackground = self.selectedBackgroundColor != nil && self.selectedBackgroundColor! == NSColor.alternateSelectedControlColor;
        }
    }
    
    func update(with item: RosterViewController.Item) {
        self.item = item;
        self.contact = ContactManager.instance.contact(for: .init(account: item.account, jid: item.jid, type: .buddy));
    }
    
    @Published
    var hasDarkBackground: Bool = false;
    
}
