//
// ServiceDiscoveryViewController.swift
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
import os

class ServiceDiscoveryViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    
    @IBOutlet var jidField: NSTextField!;
    @IBOutlet var outlineView: NSOutlineView!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    @IBOutlet var browseButton: NSButton!;
    @IBOutlet var executeButton: NSButton!
    @IBOutlet var joinButton: NSButton!;
    
    var account: BareJID?;
    var jid: JID? {
        didSet {
            //resetOutlineView();
            self.jidField.stringValue = jid?.stringValue ?? "";
            self.refreshButtonStates();
            self.progressIndicator.stopAnimation(self);
            guard let jid = self.jid else {
                return;
            }
            discoInfo(for: jid);
        }
    }
    var node: String? = nil;
    
    var type: DisplayType = .normal {
        didSet {
            //resetOutlineView();
            configureOutlineView();
        }
    }
    //var items: [Item] = [];
    var rootItem: Item? = nil {
        didSet {
            self.outlineView.reloadData();
        }
    }

    var headerView: NSTableHeaderView?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(itemWillExpand(_:)), name: NSOutlineView.itemWillExpandNotification, object: self.outlineView);
    }
    
    override func viewWillAppear() {
        refreshButtonStates();
        super.viewDidAppear();
    }
    
    @objc func itemWillExpand(_ notification: Notification) {
        guard let item = notification.userInfo?["NSObject"] as? Item else {
            return;
        }
        if item.subitems == nil {
            self.progressIndicator.startAnimation(self);
            self.discoItems(for: item, on: self.account!);
        }
    }
    
    @IBAction func enterPressed(_ sender: Any) {
        let str = jidField.stringValue;
        guard !str.isEmpty else {
            return;
        }
        self.node = nil;
        jid = JID(str);
    }
    
    @IBAction func rowDoubleClicked(_ sender: Any) {
        let row = self.outlineView.clickedRow;
        guard row >= 0 else {
            return;
        }
        guard let account = self.account, let item = self.outlineView.item(atRow: row) as? Item else {
            return;
        }
        if item.jid.domain != rootItem?.jid.domain {
            self.jidField.stringValue = item.jid.stringValue;
            self.node = item.node;
            self.jid = item.jid;
        } else {
            self.discoItems(for: item, on: account);
        }
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let it = item as? Item {
            return it.subitems?.count ?? 0;
        }
        return rootItem?.subitems?.count ?? 0;
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let it = item as? Item {
            return it.subitems?[index] as Any;
        }
        return rootItem?.subitems?[index] as Any;
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let it = item as? Item, let parentItem = outlineView.parent(forItem: it) as? Item ?? rootItem, parentItem.jid.domain == it.jid.domain && !(it.subitems?.isEmpty ?? false) {
            return it.hasFeature("http://jabber.org/protocol/disco#items") || it.identities.contains(where: { $0.category == "pubsub" && $0.type == "leaf" }) || it.identities.contains(where: { $0.category == "conference" });
        }
        return false;
    }
    
    func outlineView(_ outlineView: NSOutlineView, objectValueFor tableColumn: NSTableColumn?, byItem item: Any?) -> Any? {
        return item;
    }
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        switch (tableColumn?.identifier.rawValue ?? "") {
        case "ComponentOutlineColumn":
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ServiceDiscoveryOutlineCell"), owner: self);
            outlineView.level(forItem: item);
            return view;
        case "ComponentNameColumn":
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ServiceDiscoComponentInfoCell"), owner: self);
            let it = item as? Item;
            var image: NSImage? = nil;
            if let it = item as? Item {
                let categories = it.identities.map({ (identity) -> String in
                    return identity.category;
                });
                if categories.contains("pubsub") {
                    image = NSImage(named: "routerIcon");
                } else if categories.contains("conference") {
                    image = NSImage(named: "mucIcon");
                } else if categories.contains("gateway") {
                    image = NSImage(named: "switchIcon");
                } else {
                    image = NSImage(named: "moduleIcon");
                }
            }
            (view?.subviews[0] as? NSImageView)?.image = image;
            (view?.subviews[1] as? NSTextField)?.stringValue = it?.name ?? "";
            (view?.subviews[2] as? NSTextField)?.stringValue = it?.jid.stringValue ?? "";
            if let version = it?.version {
                let versionStr = "\(version.name) \(version.version)";
                (view?.subviews[3] as? NSTextField)?.stringValue = versionStr;
                if let os = version.os {
                    view?.toolTip = "\(versionStr) \(os)";
                } else {
                    view?.toolTip = versionStr;
                }
            } else {
                (view?.subviews[3] as? NSTextField)?.stringValue = "";
                view?.toolTip = "";
            }
            return view;
        case "ComponentPubSubNameColumn":
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ServiceDiscoComponentPubSubNameColumn"), owner: self);
            (view?.subviews[0] as? NSTextField)?.stringValue = (item as? Item)?.name ?? "";
            return view;
        case "ComponentPubSubNodeColumn":
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ServiceDiscoComponentPubSubNodeColumn"), owner: self);
            (view?.subviews[0] as? NSTextField)?.stringValue = (item as? Item)?.node ?? "";
            return view;
        default:
            return nil;
        }
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        refreshButtonStates();
    }
    
    @IBAction func clickedBrowseButton(_ sender: NSButton) {
        let row = self.outlineView.selectedRow;
        guard row >= 0 else {
            return;
        }
        guard let account = self.account, let item = self.outlineView.item(atRow: row) as? Item else {
            return;
        }
        if item.jid.domain != rootItem?.jid.domain {
            self.jidField.stringValue = item.jid.stringValue;
            self.node = item.node;
            self.jid = item.jid;
        } else {
            self.discoItems(for: item, on: account);
        }
    }
    
    @IBAction func clickedExecuteButton(_ sender: NSButton) {
        let row = self.outlineView.selectedRow;
        guard row >= 0 else {
            return;
        }
        guard let item = self.outlineView.item(atRow: row) as? Item else {
            return;
        }
        
        if item.node == nil {
            guard let windowController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("SelectCommandWindowController")) as? NSWindowController, let viewController = windowController.contentViewController as? SelectAdHocCommandController else {
                return;
            }
        
            viewController.account = self.account;
            viewController.jid = item.jid;
        
            self.view.window?.beginSheet(windowController.window!, completionHandler: nil);
        } else {
            guard let windowController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ExecuteAdhocWindowController")) as? NSWindowController, let viewController = windowController.contentViewController as? ExecuteAdHocCommandController else {
                return;
            }
            
            viewController.account = self.account;
            viewController.jid = item.jid;
            viewController.commandId = item.node;
            
            self.view.window?.beginSheet(windowController.window!, completionHandler: nil);
        }
    }
    
    @IBAction func joinButton(_ sender: NSButton) {
        let row = self.outlineView.selectedRow;
        guard row >= 0 else {
            return;
        }
        guard let item = self.outlineView.item(atRow: row) as? Item, let account = self.account else {
            return;
        }
        
        guard let discoModule = XmppService.instance.getClient(for: account)?.module(.disco) else {
            return;
        }
        
        self.joinButton.isEnabled = false;
        self.progressIndicator.startAnimation(self);
        discoModule.getInfo(for: item.jid, node: nil, completionHandler: { [weak self] result in
            switch result {
            case .success(let info):
                let requiresPassword = info.features.firstIndex(of: "muc_passwordprotected") != nil;
                
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(self);
                    self?.joinButton.isEnabled = true;
                    guard let window = self?.view.window else {
                        return;
                    }
                    JoinGroupchatViewController.open(on: window, account: account, roomJid: item.jid.bareJid, isPasswordRequired: requiresPassword);
                }
            case .failure(let error):
                DispatchQueue.main.async { [weak self] in
                    self?.view.window?.close();
                }
            }
        });
    }
    
    @IBAction func clickedCloseButton(_ sender: NSButton) {
        self.view.window?.close();
    }
    
    fileprivate func refreshButtonStates() {
        let row = self.outlineView.selectedRow;
        guard row >= 0 && row < self.outlineView.numberOfRows, let item = self.outlineView.item(atRow: row) as? Item else {
            browseButton.isEnabled = false;
            executeButton.isEnabled = false;
            joinButton.isEnabled = false;
            return;
        }
        
        browseButton.isEnabled = item.hasFeature("http://jabber.org/protocol/disco#items") || item.identities.contains(where: { $0.category == "pubsub" && $0.type == "leaf" }) || item.identities.contains(where: { $0.category == "conference" });
        executeButton.isEnabled = item.hasFeature("http://jabber.org/protocol/commands");
        joinButton.isEnabled = item.hasFeature("http://jabber.org/protocol/muc") && item.identities.firstIndex(where: { (identity) -> Bool in
            return identity.category == "conference";
        }) != nil && item.jid.localPart != nil;
    }
    
    fileprivate func resetOutlineView() {
//        self.outlineView.outlineTableColumn = nil;
//        self.outlineView.outlineTableColumn?.width = 0.0;
        if let headerView = self.outlineView.headerView {
            self.headerView = headerView;
            self.outlineView.headerView = nil;
        }
        let columns = self.outlineView.tableColumns;
        columns.forEach { (column) in
            guard column != self.outlineView.outlineTableColumn else {
                return;
            }
            self.outlineView.removeTableColumn(column);
        }
    }
    
    fileprivate func configureOutlineView() {
        let oldColumns = self.outlineView.tableColumns;
        switch type {
        case .normal, .conference:
            if let headerView = self.outlineView.headerView {
                self.headerView = headerView;
                self.outlineView.headerView = nil;
            }

            let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ComponentNameColumn"));
            nameColumn.width = self.outlineView.visibleRect.width - self.outlineView.tableColumns.reduce(10, { (prev, column) -> CGFloat in
                return prev + (oldColumns.contains(column) ? 0 : column.width + 6);
            })
            self.outlineView.addTableColumn(nameColumn);
            self.outlineView.outlineTableColumn = nameColumn;
        case .pubsub:
            if let headerView = self.headerView {
                self.outlineView.headerView = headerView;
                self.headerView = nil;
            }
            //self.outlineView.outlineTableColumn?.width = 20.0;
//            self.outlineView.headerView?.isHidden = false;
            let columnWidth = (self.outlineView.visibleRect.width - 10) / 2;
            let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ComponentPubSubNameColumn"));
            nameColumn.title = NSLocalizedString("Name", comment: "service disco column name");
            nameColumn.width = columnWidth;
            self.outlineView.addTableColumn(nameColumn);
            let nodeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ComponentPubSubNodeColumn"));
            nodeColumn.title = NSLocalizedString("Node", comment: "service disco column name");
            nodeColumn.width = columnWidth;
            self.outlineView.addTableColumn(nodeColumn);
            self.outlineView.outlineTableColumn = nameColumn;
        }
        
        oldColumns.forEach { (column) in
            guard column != self.outlineView.outlineTableColumn else {
                return;
            }
            self.outlineView.removeTableColumn(column);
        }
        self.outlineView.reloadData();
    }
    
    fileprivate func discoInfo(for jid: JID) {
        self.rootItem = nil;
        guard let account = self.account, let client = XmppService.instance.getClient(for: account), client.state == .connected() else {
            return;
        }

        self.progressIndicator.startAnimation(self);
        let node = self.node;
        client.module(.disco).getInfo(for: jid, node: node, completionHandler: { [weak self] result in
            switch result {
            case .success(let info):
                let categories = info.identities.map({ (identity) -> String in
                    return identity.category;
                });
                DispatchQueue.main.async {
                    self?.type = DisplayType.from(categories: categories);
                    self?.discoItems(for: Item(jid: jid, node: node, name: nil), on: account);
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(self);
                    var node = self?.node ?? "";
                    if !node.isEmpty {
                        node = String.localizedStringWithFormat(NSLocalizedString(" and node %@", comment: "alert window message part"), node);
                    }
                    let alert = Alert();
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.messageText = NSLocalizedString("Service Discovery Failure!", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to retrieve disco#info details from %@\\%@: %@", comment: "alert window message"), jid.stringValue, node, error.localizedDescription);
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.run(completionHandler: { (response) in
                        // nothing to do..
                    })
                }
            }
        });
    }
    
    fileprivate func discoItems(for parentItem: Item, on account: BareJID) {
        guard let client = XmppService.instance.getClient(for: account), client.state == .connected() else {
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(self);
            }
            return;
        }

        let discoModule = client.module(.disco);
        let node = parentItem.identities.contains(where: { $0.category == "conference" && $0.type == "mix" }) ? "mix" : parentItem.node;
        discoModule.getItems(for: parentItem.jid, node: node, completionHandler: { [weak self] result in
            switch result {
            case .success(let items):
                DispatchQueue.main.async {
                    let oldItems = parentItem.subitems;
                    parentItem.subitems = items.items.map({ (item) -> Item in
                        return Item(item);
                    }).sorted(by: { (i1, i2) -> Bool in
                        return (i1.name ?? i1.jid.stringValue).compare(i2.name ?? i2.jid.stringValue) == .orderedAscending;
                    })
                    if self?.rootItem == nil {
                        self?.rootItem = parentItem;
                        self?.outlineView.reloadData();
                    } else {
                        self?.outlineView.beginUpdates();
                        if let oldItemsCount = oldItems?.count {
                            self?.outlineView.removeItems(at: IndexSet(0..<oldItemsCount), inParent: parentItem, withAnimation: .effectGap);
                        }
                        self?.outlineView.insertItems(at: IndexSet(0..<parentItem.subitems!.count), inParent: parentItem, withAnimation: .effectGap);
                        self?.outlineView.endUpdates();
                    }
                }
                let group = DispatchGroup();
                if parentItem.identities.contains(where: { ($0.category == "hierarchy" || $0.category == "pubsub") && $0.type == "leaf" }) {
                    // parent was a leaf so there is no subquery for items info!
                    group.enter();
                    DispatchQueue.main.async {
                        parentItem.subitems?.forEach({ item in
                            item.subitems = [];
                            self?.outlineView.reloadItem(item);
                        });
                        group.leave()
                    }
                } else {
                    group.enter();
                    items.items.forEach({ (item) in
                        group.enter();
                        discoModule.getInfo(for: item.jid, node: item.node, completionHandler: { result in
                            switch result {
                            case .success(let info):
                                if info.features.contains("jabber:iq:version") {
                                    group.enter();
                                    client.module(.softwareVersion).checkSoftwareVersion(for: item.jid, completionHandler: { result in
                                        DispatchQueue.main.async {
                                            switch result {
                                            case .success(let version):
                                                guard let idx = parentItem.subitems?.firstIndex(where: { (it) -> Bool in
                                                    return it.jid == item.jid && it.node == item.node;
                                                }) else {
                                                    return;
                                                }
                                                if let it = parentItem.subitems?[idx] {
                                                    it.update(version: version);
                                                    self?.outlineView.reloadItem(it);
                                                }
                                            case .failure(_):
                                                break;
                                            }
                                        }
                                        group.leave();
                                    });
                                }
                                DispatchQueue.main.async {
                                    guard let idx = parentItem.subitems?.firstIndex(where: { (it) -> Bool in
                                        return it.jid == item.jid && it.node == item.node;
                                    }) else {
                                        return;
                                    }
                                    if let it = parentItem.subitems?[idx] {
                                        it.update(identities: info.identities, features: info.features);
                                        self?.outlineView.reloadItem(it);
                                    }
                                }
                            default:
                                break;
                            }
                            group.leave();
                        });
                    })
                    group.leave();
                }
                group.notify(queue: DispatchQueue.main, execute: {
                    self?.progressIndicator.stopAnimation(self);
                });
            case .failure(let error):
                parentItem.subitems = [];
                // FIXME: HANDLE IT SOMEHOW!
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(self);
                    var node = parentItem.node ?? "";
                    if !node.isEmpty {
                        node = String.localizedStringWithFormat(NSLocalizedString(" and node %@", comment: "alert window message part"), node);
                    }
                    let alert = Alert();
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.messageText = NSLocalizedString("Service Discovery Failure!", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to retrieve disco#items details from %@\\%@: %@", comment: "alert window message"), parentItem.jid.stringValue, node, error.localizedDescription);
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.run(completionHandler: { (response) in
                        // nothing to do..
                    });
                }
            }
        });
    }
    
    enum DisplayType {
        case normal
        case pubsub
        case conference
        
        static func from(categories: [String]) -> DisplayType {
            guard !categories.isEmpty else {
                return .normal;
            }
            if categories.contains("pubsub") && !categories.contains("server") {
                return .pubsub;
            }
            if categories.contains("conference") {
                return .conference;
            }
            return .normal;
        }
    }
    
    class Item: DiscoveryModule.Item {
        
        private(set) var identities: [DiscoveryModule.Identity] = [];
        private(set) var features: [String] = [];
        fileprivate var subitems: [Item]? = nil;
        private(set) var version: SoftwareVersionModule.SoftwareVersion?;
        
        override init(jid: JID, node: String?, name: String?) {
            super.init(jid: jid, node: node, name: name);
        }
        
        init(_ item: DiscoveryModule.Item) {
            super.init(jid: item.jid, node: item.node, name: item.name);
        }
        
        func hasFeature(_ feature: String) -> Bool {
            return features.contains(feature);
        }
        
        func update(identities: [DiscoveryModule.Identity], features: [String]) {
            self.identities = identities;
            self.features = features;
        }
        
        func update(version: SoftwareVersionModule.SoftwareVersion) {
            self.version = version;
        }
    }
    
}
