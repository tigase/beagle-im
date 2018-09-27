//
//  ChatsListView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 24.03.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class AbstractChatItem: ChatItemProtocol {
    
    let chat: DBChatProtocol;
    
    var name: String;
    var lastMessageText: String? {
        return chat.lastMessage;
    }
    var lastMessageTs: Date {
        return chat.timestamp;
    }
    var unread: Int {
        return chat.unread;
    }
    
    init(chat: DBChatProtocol, name: String) {
        self.chat = chat;
        self.name = name;
    }
}

class ChatItem: AbstractChatItem {
    
    init(chat: DBChatProtocol) {
        if let sessionObject = XmppService.instance.getClient(for: chat.account)?.sessionObject {
            super.init(chat: chat, name: RosterModule.getRosterStore(sessionObject).get(for: chat.jid)?.name ?? chat.jid.stringValue);
        } else {
            super.init(chat: chat, name: chat.jid.stringValue);
        }
    }
}

class GroupchatItem: AbstractChatItem {

    init(chat: DBChatProtocol) {
        super.init(chat: chat, name: chat.jid.stringValue);
    }
    
}

protocol ChatsListViewDataSourceDelegate: class {
    
    func itemsInserted(at: IndexSet, inParent: Any?);
    
    func itemsRemoved(at: IndexSet, inParent: Any?);
    
    func itemChanged(item: Any?);
    
    func itemMoved(from: Int, fromParent: Any?, to: Int, toParent: Any?);
    
    func reload();
}

class ChatsListViewController: NSViewController, NSOutlineViewDataSource, ChatsListViewDataSourceDelegate {
    
    static let CHAT_SELECTED = Notification.Name("chatSelected");
    
    @IBOutlet var outlineView: NSOutlineView!;
    
    var groups: [ChatsListGroupProtocol] = [];

    override func viewDidLoad() {
        self.groups = [ChatsListGroupGroupchat(delegate: self), ChatsListGroupChat(delegate: self)];
        outlineView.reloadData();
        self.view.wantsLayer = true;
        outlineView.expandItem(nil, expandChildren: true);
        
        NotificationCenter.default.addObserver(self, selector: #selector(chatSelected), name: ChatsListViewController.CHAT_SELECTED, object: nil);
    }
    
    override func viewWillAppear() {
//        self.view.window!.acceptsMouseMovedEvents = true;
        self.view.layer?.backgroundColor = outlineView.backgroundColor.cgColor;
    }
    
    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if let group = item as? ChatsListGroupProtocol {
            return group.count;
        }
        return groups.count;
    }
    
    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let group = item as? ChatsListGroupProtocol {
            return group.getChat(at: index)!;
        }
        return groups[index];
    }
    
    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard item is ChatsListGroupProtocol else {
            return false;
        }
        return true;
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if item is ChatsListGroupProtocol {
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item);
            } else {
                outlineView.expandItem(item);
            }
            return false;
        }
        if item is ChatItem {
            return true;
        }
        if item is GroupchatItem {
            return true;
        }
        return false;
    }
    
    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        return ChatsListTableRowView(frame: NSRect.zero);
    }
    
    func outlineViewSelectionDidChange(_ notification: Notification) {
        let selected = self.outlineView.selectedRow;
        print("selected row:", selected);
        let item = self.outlineView.item(atRow: selected);
        if let splitController = self.outlineView.window?.contentViewController as? NSSplitViewController {
            if let chat = item as? ChatItem {
                print("selected chat item:", chat.name);
                let chatController = self.storyboard!.instantiateController(withIdentifier: "ChatViewController") as! ChatViewController;
                chatController.chat = chat.chat;
                let item = NSSplitViewItem(viewController: chatController);
                if splitController.splitViewItems.count == 1 {
                    splitController.addSplitViewItem(item);
                } else {
                    splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    splitController.addSplitViewItem(item);
                }
            } else if let room = item as? GroupchatItem {
                let roomController = self.storyboard?.instantiateController(withIdentifier: "GroupchatViewController") as! GroupchatViewController;
                roomController.room = (room.chat as! DBChatStore.DBRoom);
                let item = NSSplitViewItem(viewController: roomController);
                if splitController.splitViewItems.count == 1 {
                    splitController.addSplitViewItem(item);
                } else {
                    splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                    splitController.addSplitViewItem(item);
                }
            } else if item == nil {
                let controller = self.storyboard!.instantiateController(withIdentifier: "EmptyViewController") as! NSViewController;
                splitController.removeSplitViewItem(splitController.splitViewItems[1]);
                splitController.addSplitViewItem(NSSplitViewItem(viewController: controller));
            }
        }
    }
    
    func reload() {
        outlineView.reloadData();
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
        let row = outlineView.row(forItem: item);
        guard row == 0 || row > 0 else {
            return;
        }
        let view = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false);
        // maybe we should update view?
        if let v = view as? ChatCellView, let i = item as? ChatItemProtocol {
            v.update(from: i);
            v.lastMessage.sizeToFit();
            v.superview!.layout();// = true;
//            v.needsLayout = true;
        }
    }
    
    @IBAction func openNewChatClicked(_ sender: NSButton) {
        print("open new chat cliecked");
        guard let group = (sender as? OutlineGroupItemButton)?.group else {
            return;
        }
        
        print("clicked button for", group.name);
        
        if groups.index(where: { it -> Bool in return it.name == group.name}) == 0 {
            guard let windowController = storyboard?.instantiateController(withIdentifier: "OpenGroupchatController") as? NSWindowController else {
                return;
            }
            view.window?.beginSheet(windowController.window!, completionHandler: nil);
        } else {
            guard let windowController = storyboard?.instantiateController(withIdentifier: "Open1On1ChatController") as? NSWindowController else {
                return;
            }
            view.window?.beginSheet(windowController.window!, completionHandler: nil);
        }
    }
    
    @objc func chatSelected(_ notification: Notification) {
        guard let chat = notification.object as? DBChatProtocol else {
            return;
        }

        self.groups.forEach { group in
            group.forChat(chat) { item in
                DispatchQueue.main.async {
                    let row = self.outlineView.row(forItem: item);
                    guard row >= 0 else {
                        return;
                    }
                    
                    self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false);
                }
            }
        }
//        DispatchQueue.main.async {
//            self.groups.forEach { group in
//                guard let item = group.selected(chat: chat) else {
//                    return;
//                }
//                
//                self.outlineView.selectRowIndexes(IndexSet(integer: self.outlineView.row(forItem: item)), byExtendingSelection: false);
//            }
//        }
    }
    
}

extension ChatsListViewController: NSOutlineViewDelegate {
    
    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        //var view: NSTableCellView?
        guard tableColumn!.identifier.rawValue == "ITEM1" else {
            return nil;
        }
        
        if let group = item as? ChatsListGroupProtocol {
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ChatGroupCell"), owner: self) as? NSTableCellView;
            if let textField = view?.textField {
                textField.stringValue = group.name;
                //textField.sizeToFit();
            }
            if let button = view?.subviews[1] as? OutlineGroupItemButton {
                button.group = group;
            }
            return view;
        } else if let chat = item as? ChatItemProtocol {
            let view = outlineView.makeView(withIdentifier: NSUserInterfaceItemIdentifier("ChatCell"), owner: self) as? ChatCellView;
            view?.avatar.backgroundColor = NSColor.selectedKnobColor;
            view?.update(from: chat);
            view?.lastMessage.preferredMaxLayoutWidth = self.outlineView.outlineTableColumn!.width - 80;
            view?.closeFunction = {
                switch chat.chat {
                case let c as DBChatStore.DBChat:
                    guard let messageModule: MessageModule = XmppService.instance.getClient(for: c.account)?.modulesManager.getModule(MessageModule.ID) else {
                        return;
                    }
                    _ = messageModule.chatManager.close(chat: c);
                case let r as DBChatStore.DBRoom:
                    guard let mucModule: MucModule = XmppService.instance.getClient(for: r.account)?.modulesManager.getModule(MucModule.ID) else {
                        return;
                    }
                    
                    mucModule.leave(room: r);
                default:
                    print("unknown type of chat!");
                }
            }
            view?.layout();
            return view;
        }
        return nil;
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
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();
//        self.window!.acceptsMouseMovedEvents = true;
//        trackingTag = self.addTrackingArea(NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited,.mouseMoved], owner: self, userInfo: nil));
//        trackingArea = NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited,.mouseMoved], owner: self, userInfo: nil);
//        if trackingArea != nil {
//            self.addTrackingArea(trackingArea!);
//        }
    }
    
    deinit {
//        self.removeTrackingRect(self.trackingTag!);
//        if trackingArea != nil {
//            self.removeTrackingArea(trackingArea!);
//        }
    }
    
    override func frameOfOutlineCell(atRow row: Int) -> NSRect {
        return NSRect.zero;
    }
    
    override func mouseEntered(with event: NSEvent) {
        print("mouse entered");
        mouseInside = true;
        updateMouseOver(from: event);
    }
    
    override func mouseExited(with event: NSEvent) {
        print("mouse exited");
        mouseInside = false;
        updateMouseOver(from: event);
    }
    
    override func mouseMoved(with event: NSEvent) {
        guard mouseInside else {
            return;
        }

        updateMouseOver(from: event);
    }

    fileprivate func updateMouseOver(from event: NSEvent) {
        let prevMouseOverRow = self.mouseOverRow;
        self.mouseOverRow = self.row(at: self.convert(event.locationInWindow, from: nil));
        guard mouseOverRow != prevMouseOverRow else {
            return;
        }
        if prevMouseOverRow >= 0 {
            if let chatView = self.rowView(atRow: prevMouseOverRow, makeIfNecessary: false)?.subviews.last as? ChatCellView {
                chatView.setMouseHovers(false);
            }
            self.setNeedsDisplay(self.rect(ofRow: prevMouseOverRow));
        }
        if mouseOverRow >= 0 {
            if let chatView = self.rowView(atRow: mouseOverRow, makeIfNecessary: false)?.subviews.last as? ChatCellView {
                chatView.setMouseHovers(true);
            }
            self.setNeedsDisplay(self.rect(ofRow: mouseOverRow));
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

}
