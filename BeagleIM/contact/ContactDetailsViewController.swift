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
    
    var showSettings: Bool = false;
    
    var basicViewController: ConversationDetailsViewController? {
        didSet {
            basicViewController?.account = self.account;
            basicViewController?.jid = self.jid;
        }
    }
    
    open override func viewWillAppear() {
        self.tabsView.addTabViewItem(NSTabViewItem(viewController: self.storyboard!.instantiateController(withIdentifier: "ConversationVCardViewController") as! NSViewController));
        self.tabsView.addTabViewItem(NSTabViewItem(viewController: self.storyboard!.instantiateController(withIdentifier: "ConversationOmemoViewController") as! NSViewController))
        
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
}

open class ConversationDetailsViewController: NSViewController, ContactDetailsAccountJidAware {
    
    var account: BareJID?;
    var jid: BareJID?;
    
    @IBOutlet var nameField: NSTextField!;
    @IBOutlet var jidField: NSTextField!;
    
    @IBOutlet var settingsContainerView: NSView!
    @IBOutlet var settingsContainerViewHeightConstraint: NSLayoutConstraint!
    
    var settingsViewController: ConversationSettingsViewController? {
        didSet {
            settingsViewController?.account = self.account;
            settingsViewController?.jid = self.jid;
        }
    }
    
    var showSettings: Bool = false;
    
    open override func viewWillAppear() {
        nameField.stringValue = jid?.stringValue ?? "";
        jidField.stringValue = jid?.stringValue ?? "";
        if let jid = self.jid, let account = self.account {
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
                            fn = XmppService.instance.getClient(for: account)?.rosterStore?.get(for: JID(jid))?.name ?? jid.stringValue;
                        }
                    }
                    self.nameField.stringValue = fn;
                }
            }
        }
        settingsContainerView.isHidden = !showSettings;
        settingsContainerViewHeightConstraint.isActive = !showSettings;
        settingsViewController?.account = self.account;
        settingsViewController?.jid = self.jid;
        super.viewWillAppear();
    }
    
    open override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "PrepareConversationSettingsViewController" {
            self.settingsViewController = segue.destinationController as? ConversationSettingsViewController;
        }
    }
}

open class ConversationSettingsViewController: NSViewController, ContactDetailsAccountJidAware {
 
    var account: BareJID?
    var jid: BareJID?
    
    var chat: DBChatProtocol? {
        didSet {
            if chat != nil {
                muteNotifications.isEnabled = true;
                if let chat = self.chat as? DBChatStore.DBChat {
                    muteNotifications.state = chat.options.notifications == .none ? .on : .off;
                }
                if let room = self.chat as? DBChatStore.DBRoom {
                    muteNotifications.state = room.options.notifications == .none ? .on : .off;
                }
            } else {
                muteNotifications.isEnabled = false;
            }
        }
    }
    
    @IBOutlet var muteNotifications: NSButton!;
 
    open override func viewWillAppear() {
        super.viewWillAppear();
        if let account = self.account, let jid = self.jid {
            chat = DBChatStore.instance.getChat(for: account, with: jid);
        } else {
            muteNotifications.isEnabled = false;
        }
        print("got:", account, "and:", jid);
    }
    
    @IBAction func muteNotificcationsChanged(_ sender: NSButton) {
        let state = sender.state == .on;
        if let chat = self.chat as? DBChatStore.DBChat {
            chat.modifyOptions({ (options) in
                options.notifications = state ? .none : .always;
            }, completionHandler: nil);
        }
        if let room = self.chat as? DBChatStore.DBRoom {
            room.modifyOptions({ (options) in
                options.notifications = state ? .none : .mention;
            }, completionHandler: nil);
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
        fingerprintView.font = NSFont.userFixedPitchFont(ofSize: NSFont.systemFontSize);
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
        DBOMEMOStore.instance.setStatus(identity.status.toTrust(trust), forIdentity: identity.address, andAccount: self.account);
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

    override func viewWillAppear() {
        super.viewWillAppear();
        _ = self.view;
        refresh();
    }
    
    func refresh() {
        guard let jid = self.jid, let account = self.account else {
            let views = self.stack.arrangedSubviews;
            views.forEach { (view) in
                self.stack.removeView(view);
            }
            return;
        }
        
        DBVCardStore.instance.vcard(for: jid) { (vcard) in
            DispatchQueue.main.async {
                let views = self.stack.arrangedSubviews;
                views.forEach { (view) in
                    self.stack.removeView(view);
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
                        fn = XmppService.instance.getClient(for: account)?.rosterStore?.get(for: JID(jid))?.name ?? jid.stringValue;
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
                    self.stack.addArrangedSubview(roleAndCompany);
                }

                if let addresses = vcard?.addresses, !addresses.isEmpty {
                    let label = NSTextField(labelWithString: "Addresses");
                    label.setContentCompressionResistancePriority(.required, for: .vertical);
                    label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium);
                    self.stack.addArrangedSubview(label);
                    addresses.forEach({ (addr) in
                        self.addAddress(address: addr);
                    })
                }
//                self.view.needsLayout = true;
//                self.stack.invalidateIntrinsicContentSize();
            }
        }
    }
    
    @objc func refreshVCard(_ sender: NSButton) {
        guard let jid = self.jid, let account = self.account else {
            return;
        }
        VCardManager.instance.refreshVCard(for: jid, on: account) { (vcard) in
            DispatchQueue.main.async {
                self.refresh();
            }
        }
    }
    
    func addAddress(address addr: VCard.Address) {
        let label = NSTextField(labelWithString: (addr.types.first ?? .home) == .home ? "Home" : "Work");
        label.setContentHuggingPriority(.defaultLow, for: .vertical);
        label.setContentHuggingPriority(.defaultLow, for: .horizontal);
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2.0, weight: .bold);

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
        value.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2.0);
        value.setContentHuggingPriority(.defaultLow, for: .vertical);
        value.setContentHuggingPriority(.defaultLow, for: .horizontal);
        value.isEditable = false;
        value.isEnabled = true;
        value.isSelectable = true;
        value.allowsEditingTextAttributes = true;
        if let url = parts.url {
            value.attributedStringValue = NSAttributedString(string: str, attributes: [.link : url]);
        }
        
        let row = NSStackView(views: [label, value]);
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
                        fn = XmppService.instance.getClient(for: self.account)?.rosterStore?.get(for: JID(self.jid))?.name ?? self.jid.stringValue;
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
        VCardManager.instance.refreshVCard(for: jid, on: account) { (vcard) in
            if vcard != nil {
                DispatchQueue.main.async {
                    self.refresh();
                }
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
        DBOMEMOStore.instance.setStatus(identity.status.toTrust(trust), forIdentity: identity.address, andAccount: self.account);
        DispatchQueue.main.async {
            self.refresh();
        }
    }
    
}
