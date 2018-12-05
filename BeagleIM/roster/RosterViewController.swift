//
// RosterViewController.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift

class RosterViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
    
    @IBOutlet var statusButton: NSPopUpButton!;
    @IBOutlet var statusView: NSTextField!;
    @IBOutlet var contactsTableView: NSTableView!;
    
    @IBOutlet var contactsFilterSelector: NSSegmentedControl?;
    @IBOutlet var addContactButton: NSButton!;
    
    fileprivate var items: [Item] = [];
    fileprivate let dispatcher = QueueDispatcher(label: "roster_view");
    fileprivate var prevSelection = -1;
    fileprivate var showOnlyOnline: Bool = true {
        didSet {
            guard showOnlyOnline != oldValue else {
                return;
            }
            self.reloadData();
            self.updateContactsFilterSelector();
        }
    }
    fileprivate var selectedStatus: StatusShow?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        self.addContactButton.isEnabled = false;
        
        NotificationCenter.default.addObserver(self, selector: #selector(contactPresenceChanged(_:)), name: XmppService.CONTACT_PRESENCE_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(rosterItemUpdated), name: DBRosterStore.ITEM_UPDATED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(serviceStatusChanged), name: XmppService.STATUS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged), name: AvatarManager.AVATAR_CHANGED, object: nil);
        
        self.contactsTableView.menu?.delegate = self;
        
        statusButton.setTitle(statusButton.itemTitle(at: 1));
        
        updateContactsFilterSelector();
        
        reloadData();
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.statusUpdated(XmppService.instance.currentStatus);
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
    
    @objc func serviceStatusChanged(_ notification: Notification) {
        let status = notification.object as? XmppService.Status;
        self.statusUpdated(status);
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
        let selected = self.items[sender.clickedRow];
        
        guard let messageModule: MessageModule = XmppService.instance.getClient(for: selected.account)?.modulesManager.getModule(MessageModule.ID) else {
            return;
        }
        
        let chat = messageModule.chatManager.getChatOrCreate(with: JID(selected.jid), thread: nil);
        NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: chat)
    }
    
    func reloadData() {
        XmppService.instance.clients.values.forEach { client in
            guard let rosterModule: RosterModule = client.modulesManager.getModule(RosterModule.ID), let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) else {
                return;
            }
            
            let account = client.sessionObject.userBareJid!;
            
            (rosterModule.rosterStore as! DBRosterStoreWrapper).getJids().forEach { jid in
                guard let ri = rosterModule.rosterStore.get(for: jid) else {
                    return;
                }
                
                self.updateItem(for: jid.bareJid, on: account, name: ri.name, status: presenceModule.presenceStore.getBestPresence(for: jid.bareJid)?.show);
            }
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
    
    @objc func avatarChanged(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
            return;
        }
        
        dispatcher.async {
            let items = DispatchQueue.main.sync { return self.items };
            
            guard let currIdx = items.index(where: { i -> Bool in
                return i.jid == jid && i.account == account;
            }) else {
                return;
            }
            
            DispatchQueue.main.async {
                self.contactsTableView.reloadData(forRowIndexes: IndexSet(integer: currIdx), columnIndexes: IndexSet(integer: 0));
            }
        }
    }
    
    @objc func contactPresenceChanged(_ notification: Notification) {
        guard let e = notification.object as? PresenceModule.ContactPresenceChanged else {
            return;
        }
        
        guard let from = e.presence.from?.bareJid, let account = e.sessionObject.userBareJid else {
            return;
        }
        
        updateItem(for: from, on: account, rosterItem: nil, presence: e.presence);
    }

    @objc func rosterItemUpdated(_ notification: Notification) {
        guard let e = notification.object as? RosterModule.ItemUpdatedEvent else {
            return;
        }
        
        guard let account = e.sessionObject.userBareJid, let ri = e.rosterItem else {
            return;
        }
        
        guard e.action != .removed else {
            self.removeItem(for: ri.jid.bareJid, on: account);
            return;
        }
        
        self.updateItem(for: ri.jid.bareJid, on: account, rosterItem: ri, presence: nil);
    }
    
    fileprivate func updateItem(for jid: BareJID, on account: BareJID, rosterItem: RosterItem?, presence: Presence?) {
        dispatcher.async {
            if rosterItem == nil || presence == nil {
                guard let client = XmppService.instance.getClient(for: account) else {
                    self.removeItem(for: jid, on: account);
                    return;
                }
                guard let ri = rosterItem ?? client.rosterStore?.get(for: JID(jid)) else {
                    self.removeItem(for: jid, on: account);
                    return;
                }
                let p = presence ?? client.presenceStore?.getBestPresence(for: jid);
                self.updateItem(for: jid, on: account, name: ri.name, status: p?.show);
            } else {
                self.updateItem(for: jid, on: account, name: rosterItem!.name, status: presence!.show);
            }
        }
    }
    
    fileprivate func updateItem(for jid: BareJID, on account: BareJID, name: String?, status: Presence.Show?) {
        dispatcher.async {
            var items = DispatchQueue.main.sync { return self.items };
            
            guard let currIdx = items.index(where: { i -> Bool in
                return i.jid == jid && i.account == account;
            }) else {
                guard !self.showOnlyOnline || status != nil else {
                    return;
                }

                let idx = self.findPositionForName(items: items, jid: jid, name: name);
                items.insert(Item(account: account, jid: jid, name: name, status: status), at: idx);
                
                print("for name:", name ?? jid.stringValue, "inserting in:", items.map { i in i.name ?? i.jid.stringValue}, "at:", idx);

                DispatchQueue.main.async {
                    self.items = items;
                    self.contactsTableView.insertRows(at: IndexSet(integer: idx), withAnimation: .slideLeft);
                }

                return;
            }
            
            guard !self.showOnlyOnline || status != nil else {
                items.remove(at: currIdx);
                
                DispatchQueue.main.async {
                    self.items = items;
                    self.contactsTableView.removeRows(at: IndexSet(integer: currIdx), withAnimation: .slideRight);
                }
                return;
            }

            let item = items[currIdx];
            
            if (name ?? "") == (item.name ?? "") {
            //if (name == nil && item.name == nil) || (name != nil && name! == item.name!) {
                // here we are not changing position
                item.status = status;
                
                DispatchQueue.main.async {
                    self.contactsTableView.reloadData(forRowIndexes: IndexSet(integer: currIdx), columnIndexes: IndexSet(integer: 0));
                }
            } else {
                // we need to change position
                items.remove(at: currIdx);
                
                item.status = status;
                item.name = name;
                
                let newIdx = self.findPositionForName(items: items, jid: item.jid, name: item.name);
                
                items.insert(item, at: newIdx);
                
                DispatchQueue.main.async {
                    self.contactsTableView.reloadData(forRowIndexes: IndexSet(integer: currIdx), columnIndexes: IndexSet(integer: 0));
                    self.items = items;
                    self.contactsTableView.moveRow(at: currIdx, to: newIdx);
                }
            }
        }
    }
    
    fileprivate func removeItem(for jid: BareJID, on account: BareJID) {
        dispatcher.async {
            var items = DispatchQueue.main.sync { return self.items; };
            guard let currIdx = items.index(where: { i -> Bool in
                return i.jid == jid && i.account == account;
            }) else {
                return;
            }
            items.remove(at: currIdx);
            
            DispatchQueue.main.async {
                self.items = items;
                self.contactsTableView.removeRows(at: IndexSet(integer: currIdx), withAnimation: .slideRight);
            }
        }
    }
    
    func findPositionForName(items: [Item], jid: BareJID, name: String?) -> Int {
        let newName = name ?? jid.stringValue;
        return items.index(where: { (i) -> Bool in
            let n = i.name ?? i.jid.stringValue;
            switch newName.localizedCaseInsensitiveCompare(n) {
            case .orderedDescending:
                return false;
            case .orderedAscending:
                return true;
            case .orderedSame:
                return false;
            }
        }) ?? items.count;
    }
    
    class Item {
        let account: BareJID;
        let jid: BareJID;
        var name: String?;
        var status: Presence.Show?;
        
        
        
        init(account: BareJID, jid: BareJID, name: String?, status: Presence.Show?) {
            self.account = account;
            self.jid = jid;
            self.name = name;
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

class RosterContactView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarViewWithStatus!;
    @IBOutlet var nameAndStatus: NSTextField!;
    
    fileprivate var item: RosterViewController.Item!;
    
    var selectedBackgroundColor: NSColor? {
        didSet {
            avatar.backgroundColor = selectedBackgroundColor ?? backgroundColor;
            self.refresh();
        }
    }
    
    var backgroundColor: NSColor? {
        didSet {
            avatar.backgroundColor = selectedBackgroundColor ?? backgroundColor;
            self.refresh();
        }
    }
    
    func update(with item: RosterViewController.Item) {
        self.item = item;
        avatar.update(for: item.jid, on: item.account);
        self.refresh();
    }
    
    func refresh() {
        guard item != nil, let modulesManager = XmppService.instance.getClient(for: self.item.account)?.modulesManager else {
            return;
        }
        
        guard let presenceModule: PresenceModule = modulesManager.getModule(PresenceModule.ID) else {
            return;
        }
        
        let name = self.item.name ?? self.item.jid.stringValue;
        
        let darkBackground = self.selectedBackgroundColor != nil && self.selectedBackgroundColor! == NSColor.alternateSelectedControlColor;//self.backgroundStyle == .dark;
        
        let label = NSMutableAttributedString(string: name, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium), NSAttributedString.Key.foregroundColor: (darkBackground ? NSColor.alternateSelectedControlTextColor : NSColor.textColor)]);
        
        let status = presenceModule.presenceStore.getBestPresence(for: self.item.jid)?.status;
        if status != nil && !status!.isEmpty {
            label.append(NSAttributedString(string: "\n"));
//            label.append(NSAttributedString(string: status!, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), NSAttributedString.Key.foregroundColor: (darkBackground ? NSColor.lightGray : NSColor.darkGray)]));
            label.append(NSAttributedString(string: status!, attributes: [NSAttributedString.Key.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor]));
        }
        
        nameAndStatus.attributedStringValue = label;
    }
}
