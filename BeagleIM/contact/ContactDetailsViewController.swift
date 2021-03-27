//
// ContactDetailsViewController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

open class ContactDetailsViewController: NSViewController, ContactDetailsAccountJidAware {

    var account: BareJID?;
    var jid: BareJID?;

    @IBOutlet var basicContainerView: NSView!;
    @IBOutlet var tabs: NSSegmentedControl!;
    @IBOutlet var tabsView: NSTabView!;
    
    var showSettings: Bool {
        return viewType != .contact;
    }
    var viewType: ViewType = .contact;
    
    var basicViewController: ConversationDetailsViewController? {
        didSet {
            basicViewController?.account = self.account;
            basicViewController?.jid = self.jid;
            basicViewController?.showSettings = self.showSettings;
        }
    }
    
    open override func viewWillAppear() {
        if viewType != .groupchat {
            self.tabsView.addTabViewItem(NSTabViewItem(viewController: self.storyboard!.instantiateController(withIdentifier: "ConversationVCardViewController") as! NSViewController));
        }
        let tab = NSTabViewItem(viewController: self.storyboard!.instantiateController(withIdentifier: "ConversationAttachmentsViewController") as! NSViewController);
        tab.label = "Attachments"
        self.tabsView.addTabViewItem(tab);
        if viewType != .groupchat {
            self.tabsView.addTabViewItem(NSTabViewItem(viewController: self.storyboard!.instantiateController(withIdentifier: "ConversationOmemoViewController") as! NSViewController))
        }
        
        basicViewController?.account = self.account;
        basicViewController?.jid = self.jid;
        basicViewController?.showSettings = self.showSettings;
        
        self.tabs.segmentCount = self.tabsView.tabViewItems.count;
        var i = 0;
        self.tabsView.tabViewItems.forEach { (item) in
            self.tabs.setLabel(item.label, forSegment: i);
            i = i + 1;
            if let aware = item.viewController as? ContactDetailsAccountJidAware {
                aware.account = self.account;
                aware.jid = self.jid;
            }
        }
        super.viewWillAppear();
        self.tabs.setSelected(true, forSegment: 0);
    }
    
    @IBAction func tabChanged(_ sender: NSSegmentedControl) {
        self.tabsView.selectTabViewItem(at: sender.selectedSegment);
    }
    
    open override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "ConversationDetailsViewController" {
            self.basicViewController = segue.destinationController as? ConversationDetailsViewController;
        }
    }
    
    enum ViewType {
        case contact
        case chat
        case groupchat
    }
}

open class ConversationDetailsViewController: NSViewController, ContactDetailsAccountJidAware {
    
    var account: BareJID?;
    var jid: BareJID?;
    
    @IBOutlet var nameField: NSTextField!;
    @IBOutlet var jidField: NSTextField!;
    @IBOutlet var avatarView: AvatarView!;
    
    @IBOutlet var settingsContainerView: NSView!
    @IBOutlet var settingsContainerViewHeightConstraint: NSLayoutConstraint?
    
    var settingsViewController: ConversationSettingsViewController? {
        didSet {
            settingsViewController?.account = self.account;
            settingsViewController?.jid = self.jid;
        }
    }
    
    var showSettings: Bool = false;
    
    open override func viewWillAppear() {
        nameField.stringValue = jid?.stringValue ?? "";
        //nameField.focusRingType = .none;
        jidField.stringValue = jid?.stringValue ?? "";
        if let jid = self.jid, let account = self.account {
            avatarView.image = AvatarManager.instance.avatar(for: jid, on: account);
            if let channel = DBChatStore.instance.conversation(for: account, with: jid) as? Channel {
                if let name = channel.name {
                    nameField.stringValue = name;
                }
            } else {
            DBVCardStore.instance.vcard(for: jid) { (vcard) in
                DispatchQueue.main.async {
                    var fn: String = "";
                    if let fn1 = vcard?.fn, !fn1.isEmpty {
                        fn = fn1;
                    } else {
                        if let given = vcard?.givenName, !given.isEmpty {
                            fn = given;
                        }
                        if let surname = vcard?.surname, !surname.isEmpty {
                            fn = fn.isEmpty ? surname : "\(fn) \(surname)"
                        }
                        if fn.isEmpty {
                            fn = DBRosterStore.instance.item(for: account, jid: JID(jid))?.name ?? jid.stringValue;
                        }
                    }
                    self.nameField.stringValue = fn;
                }
            }
            }
        }
        settingsContainerView.isHidden = !showSettings;
        settingsContainerViewHeightConstraint?.isActive = !showSettings;
        settingsViewController?.account = self.account;
        settingsViewController?.jid = self.jid;
        super.viewWillAppear();
        self.view.layout();
    }
    
    open override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "PrepareConversationSettingsViewController" {
            self.settingsViewController = segue.destinationController as? ConversationSettingsViewController;
            self.settingsViewController?.superView = self.settingsContainerView;
        }
    }
}

open class ConversationSettingsViewController: NSViewController, ContactDetailsAccountJidAware {
 
    var account: BareJID?
    var jid: BareJID?
    
    var chat: Conversation?;
    
    weak var superView: NSView?;
    
    var muteNotifications: NSButton?;
    var blockContact: NSButton?;
    var confirmMessages: NSButton?;
    
    open override func viewWillAppear() {
        super.viewWillAppear();
        if let account = self.account, let jid = self.jid {
            chat = DBChatStore.instance.conversation(for: account, with: jid);
        }
        var rows: [NSView] = [];
        if let chat = self.chat {
            muteNotifications = NSButton(checkboxWithTitle: "Mute notifications", target: self, action: #selector(muteNotificationsChanged));
            rows.append(muteNotifications!);

            switch chat {
            case let r as Room:
                muteNotifications?.state = r.options.notifications == .none ? .on : .off;
            case let c as Chat:
                muteNotifications?.state = c.options.notifications == .none ? .on : .off;
                if let client = chat.context {
                    blockContact = NSButton(checkboxWithTitle: "Block contact", target: self, action: #selector(blockContactChanged));
                    rows.append(blockContact!);
                    blockContact?.state = BlockedEventHandler.isBlocked(JID(c.jid), on: client) ? .on : .off;
                    blockContact?.isEnabled = client.module(.blockingCommand).isAvailable;
                }
                if DBRosterStore.instance.item(for: chat.account, jid: JID(chat.jid)) == nil {
                    let button = NSButton(title: "Add to contacts", image: NSImage(named: NSImage.addTemplateName)!, target: self, action: #selector(self.addToRoster(_:)));
                    button.isBordered = false;
                    rows.append(button);
                }
            default:
                break;
            }
            
            if Settings.confirmMessages && chat.canSendChatMarker() {
                confirmMessages = NSButton(checkboxWithTitle: "Confirm messages", target: self, action: #selector(confirmMessagesChanged));
                switch chat {
                case let chat as Chat:
                    confirmMessages?.toolTip = "Disabling will disable syncing information about read messages between your devices!";
                    confirmMessages?.state = chat.options.confirmMessages ? .on : .off;
                case let room as Room:
                    confirmMessages?.state = room.options.confirmMessages ? .on : .off;
                case let channel as Channel:
                    confirmMessages?.state = channel.options.confirmMessages ? .on : .off;
                default:
                    break;
                }
                confirmMessages?.isEnabled = chat.canSendChatMarker();
                rows.append(confirmMessages!);
            }
        }

        setRows(rows);
        
        superView?.heightAnchor.constraint(equalToConstant: self.view.fittingSize.height).isActive = true;
        
        print("got:", account as Any, "and:", jid as Any);
    }
        
    private func setRows(_ rows: [NSView]) {
        if !rows.isEmpty {
            var constraints: [NSLayoutConstraint] = [];
            rows.enumerated().forEach() { index, row in
                row.translatesAutoresizingMaskIntoConstraints = false;
            
                let divider = NSBox();
                divider.translatesAutoresizingMaskIntoConstraints = false;
                divider.title = "Separator \(index)";
                divider.boxType = .separator;
                view.addSubview(divider);
                constraints.append(view.leadingAnchor.constraint(equalTo: divider.leadingAnchor));
                constraints.append(view.trailingAnchor.constraint(equalTo: divider.trailingAnchor));
                if index == 0 {
                    constraints.append(view.topAnchor.constraint(equalTo: divider.topAnchor, constant: -4));
                } else {
                    constraints.append(rows[index-1].bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -8));
                }
            
                view.addSubview(row);
                constraints.append(view.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: -4));
                constraints.append(view.trailingAnchor.constraint(greaterThanOrEqualTo: row.trailingAnchor, constant: 4));
                constraints.append(divider.bottomAnchor.constraint(equalTo: row.topAnchor, constant: -8))
            }
            constraints.append(view.bottomAnchor.constraint(equalTo: rows.last!.bottomAnchor, constant: 4));
            
            NSLayoutConstraint.activate(constraints);
        }
    }
    
    @objc func muteNotificationsChanged(_ sender: NSButton) {
        let state = sender.state == .on;
        if let chat = self.chat as? Chat {
            chat.updateOptions({ (options) in
                options.notifications = state ? .none : .always;
            });
        }
        if let room = self.chat as? Room {
            room.updateOptions({ (options) in
                options.notifications = state ? .none : .mention;
            });
        }
    }
    
    @objc func confirmMessagesChanged(_ sender: NSButton) {
        let state = sender.state == .on;
        if let conv = self.chat {
            switch conv {
            case let chat as Chat:
                chat.updateOptions({ options in
                    options.confirmMessages = state;
                })
            case let room as Room:
                room.updateOptions({ options in
                    options.confirmMessages = state;
                })
            case let channel as Channel:
                channel.updateOptions({ options in
                    options.confirmMessages = state;
                })
            default:
                break;
            }
        }
    }
    
    @objc func blockContactChanged(_ sender: NSButton) {
        if let chat = self.chat as? Chat, let context = chat.context {
            if sender.state == .on {
                context.module(.blockingCommand).block(jids: [JID(chat.jid)], completionHandler: { [weak sender] result in
                    DispatchQueue.main.async {
                        switch result {
                        case .failure(_):
                            sender?.state = .off;
                        default:
                            break;
                        }
                    }
                })
            } else {
                context.module(.blockingCommand).unblock(jids: [JID(chat.jid)], completionHandler: { [weak sender] result in
                    DispatchQueue.main.async {
                        switch result {
                        case .failure(_):
                            sender?.state = .on;
                        default:
                            break;
                        }
                    }
                })
            }
        }
    }
    
    @objc func addToRoster(_ sender: Any) {
        guard let parent = self.view.window?.parent, let chat = self.chat as? Chat else {
            return;
        }
        self.view.window?.close();
        if let addContactController = NSStoryboard(name: "Roster", bundle: nil).instantiateController(withIdentifier: "AddContactController") as? AddContactController {
            _ = addContactController.view;
            addContactController.jidField.stringValue = chat.jid.stringValue;
            DBVCardStore.instance.vcard(for: chat.jid) { (vcard) in
                DispatchQueue.main.async {
                    var fn: String = "";
                    if let fn1 = vcard?.fn, !fn1.isEmpty {
                        fn = fn1;
                    } else {
                        if let given = vcard?.givenName, !given.isEmpty {
                            fn = given;
                        }
                        if let surname = vcard?.surname, !surname.isEmpty {
                            fn = fn.isEmpty ? surname : "\(fn) \(surname)"
                        }
                    }
                    if let idx = addContactController.accountSelector.itemTitles.firstIndex(of: chat.account.stringValue) {
                        addContactController.accountSelector.selectItem(at: idx);
                    }
                    if fn.isEmpty {
                        addContactController.labelField.stringValue = chat.jid.localPart ?? chat.jid.stringValue;
                    } else {
                        addContactController.labelField.stringValue = fn;
                    }
                    let window = NSWindow(contentViewController: addContactController);
                    parent.beginSheet(window, completionHandler: nil);
                }
            }
        }
    }
    
}

open class ConversationOmemoViewController: NSViewController, ContactDetailsAccountJidAware {
    
    var account: BareJID?
    var jid: BareJID?
    
    var identities: [Identity] = [] {
        didSet {
            self.removeAllRows();
            self.identities.forEach { (identity) in
                let view = IdentityView(identity: identity, account: self.account!);
                self.addRow(view);
            }
        }
    }
    
    @IBOutlet var stack: NSStackView!;
    
    open override func viewWillAppear() {
        super.viewWillAppear();
        guard let jid = self.jid, let account = self.account else {
            return;
        }
        
        self.identities = DBOMEMOStore.instance.identities(forAccount: account, andName: jid.stringValue).filter({ (identity) -> Bool in
            return identity.status.isActive;
        })
    }
    
    func addRow(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = false;
        view.setContentHuggingPriority(.defaultLow, for: .vertical);
        view.setContentHuggingPriority(.required, for: .horizontal);
        stack.addArrangedSubview(view);
    }
    
    func addSeparator() {
        let separator = NSBox(frame: .zero);
        separator.boxType = .separator;
        stack.addArrangedSubview(separator);
    }
    
    func removeAllRows() {
        let subviews = stack.subviews;
        subviews.forEach { (view) in
                //stack.removeArrangedSubview(view);
            view.removeFromSuperview();
        }
    }
}

class IdentityView: NSView {
    
    let identity: Identity;
    let account: BareJID;
    
    let fingerprintView: NSTextField;
    let statusButton: NSPopUpButton;
    
    init(identity: Identity, account: BareJID) {
        self.account = account;
        self.identity = identity;
        fingerprintView = NSTextField(wrappingLabelWithString: IdentityView.prettify(fingerprint: String(identity.fingerprint.dropFirst(2))));
        fingerprintView.translatesAutoresizingMaskIntoConstraints = false;
        fingerprintView.setContentHuggingPriority(.required, for: .horizontal);
        fingerprintView.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize - 1);
        statusButton = NSPopUpButton(image: NSImage(named: NSImage.lockLockedTemplateName)!, target: nil, action: #selector(trustChanged(_:)));
        statusButton.imagePosition = .imageOnly;
        //                statusButton.widthAnchor.constraint(equalToConstant: 20).isActive = true;
        statusButton.translatesAutoresizingMaskIntoConstraints = false;
        statusButton.isTransparent = false;
        statusButton.isBordered = false;
        super.init(frame: .zero);
        statusButton.target = self;
        self.autoresizingMask = [.width, .height];
        self.autoresizesSubviews = true;
        //                self.translatesAutoresizingMaskIntoConstraints = false;
        self.addSubview(fingerprintView);
        self.addSubview(statusButton);
        self.topAnchor.constraint(equalTo: fingerprintView.topAnchor).isActive = true;
        self.leftAnchor.constraint(equalTo: fingerprintView.leftAnchor).isActive = true;
        self.bottomAnchor.constraint(equalTo: fingerprintView.bottomAnchor).isActive = true;
        //                self.topAnchor.constraint(equalTo:statusButton.topAnchor).isActive = true;
        //                self.bottomAnchor.constraint(equalTo:statusButton.bottomAnchor).isActive = true;
        statusButton.centerYAnchor.constraint(equalTo: fingerprintView.centerYAnchor).isActive = true;
        statusButton.leftAnchor.constraint(equalTo: fingerprintView.rightAnchor, constant: 2.0).isActive = true;
        self.rightAnchor.constraint(equalTo: statusButton.rightAnchor).isActive = true;
        
        let arr: [Trust] = [.trusted, .verified, .compromised, .undecided];
        arr.forEach { (trust) in
            var title = "Test";
            switch trust {
            case .trusted:
                title = "Trusted";
            case .verified:
                title = "Verified";
            case .compromised:
                title = "Compromised";
            case .undecided:
                title = "Undecided";
            }
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "");
            switch trust {
            case .trusted:
                item.image = NSImage(named: NSImage.lockLockedTemplateName);
            case .verified:
                item.image = NSImage(named: NSImage.lockLockedTemplateName);
            case .undecided:
                item.image = NSImage(named: NSImage.lockUnlockedTemplateName);
            case .compromised:
                item.image = NSImage(named: NSImage.stopProgressTemplateName);
            }
            statusButton.menu?.addItem(item);
        }
        print("identity:", identity.fingerprint, "trust:", identity.status.trust);
        switch identity.status.trust {
        case .trusted:
            statusButton.selectItem(at: 0);
        case .verified:
            statusButton.selectItem(at: 1);
        case .compromised:
            statusButton.selectItem(at: 2);
        case .undecided:
            statusButton.selectItem(at: 3);
        }
        self.fingerprintView.textColor = identity.status.trust == .compromised ? NSColor.systemRed : NSColor.labelColor;
    }
    
    @objc func trustChanged(_ sender: NSPopUpButton) {
        var trust: Trust = .undecided;
        switch sender.indexOfSelectedItem {
        case 0:
            trust = .trusted;
        case 1:
            trust = .verified;
        case 2:
            trust = .compromised;
        default:
            trust = .undecided;
        }
        print("selected:", sender.indexOfSelectedItem, "trust:", trust);
        _ = DBOMEMOStore.instance.setStatus(identity.status.toTrust(trust), forIdentity: identity.address, andAccount: self.account);
        self.fingerprintView.textColor = trust == .compromised ? NSColor.systemRed : NSColor.labelColor;
    }
    
    required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    override func resize(withOldSuperviewSize oldSize: NSSize) {
//        print("oldSize:", oldSize, "newSize:", self.frame.size);
//        super.resize(withOldSuperviewSize: oldSize);
//    }
//
//    override func resizeSubviews(withOldSize oldSize: NSSize) {
//        self.needsLayout = true;
//        super.resizeSubviews(withOldSize: oldSize);
//    }
    
//    override func layout() {
//        fingerprintView.preferredMaxLayoutWidth = 0;
//        super.layout();
//        fingerprintView.preferredMaxLayoutWidth = fingerprintView.frame.size.width;//self.frame.size.width - (4.0 + statusButton.frame.width);
//        self.needsLayout = true;
//        print("width:", self.frame.size.width, "preferred:", fingerprintView.preferredMaxLayoutWidth)
//        super.layout();
//        print("w1:", fingerprintView.frame.size, "w2:", statusButton.frame.size)
//    }
    
    static func prettify(fingerprint tmp: String) -> String {
        var fingerprint = tmp;
        var idx = fingerprint.startIndex;
        for _ in 0..<(fingerprint.count / 8) {
            idx = fingerprint.index(idx, offsetBy: 8);
            fingerprint.insert(" ", at: idx);
            idx = fingerprint.index(after: idx);
        }
        return fingerprint;
    }
    
}

class ConversationVCardViewController: NSViewController, ContactDetailsAccountJidAware {
    
    var account: BareJID?
    var jid: BareJID?
    
    @IBOutlet var stack: NSStackView!;

    private var vcard: VCard? {
        didSet {
            updateDisplayedValue();
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        _ = self.view;
        if let jid = self.jid {
            DBVCardStore.instance.vcard(for: jid) { (vcard) in
                DispatchQueue.main.async {
                    self.vcard = vcard;
                }
            }
        }
    }
        
    private func updateDisplayedValue() {
        let views = self.stack.arrangedSubviews;
        views.forEach { (view) in
            self.stack.removeView(view);
        }
        
        guard let jid = self.jid, let account = self.account else {
            return;
        }
        
        var fn: String = "";
        if let fn1 = vcard?.fn, !fn1.isEmpty {
            fn = fn1;
        } else {
            if let given = vcard?.givenName, !given.isEmpty {
                fn = given;
            }
            if let surname = vcard?.surname, !surname.isEmpty {
                fn = fn.isEmpty ? surname : "\(fn) \(surname)"
            }
            if fn.isEmpty {
                fn = DBRosterStore.instance.item(for: account, jid: JID(jid))?.name ?? jid.stringValue;
            }
        }
        let name = NSTextField(wrappingLabelWithString: fn);
        name.font = NSFont.boldSystemFont(ofSize: NSFont.systemFontSize);
        name.setContentCompressionResistancePriority(.required, for: .vertical);
        name.setContentHuggingPriority(.required, for: .horizontal);
        name.translatesAutoresizingMaskIntoConstraints = false;
        let refresh = NSButton(image: NSImage(named: NSImage.refreshTemplateName)!, target: self, action: #selector(self.refreshVCard));
        refresh.widthAnchor.constraint(equalToConstant: 16).isActive = true;
        refresh.heightAnchor.constraint(equalToConstant: 16).isActive = true;
        refresh.translatesAutoresizingMaskIntoConstraints = false;
        refresh.isBordered = false;
        let vbox = NSView(frame: .zero);
        vbox.setContentCompressionResistancePriority(.required, for: .vertical);
        vbox.setContentHuggingPriority(.required, for: .horizontal);
        vbox.translatesAutoresizingMaskIntoConstraints = true;
        vbox.autoresizingMask = [.width, .height];
        vbox.autoresizesSubviews = true;
        vbox.addSubview(name);
        vbox.addSubview(refresh);
        vbox.leftAnchor.constraint(equalTo: name.leftAnchor).isActive = true;
        vbox.rightAnchor.constraint(equalTo: refresh.rightAnchor).isActive = true;
        vbox.topAnchor.constraint(equalTo: refresh.topAnchor).isActive = true;
        vbox.bottomAnchor.constraint(equalTo: refresh.bottomAnchor).isActive = true;
        name.centerYAnchor.constraint(equalTo: refresh.centerYAnchor).isActive = true;
        refresh.leftAnchor.constraint(greaterThanOrEqualTo: name.rightAnchor, constant: 8.0).isActive = true;
        
        self.stack.addArrangedSubview(vbox);
        
        var line = vcard?.role;
        if let org = vcard?.organizations.first?.name, !org.isEmpty {
            line = (line?.isEmpty ?? true) ? org : "\(line!) at \(org)"
        }

        if line != nil {
            let roleAndCompany = NSTextField(wrappingLabelWithString: line!);
            roleAndCompany.setContentCompressionResistancePriority(.required, for: .vertical);
            roleAndCompany.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2, weight: .medium);
            self.stack.addArrangedSubview(roleAndCompany);
        }
        
        if let phones = vcard?.telephones.filter({ !$0.isEmpty }).filter({ $0.uri != "null" && $0.number != "null"  }), !phones.isEmpty {
            let label = NSTextField(labelWithString: "Telephone")
            label.setContentCompressionResistancePriority(.required, for: .vertical);
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium);
            label.textColor = NSColor.secondaryLabelColor;
            self.stack.addArrangedSubview(label);
            for phone in phones {
                self.add(phone: phone);
            }
        }
        if let emails = vcard?.emails.filter({ !$0.isEmpty }).filter({ $0.address != "null" }), !emails.isEmpty {
            let label = NSTextField(labelWithString: "Emails")
            label.setContentCompressionResistancePriority(.required, for: .vertical);
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium);
            label.textColor = NSColor.secondaryLabelColor;
            self.stack.addArrangedSubview(label);
            for email in emails {
                self.add(email: email);
            }
        }
        if let addresses = vcard?.addresses, !addresses.isEmpty {
            let label = NSTextField(labelWithString: "Addresses");
            label.setContentCompressionResistancePriority(.required, for: .vertical);
            label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium);
            label.textColor = NSColor.secondaryLabelColor;
            self.stack.addArrangedSubview(label);
            for addr in addresses {
                self.add(address: addr);
            }
        }
    }
    
    @objc func refreshVCard(_ sender: NSButton) {
        guard let jid = self.jid, let account = self.account else {
            return;
        }
        var retrievedVCard: VCard? = nil;
        let group = DispatchGroup();
        group.enter();
        VCardManager.instance.refreshVCard(for: jid, on: account) { (result) in
            switch result {
            case .success(let vcard):
                DispatchQueue.main.async {
                    if retrievedVCard == nil {
                        retrievedVCard = vcard;
                    }
                }
            default:
                break;
            }
            group.leave();
        }
        group.enter();
        PrivateVCard4Helper.retrieve(on: account, from: jid, completionHandler: { result in
            switch result {
            case .success(let vcard):
                DispatchQueue.main.async {
                    retrievedVCard = vcard;
                }
            case .failure(_):
                break;
            }
            group.leave();
        })
        group.notify(queue: DispatchQueue.main, execute: {
            if let vcard = retrievedVCard {
                self.vcard = vcard;
            } else {
                DBVCardStore.instance.vcard(for: jid) { (vcard) in
                    DispatchQueue.main.async {
                        self.vcard = vcard;
                    }
                }
            }
        })
    }
    
    func add(address addr: VCard.Address) {
        var str = "";
        if let street = addr.street, !street.isEmpty {
            str = street;
        }
        let locality = addr.locality;
        let postalCode = addr.postalCode;
        if locality != nil || postalCode != nil {
            if locality != nil && postalCode != nil {
                str = str.isEmpty ? (locality!) : "\(str), \(postalCode!) \(locality!)"
            } else {
                if locality != nil {
                    str = str.isEmpty ? (locality!) : "\(str), \(locality!)"
                }
            }
        }
        if let region = addr.region, !region.isEmpty {
            str = str.isEmpty ? region : "\(str), \(region)";
        }
        if let country = addr.country, !country.isEmpty {
            str = str.isEmpty ? country : "\(str), \(country)"
        }
        
        var parts = URLComponents();
        parts.scheme = "http";
        parts.host = "maps.apple.com";
        parts.queryItems = [ URLQueryItem(name: "q", value: str.replacingOccurrences(of: ", ", with: ",")) ];
        
        let field = prepareValueLabel(text: str, url: parts.url);
        self.addRow(label: (addr.types.first ?? .home) == .home ? "Home" : "Work", valueField: field);
    }
    
    func add(email: VCard.Email) {
        guard var address = email.address, !address.isEmpty else {
            return;
        }
        
        var label = address;
        if !address.starts(with: "mailto:") {
            address = "mailto:\(address)";
        } else {
            if let idx = label.firstIndex(of: ":") {
                label = String(label.suffix(from: label.index(after: idx)));
            }
        }
        
        let field = prepareValueLabel(text: label, url: URL(string: address));
        addRow(label: (email.types.first ?? .home) == .home ? "Home" : "Work", valueField: field);
    }
    
    func add(phone: VCard.Telephone) {
        guard let uri = phone.uri, !uri.isEmpty, let number = phone.number else {
            return;
        }
        let field = prepareValueLabel(text: number, url: URL(string: uri.replacingOccurrences(of: " ", with: "-")));
        addRow(label: (phone.types.first ?? .home) == .home ? "Home" : "Work", valueField: field);
    }
    
    func prepareValueLabel(text: String, url: URL?) -> NSTextField {
        let value = NSTextField(wrappingLabelWithString: text);
        value.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2.0);
        value.setContentHuggingPriority(.defaultLow, for: .vertical);
        value.setContentHuggingPriority(.defaultLow, for: .horizontal);
        value.allowsEditingTextAttributes = true;
        value.isSelectable = true;
        if let url = url {
            value.attributedStringValue = NSAttributedString(string: text, attributes: [.link : url]);
        }
        return value;
    }
    
    func addRow(label text: String, valueField: NSTextField) {
        let label = NSTextField(labelWithString: text);
        label.setContentHuggingPriority(.defaultLow, for: .vertical);
        label.setContentHuggingPriority(.defaultLow, for: .horizontal);
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2.0, weight: .bold);
        label.textColor = NSColor.secondaryLabelColor;
        
        let row = NSStackView(views: [label, valueField]);
        row.setContentHuggingPriority(.defaultLow, for: .vertical);
        row.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        row.orientation = .horizontal;
        self.stack.addArrangedSubview(row);
    }
}

class CustomNSStackView: NSStackView {
    
//    private var _intrinsicContentSize: NSSize? = nil;
//    
//    override var intrinsicContentSize: NSSize {
//        if _intrinsicContentSize == nil {
//            return super.intrinsicContentSize;
//        }
//        return _intrinsicContentSize!;
//    }
//    
//    override func invalidateIntrinsicContentSize() {
//        super.invalidateIntrinsicContentSize();
//        _intrinsicContentSize = NSSize(width: super.intrinsicContentSize.width, height: self.fittingSize.height);
//    }
    
}

class ConversationGroupingViewController: NSViewController, ContactDetailsAccountJidAware {
    
    var account: BareJID?
    var jid: BareJID?
    
    @IBOutlet var stack: NSStackView!;
    
    fileprivate var controllers: [NSViewController] = [];
    
    func add(viewController: NSViewController) {
        controllers.append(viewController);
    }
    
    override func viewWillAppear() {
        controllers.forEach { (controller) in
            if let aware = controller as? ContactDetailsAccountJidAware {
                aware.account = self.account;
                aware.jid = self.jid;
            }
            if self.stack.arrangedSubviews.isEmpty {
                let separator = NSBox(frame: .zero);
                separator.boxType = .separator;
                stack.addArrangedSubview(separator);
            }
            controller.view.setContentHuggingPriority(.required, for: .horizontal);
            controller.view.translatesAutoresizingMaskIntoConstraints = false;
            stack.addArrangedSubview(controller.view);
            controller.viewWillAppear();
        }
        super.viewWillAppear();
    }
    
    override func viewWillDisappear() {
        let views = self.stack.arrangedSubviews;
        views.forEach { (view) in
            self.stack.removeView(view);
        }
        controllers.forEach { (controller) in
            controller.viewWillDisappear();
        }
    }
    
}

protocol ContactDetailsAccountJidAware: class {
    var account: BareJID? { get set }
    var jid: BareJID? { get set }
}

open class ContactDetailsViewController1: NSViewController, NSTableViewDelegate {

    @IBOutlet var name: NSTextField!;
    @IBOutlet var roleAndCompany: NSTextField!;
    @IBOutlet var addressesLabel: NSTextField!;
    @IBOutlet var addresses: NSGridView!;
    @IBOutlet var identitiesTableView: OMEMOIdentitiesTableView!;

    @IBOutlet var roleAndCompanyTopSpacing: NSLayoutConstraint!;
    var roleAndCompanyHeight: NSLayoutConstraint?;
    var addressesLabelHeight: NSLayoutConstraint?;
    
    var account: BareJID!;
    var jid: BareJID!;
    
    open override func viewDidLoad() {
//        self.addresses.removeRow(at: 0);
        self.identitiesTableView.delegate = self;
        self.roleAndCompanyHeight = roleAndCompany.heightAnchor.constraint(equalToConstant: 0);
        self.addressesLabelHeight = addressesLabel.heightAnchor.constraint(equalToConstant: 0);
    }
    
    open override func viewWillAppear() {
        refresh();
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identity = identitiesTableView.identities[row];
        
        switch tableView.column(withIdentifier: tableColumn!.identifier) {
        case 1:
            guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ContactViewOMEMOTrustCellView"), owner: nil) as? NSTableCellView else {
                return nil;
            }
            
            var idx = 0;
            switch identity.status.trust {
            case .undecided:
                idx = 0;
            case .trusted:
                idx = 1;
            case .verified:
                idx = 2;
            case .compromised:
                idx = 3;
            }
            if let button = cell.subviews.first as? NSPopUpButton {
                button.isEnabled = identity.status.isActive;
                button.tag = row;
                button.target = self;
                button.action = #selector(trustChanged);
                let color = identity.status.trust == .compromised ? NSColor.systemRed : (identity.status.isActive ? NSColor.labelColor : NSColor.secondaryLabelColor);
                button.contentTintColor = color;
                button.selectItem(at: idx);
                button.synchronizeTitleAndSelectedItem();
            }
            return cell;
        default:
            guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ContactViewOMEMOFingerprintCellView"), owner: nil) as? NSTableCellView else {
                return nil;
            }
            
            cell.textField?.textColor = identity.status.trust == .compromised ? NSColor.systemRed : (identity.status.isActive ? NSColor.labelColor : NSColor.secondaryLabelColor);
            cell.textField?.stringValue = identitiesTableView.prettify(fingerprint: String(identity.fingerprint.dropFirst(2)));
            
            return cell;
        }
    }
    
    func refresh() {
        identitiesTableView.identities = DBOMEMOStore.instance.identities(forAccount: account!, andName: jid!.stringValue);
        DBVCardStore.instance.vcard(for: jid) { (vcard) in
            DispatchQueue.main.async {
                var fn: String = "";
                if let fn1 = vcard?.fn, !fn1.isEmpty {
                    fn = fn1;
                } else {
                    if let given = vcard?.givenName, !given.isEmpty {
                        fn = given;
                    }
                    if let surname = vcard?.surname, !surname.isEmpty {
                        fn = fn.isEmpty ? surname : "\(fn) \(surname)"
                    }
                    if fn.isEmpty {
                        fn = DBRosterStore.instance.item(for: self.account, jid: JID(self.jid))?.name ?? self.jid.stringValue;
                    }
                }
                self.name.stringValue = fn;
                
//                let details = NSMutableAttributedString(string: fn);
//                details.addAttribute(.font, value: NSFont(descriptor: self.name.font!.fontDescriptor, size: NSFont.labelFontSize + 2.0)!, range: NSRange(location: 0, length: details.length));
//                details.applyFontTraits(.boldFontMask, range: NSRange(location: 0, length: details.length));
                
                var line = vcard?.role;
                if let org = vcard?.organizations.first?.name, !org.isEmpty {
                    line = (line?.isEmpty ?? true) ? org : "\(line!) at \(org)"
                }
//                if !(line?.isEmpty ?? true) {
//                    details.append(NSAttributedString(string: "\n"));
//                    details.append(NSAttributedString(string: line!));
//                }

                self.roleAndCompany.stringValue = line ?? "";
                self.roleAndCompanyHeight?.isActive = line?.isEmpty ?? true;
                self.roleAndCompanyTopSpacing.constant = (line?.isEmpty ?? true) ? 0.0 : 4.0;
                
                self.addressesLabelHeight?.isActive = vcard?.addresses.filter({ (a) -> Bool in
                    return !a.isEmpty
                }).isEmpty ?? true;
                
                if vcard != nil {
                    if self.addresses.numberOfRows > 1 {
                        for _ in 0..<(self.addresses!.numberOfRows-1) {
                            self.addresses.removeRow(at: 0);
                        }
                    }
                    for addr in vcard!.addresses.filter({ (a) -> Bool in
                        return !a.isEmpty;
                    }) {
                        self.add(address: addr);
//                        self.add(address: addr);
                    }
//                    if self.addresses.numberOfRows == 0 {
//                        self.addresses.addRow(with: [NSGridCell.emptyContentView]);
//                    }
                    self.addresses.needsLayout = true;
                    self.addresses.layout();
                }
//                self.name.attributedStringValue = details;
            }
        }
    }
    
    fileprivate func add(address addr: VCard.Address) {
        let label = NSTextField(labelWithString: (addr.types.first ?? .home) == .home ? "Home" : "Work");
        label.setContentHuggingPriority(.defaultLow, for: .vertical);
        label.setContentHuggingPriority(.defaultLow, for: .horizontal);
        label.font = NSFont(descriptor: self.roleAndCompany.font!.fontDescriptor.withSymbolicTraits(.bold), size: NSFont.systemFontSize - 2.0)
        
        var str = "";
        if let street = addr.street, !street.isEmpty {
            str = street;
        }
        let locality = addr.locality;
        let postalCode = addr.postalCode;
        if locality != nil || postalCode != nil {
            if locality != nil && postalCode != nil {
                str = str.isEmpty ? (locality!) : "\(str), \(postalCode!) \(locality!)"
            } else {
                if locality != nil {
                    str = str.isEmpty ? (locality!) : "\(str), \(locality!)"
                }
            }
        }
        if let region = addr.region, !region.isEmpty {
            str = str.isEmpty ? region : "\(str), \(region)";
        }
        if let country = addr.country, !country.isEmpty {
            str = str.isEmpty ? country : "\(str), \(country)"
        }
        
        var parts = URLComponents();
        parts.scheme = "http";
        parts.host = "maps.apple.com";
        parts.queryItems = [ URLQueryItem(name: "q", value: str.replacingOccurrences(of: ", ", with: ",")) ];
        let value = NSTextField(wrappingLabelWithString: str);
        value.font = NSFont(descriptor: self.roleAndCompany.font!.fontDescriptor, size: NSFont.systemFontSize - 2.0)
        value.setContentHuggingPriority(.defaultLow, for: .vertical);
        value.setContentHuggingPriority(.defaultLow, for: .horizontal);
        value.isEditable = false;
        value.isEnabled = true;
        value.isSelectable = true;
        value.allowsEditingTextAttributes = true;
//        if let url = URL(string: "http:://maps.apple.com/?q=\(str.replacingOccurrences(of: "\n", with: "\n"))") {
        if let url = parts.url {
            value.attributedStringValue = NSAttributedString(string: str, attributes: [.link : url]);
        }
        self.addresses.insertRow(at: self.addresses.numberOfRows-1, with: [ label, value ])
    }
    
    @IBAction func refreshVCard(_ sender: NSButton) {
        VCardManager.instance.refreshVCard(for: jid, on: account) { (result) in
            switch result {
            case .success(_):
                DispatchQueue.main.async {
                    self.refresh();
                }
            default:
                break;
            }
        }
    }
 
    @objc func trustChanged(_ sender: NSPopUpButton) {
        var trust = Trust.trusted;
        switch sender.selectedTag() {
        case 2:
            trust = .trusted;
        case 3:
            trust = .verified;
        case 4:
            trust = .compromised;
        default:
            trust = .undecided;
        }
        let identity = identitiesTableView.identities[sender.tag];
        _ = DBOMEMOStore.instance.setStatus(identity.status.toTrust(trust), forIdentity: identity.address, andAccount: self.account);
        DispatchQueue.main.async {
            self.refresh();
        }
    }
    
}

open class ConversationAttachmentsViewController: NSViewController, ContactDetailsAccountJidAware, NSCollectionViewDelegate, NSCollectionViewDataSource {

    var account: BareJID?
    var jid: BareJID?
    
    @IBOutlet var collectionView: NSCollectionView!;
    
    @IBOutlet var heightConstraint: NSLayoutConstraint!;
    
    var items: [ConversationEntry] = [];
        
    open override func viewDidLoad() {
        super.viewDidLoad();
        heightConstraint.constant = 0;
    }
    
    @objc func openFile(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ConversationEntry else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        NSWorkspace.shared.open(localUrl);
    }
    
    @objc func saveFile(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ConversationEntry else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        let savePanel = NSSavePanel();
        let ext = localUrl.pathExtension;
        if !ext.isEmpty {
            savePanel.allowedFileTypes = [ext];
        }
        savePanel.nameFieldStringValue = localUrl.lastPathComponent;
        savePanel.allowsOtherFileTypes = true;
        savePanel.beginSheetModal(for: self.view.window!, completionHandler: { response in
            guard response == NSApplication.ModalResponse.OK, let url = savePanel.url else {
                return;
            }
            try? FileManager.default.copyItem(at: localUrl, to: url);
        })
    }

    @objc func deleteFile(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ConversationEntry else {
            return;
        }
        DownloadStore.instance.deleteFile(for: "\(item.id)");
        if let idx = items.firstIndex(where: { (att) -> Bool in
            return item.id == att.id;
        }) {
            items.remove(at: idx);
            collectionView.deleteItems(at: [IndexPath(item: idx, section: 0)]);
        }
        DBChatHistoryStore.instance.updateItem(for: item.conversation, id: item.id, updateAppendix: { appendix in
            appendix.state = .removed;
        })
    }
    
    @objc func shareFile(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ConversationEntry else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        
        NSSharingService.sharingServices(forItems: [localUrl]).first(where: { (service) -> Bool in
            service.title == sender.title;
        })?.perform(withItems: [localUrl]);
    }
    
    func collectionView(_ collectionView: NSCollectionView, menuForRepresentedObjectAt indexPath: IndexPath) -> NSMenu? {
        let menu = NSMenu();
        let attachment = items[indexPath.item];
        menu.addItem(NSMenuItem(title: "Open", action: #selector(openFile(_:)), keyEquivalent: ""));
        menu.addItem(NSMenuItem(title: "Save", action: #selector(saveFile(_:)), keyEquivalent: ""));
        if let localUrl = DownloadStore.instance.url(for: "\(attachment.id)") {
            let shareItem = NSMenuItem(title: "Share", action: nil, keyEquivalent: "");
            let shareMenu = NSMenu();
            shareItem.submenu = shareMenu;
            let sharingServices = NSSharingService.sharingServices(forItems: [localUrl]);
            for service in sharingServices {
                let item = shareMenu.addItem(withTitle: service.title, action: nil, keyEquivalent: "");
                item.image = service.image;
                item.target = self;
                item.action = #selector(shareFile(_:));
                item.isEnabled = true;
                item.representedObject = attachment;
            }

            if !shareMenu.items.isEmpty {
                menu.addItem(shareItem);
            }
        }
        menu.addItem(NSMenuItem.separator());
        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteFile(_:)), keyEquivalent: "");
        deleteItem.attributedTitle = NSAttributedString(string: "Delete", attributes: [.foregroundColor: NSColor.systemRed]);
        menu.addItem(deleteItem);
        for item in menu.items {
            item.representedObject = attachment;
        }
        
        return menu.items.isEmpty ? nil : menu;
    }
    
    open override func viewWillAppear() {
        // should show progress indicator...
        DBChatHistoryStore.instance.loadAttachments(for: ConversationKeyItem(account: account!, jid: jid!), completionHandler: { attachments in
            DispatchQueue.main.async {
                self.items = attachments.filter({ (attachment) -> Bool in
                    return DownloadStore.instance.url(for: "\(attachment.id)") != nil;
                })
                self.collectionView.reloadData();
                self.heightConstraint.constant = max(min(CGFloat(ceil(Double(self.items.count) / 3.0)) * 105.0, 350.0), 20);
                if self.items.isEmpty {
                    let label = NSTextField(labelWithString: "No attachments");
                    label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium);
                    label.alignment = .center;
                    label.setContentHuggingPriority(.defaultHigh, for: .horizontal);
                    label.textColor = NSColor.secondaryLabelColor;
                    self.collectionView.backgroundView = label;
                } else {
                    self.collectionView.backgroundView = nil;
                }
            }
        })
        super.viewWillAppear();
    }
    
    public func numberOfSections(in collectionView: NSCollectionView) -> Int {
        return 1;
    }
    
    public func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count;
    }
    
    public func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let view = storyboard!.instantiateController(withIdentifier: "ConversationAttachmentFileView") as! ConversationAttachmentView;
    
        let item = items[indexPath.item];
        
        view.set(item: item);
        
        return view;
    }
}
    
class ConversationAttachmentsCollectionView: NSCollectionView {

    var clickedItemIndex: Int = NSNotFound;

    override func menu(for event: NSEvent) -> NSMenu? {
        self.clickedItemIndex = NSNotFound;

        let point = self.convert(event.locationInWindow, from:nil)
        let count = numberOfItems(inSection: 0);

        for index in 0 ..< count
        {
            let itemFrame = self.frameForItem(at: index)
            if NSMouseInRect(point, itemFrame, self.isFlipped)
            {
                self.clickedItemIndex = index
                if let delegate = self.delegate as? ConversationAttachmentsViewController {
                    return delegate.collectionView(self, menuForRepresentedObjectAt: IndexPath(item: index, section: 0));
                }
            }
        }

        return super.menu(for: event)
    }

}

class ConversationAttachmentView: NSCollectionViewItem {
    
    var imageField: NSImageView!;
    var filenameField: NSTextField!;
    var detailsField: NSTextField!;
    
    private var id: Int = NSNotFound;
        
    private var trackingArea: NSTrackingArea?;
        
    var constraints: [ViewType: [NSLayoutConstraint]] = [:];
    
    var viewType: ViewType = .none {
        didSet {
            if let oldConstraints = self.constraints[oldValue] {
                NSLayoutConstraint.deactivate(oldConstraints);
            }
            if let newConstraints = self.constraints[viewType] {
                NSLayoutConstraint.activate(newConstraints);
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        trackingArea = NSTrackingArea(rect: .zero, options: [.inVisibleRect, .activeAlways, .mouseEnteredAndExited], owner: self, userInfo: nil);
        self.view.addTrackingArea(trackingArea!);
        
        imageField = NSImageView(frame: .zero);
        imageField.translatesAutoresizingMaskIntoConstraints = false;
        self.view.addSubview(imageField);
        filenameField = NSTextField(labelWithString: "");
        filenameField.translatesAutoresizingMaskIntoConstraints = false;
        filenameField.drawsBackground = true;
        filenameField.backgroundColor = NSColor.alternatingContentBackgroundColors.first?.withAlphaComponent(0.85);
        filenameField.textColor = NSColor.secondaryLabelColor;
        filenameField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2, weight: .medium);
        filenameField.alignment = .center;
        filenameField.lineBreakMode = .byTruncatingTail;
        filenameField.cell?.truncatesLastVisibleLine = true
        self.view.addSubview(filenameField);
        detailsField = NSTextField(labelWithString: "");
        detailsField.translatesAutoresizingMaskIntoConstraints = false;
        detailsField.drawsBackground = true;
        detailsField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 3, weight: .medium);
        detailsField.alignment = .center;
        detailsField.textColor = NSColor.secondaryLabelColor;
        detailsField.backgroundColor = NSColor.alternatingContentBackgroundColors.first?.withAlphaComponent(0.85); //NSColor.alternatingContentBackgroundColors//unemphasizedSelectedContentBackgroundColor;
        detailsField.lineBreakMode = .byTruncatingTail;
        detailsField.cell?.truncatesLastVisibleLine = true
        self.view.addSubview(detailsField);

        constraints[.image] = [
            view.leadingAnchor.constraint(equalTo: imageField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: imageField.trailingAnchor),
            view.topAnchor.constraint(equalTo: imageField.topAnchor),
            view.bottomAnchor.constraint(equalTo: imageField.bottomAnchor),
            
            imageField.widthAnchor.constraint(equalTo: imageField.heightAnchor),
            imageField.heightAnchor.constraint(equalToConstant: 100),
            
            view.leadingAnchor.constraint(equalTo: filenameField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: filenameField.trailingAnchor),
            imageField.bottomAnchor.constraint(equalTo: filenameField.topAnchor),
            
            view.leadingAnchor.constraint(equalTo: detailsField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: detailsField.trailingAnchor),
            filenameField.bottomAnchor.constraint(equalTo: detailsField.topAnchor),
            detailsField.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ];

        constraints[.imageHover] = [
            view.leadingAnchor.constraint(equalTo: imageField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: imageField.trailingAnchor),
            view.topAnchor.constraint(equalTo: imageField.topAnchor),
            view.bottomAnchor.constraint(equalTo: imageField.bottomAnchor),
            
            imageField.widthAnchor.constraint(equalTo: imageField.heightAnchor),
            imageField.heightAnchor.constraint(equalToConstant: 100),
            
            view.leadingAnchor.constraint(equalTo: filenameField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: filenameField.trailingAnchor),
            view.topAnchor.constraint(lessThanOrEqualTo: filenameField.topAnchor),
            
            view.leadingAnchor.constraint(equalTo: detailsField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: detailsField.trailingAnchor),
            filenameField.bottomAnchor.constraint(equalTo: detailsField.topAnchor),
            detailsField.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ];
        
        constraints[.file] = [
            view.leadingAnchor.constraint(equalTo: imageField.leadingAnchor, constant: -10),
            view.trailingAnchor.constraint(equalTo: imageField.trailingAnchor, constant: 10),
            view.topAnchor.constraint(equalTo: imageField.topAnchor, constant: -4),
            view.bottomAnchor.constraint(equalTo: imageField.bottomAnchor, constant: 16),
            
            imageField.widthAnchor.constraint(equalTo: imageField.heightAnchor),
            imageField.heightAnchor.constraint(equalToConstant: 80),
            
            view.leadingAnchor.constraint(equalTo: filenameField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: filenameField.trailingAnchor),
            view.topAnchor.constraint(lessThanOrEqualTo: filenameField.topAnchor),
            
            view.leadingAnchor.constraint(equalTo: detailsField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: detailsField.trailingAnchor),
            filenameField.bottomAnchor.constraint(equalTo: detailsField.topAnchor),
            detailsField.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            detailsField.heightAnchor.constraint(equalToConstant: 0)
        ];

        constraints[.fileHover] = [
            view.leadingAnchor.constraint(equalTo: imageField.leadingAnchor, constant: -17),
            view.trailingAnchor.constraint(equalTo: imageField.trailingAnchor, constant: 17),
            view.topAnchor.constraint(equalTo: imageField.topAnchor, constant: -4),
            view.bottomAnchor.constraint(equalTo: imageField.bottomAnchor, constant: 30),
            
            imageField.widthAnchor.constraint(equalTo: imageField.heightAnchor),
            imageField.heightAnchor.constraint(equalToConstant: 66),
            
            view.leadingAnchor.constraint(equalTo: filenameField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: filenameField.trailingAnchor),
            view.topAnchor.constraint(lessThanOrEqualTo: filenameField.topAnchor),
            
            view.leadingAnchor.constraint(equalTo: detailsField.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: detailsField.trailingAnchor),
            filenameField.bottomAnchor.constraint(equalTo: detailsField.topAnchor),
            detailsField.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ];
    }
    
    override func mouseEntered(with event: NSEvent) {
        print("mouse entered!");
        super.mouseEntered(with: event);
//        NSAnimationContext.runAnimationGroup { (context) in
//            context.duration = 5.0;
//            context.allowsImplicitAnimation = true;
            switch viewType {
            case .image:
                viewType = .imageHover;
            case .file:
                viewType = .fileHover;
            default:
                break;
            }
//            self.view.layoutSubtreeIfNeeded()
//        }
    }

    override func mouseExited(with event: NSEvent) {
        print("mouse exited!");
        super.mouseExited(with: event);
//        NSAnimationContext.runAnimationGroup { (context) in
//            context.duration = 5.0;
//            context.allowsImplicitAnimation = true;
        switch viewType {
        case .imageHover:
            viewType = .image;
        case .fileHover:
            viewType = .file;
        default:
            break;
        }
//            self.view.layoutSubtreeIfNeeded()
//        }
    }

    func set(item: ConversationEntry) {
        self.id = item.id;
        if let fileUrl = DownloadStore.instance.url(for: "\(item.id)") {
            filenameField.stringValue = fileUrl.lastPathComponent;
            let fileSize = fileSizeToString(try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.size] as? UInt64);
            detailsField.stringValue = fileSize;
            if let imageProvider = MetadataCache.instance.metadata(for: "\(item.id)")?.imageProvider {
                viewType = .image;
                imageField.image = NSWorkspace.shared.icon(forFile: fileUrl.path);
                imageProvider.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil, completionHandler: { data, error in
                    guard data != nil && error == nil else {
                        DispatchQueue.main.async {
                            guard self.id == item.id else {
                                return;
                            }
                            self.viewType = .file;
                            self.imageField.image = NSWorkspace.shared.icon(forFile: fileUrl.path);
                        }
                        return;
                    }
                    DispatchQueue.main.async {
                        guard self.id == item.id else {
                            return;
                        }
                        switch data! {
                        case let image as NSImage:
                            self.imageField.image = image.square(100);
                        case let data as Data:
                            self.imageField.image = NSImage(data: data)?.square(100);
                        default:
                            break;
                        }
                    }
                })
            } else if let image = NSImage(contentsOf: fileUrl)?.square(100) {
                imageField.image = image;
                viewType = .image;
            } else {
                imageField.image = NSWorkspace.shared.icon(forFile: fileUrl.path);
                viewType = .file;
            }
        } else if case .attachment(let url, let appendix) = item.payload {
            viewType = .file;
            let filename = appendix.filename ?? URL(string: url)?.lastPathComponent ?? "";
            if filename.isEmpty {
                self.filenameField.stringValue =  "Unknown file";
            } else {
                self.filenameField.stringValue = filename;
            }
            if let size = appendix.filesize {
                if let mimetype = appendix.mimetype, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue() {
                    imageField.image = NSWorkspace.shared.icon(forFileType: uti as String);
                } else {
                    imageField.image = NSWorkspace.shared.icon(forFileType: "");
                }
                detailsField.stringValue = fileSizeToString(UInt64(size));
            } else {
                detailsField.stringValue = "---";
                imageField.image = NSWorkspace.shared.icon(forFileType: "");
            }
        }
    }
    
    func fileSizeToString(_ sizeIn: UInt64?) -> String {
        guard let size = sizeIn else {
            return "";
        }
        let formatter = ByteCountFormatter();
        formatter.countStyle = .file;
        return formatter.string(fromByteCount: Int64(size));
    }
    
    enum ViewType {
        case none
        case image
        case imageHover
        case file
        case fileHover
    }
}
