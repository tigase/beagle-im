//
//  AbstractChatViewController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 21.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class AbstractChatViewController: NSViewController, NSTableViewDataSource, ChatViewDataSourceDelegate {
    
    @IBOutlet var tableView: NSTableView!;
    @IBOutlet var messageField: NSTextField!;
    
    var dataSource: ChatViewDataSource!;
    var chat: DBChatProtocol!;

    var account: BareJID! {
        return chat.account;
    }
    
    var jid: BareJID! {
        return chat.jid.bareJid;
    }
    
    var hasFocus: Bool {
        return DispatchQueue.main.sync { view.window?.isKeyWindow ?? false };
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        self.view.wantsLayer = true;
        self.view.layer?.backgroundColor = NSColor.white.cgColor;
        self.dataSource.delegate = self;
        self.tableView.dataSource = self;
        
        NotificationCenter.default.addObserver(self, selector: #selector(didBecomeKeyWindow), name: NSWindow.didBecomeKeyNotification, object: nil);
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.tableView.reloadData();
        print("scrolling to", self.tableView.numberOfRows - 1)
        self.tableView.scrollRowToVisible(self.tableView.numberOfRows - 1);
        
        self.dataSource.refreshData();
    }
    
    override func viewDidAppear() {
        super.viewDidAppear();
        DispatchQueue.main.async {
            self.view.window!.makeFirstResponder(self.messageField);
        }
    }
    
    @objc func didBecomeKeyWindow(_ notification: Notification) {
        if chat.unread > 0 {
            DBChatHistoryStore.instance.markAsRead(for: account, with: jid);
        }
    }

    func itemAdded(at rows: IndexSet) {
        tableView.insertRows(at: rows, withAnimation: NSTableView.AnimationOptions.slideLeft)
        if (rows.contains(0)) {
            tableView.scrollRowToVisible(0);
        }
    }
    
    func itemUpdated(indexPath: IndexPath) {
        tableView.reloadData(forRowIndexes: [indexPath.item], columnIndexes: [0]);
    }
    
    func itemsReloaded() {
        tableView.reloadData();
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        return dataSource.count;
    }

}
