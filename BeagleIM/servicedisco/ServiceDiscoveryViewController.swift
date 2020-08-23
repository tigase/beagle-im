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
            return it.hasFeature("http://jabber.org/protocol/disco#items") || it.identities.contains(where: { $0.category == "pubsub" && $0.type == "leaf" });
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
        
        guard let discoModule: DiscoveryModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        self.joinButton.isEnabled = false;
        self.progressIndicator.startAnimation(self);
        discoModule.getInfo(for: item.jid, node: nil, onInfoReceived: { [weak self] node, identities, features in
            let requiresPassword = features.firstIndex(of: "muc_passwordprotected") != nil;
            
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(self);
                self?.joinButton.isEnabled = true;
                guard let window = self?.view.window else {
                    return;
                }
                JoinGroupchatViewController.open(on: window, account: account, roomJid: item.jid.bareJid, isPasswordRequired: requiresPassword);
            }
        }, onError: { (errorCondition) in
            DispatchQueue.main.async { [weak self] in
                self?.view.window?.close();
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
        
        browseButton.isEnabled = true;
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
            nameColumn.title = "Name";
            nameColumn.width = columnWidth;
            self.outlineView.addTableColumn(nameColumn);
            let nodeColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ComponentPubSubNodeColumn"));
            nodeColumn.title = "Node";
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
        guard let account = self.account, let client = XmppService.instance.getClient(for: account), client.state == .connected else {
            return;
        }
        guard let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }

        self.progressIndicator.startAnimation(self);
        discoModule.getInfo(for: jid, node: self.node, onInfoReceived: { [weak self] (node, identities, features) in
            let categories = identities.map({ (identity) -> String in
                return identity.category;
            });
            DispatchQueue.main.async {
                self?.type = DisplayType.from(categories: categories);
                self?.discoItems(for: Item(jid: jid, node: node ?? self?.node, name: nil), on: account);
            }
        }) { [weak self] (error) in
            // FIXME: HANDLE IT SOMEHOW!
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(self);
                var node = self?.node ?? "";
                if !node.isEmpty {
                    node = " and node \(node)";
                }
                let alert = Alert();
                alert.icon = NSImage(named: NSImage.cautionName);
                alert.messageText = "Service Discovery Failure!"
                alert.informativeText = "It was not possible to retrieve disco#info details from \(jid)\(node): \(error?.rawValue ?? "unknown error")";
                alert.addButton(withTitle: "OK");
                alert.run(completionHandler: { (response) in
                    // nothing to do..
                })
            }
            print("error", error as Any);
        }
    }
    
    fileprivate func discoItems(for parentItem: Item, on account: BareJID) {
        guard let client = XmppService.instance.getClient(for: account), client.state == .connected else {
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(self);
            }
            return;
        }
        guard let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(self);
            }
            return;
        }
        discoModule.getItems(for: parentItem.jid, node: parentItem.node, onItemsReceived: { [weak self] (node, items) in
            DispatchQueue.main.async {
                parentItem.subitems = items.map({ (item) -> Item in
                    return Item(item);
                }).sorted(by: { (i1, i2) -> Bool in
                    return (i1.name ?? i1.jid.stringValue).compare(i2.name ?? i2.jid.stringValue) == .orderedAscending;
                })
                if self?.rootItem == nil {
                    self?.rootItem = parentItem;
                    self?.outlineView.reloadData();
                } else {
                    self?.outlineView.insertItems(at: IndexSet(0..<parentItem.subitems!.count), inParent: parentItem, withAnimation: .effectGap);
                }
            }
            var count = items.count;
            let finished = {
                count = count - 1;
                if count <= 0 {
                    self?.progressIndicator.stopAnimation(self);
                }
            }
            if parentItem.identities.contains(where: { ($0.category == "hierarchy" || $0.category == "pubsub") && $0.type == "leaf" }) {
                // parent was a leaf so there is no subquery for items info!
                DispatchQueue.main.async {
                    parentItem.subitems?.forEach({ item in
                        item.subitems = [];
                        self?.outlineView.reloadItem(item);
                        finished();
                    });
                }
            } else {
                items.forEach({ (item) in
                    discoModule.getInfo(for: item.jid, node: item.node, onInfoReceived: { (node, identities, features) in
                        DispatchQueue.main.async {
                            guard let idx = parentItem.subitems?.firstIndex(where: { (it) -> Bool in
                                return it.jid == item.jid && it.node == item.node;
                            }) else {
                                return;
                            }
                            if let it = parentItem.subitems?[idx] {
                                it.update(identities: identities, features: features);
                                self?.outlineView.reloadItem(it);
                            }
                            finished();
                        }
                    }) { (error) in
                        // FIXME: HANDLE IT SOMEHOW!
                        DispatchQueue.main.async {
                            finished();
                        }
                        print("error", error as Any);
                    }
                })
                if items.isEmpty {
                    DispatchQueue.main.async {
                        finished();
                    }
                }
            }
        }, onError: { [weak self] (error) in
            parentItem.subitems = [];
            // FIXME: HANDLE IT SOMEHOW!
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(self);
                var node = parentItem.node ?? "";
                if !node.isEmpty {
                    node = " and node \(node)";
                }
                let alert = Alert();
                alert.icon = NSImage(named: NSImage.cautionName);
                alert.messageText = "Service Discovery Failure!"
                alert.informativeText = "It was not possible to retrieve disco#items details from \(parentItem.jid)\(node): \(error?.rawValue ?? "unknown error")";
                alert.addButton(withTitle: "OK");
                alert.run(completionHandler: { (response) in
                    // nothing to do..
                });
            }
            print("error", error as Any);
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
    }
    
}
