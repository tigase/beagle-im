//
// RosterViewController_ContextMenu.swift
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

extension RosterViewController: NSMenuDelegate {
 
    func numberOfItems(in menu: NSMenu) -> Int {
        return menu.items.count;
    }
    
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool {
        guard self.contactsTableView.clickedRow >= 0 else {
            item.isHidden = true;
            return true;
        }
        
        item.isHidden = false;
        
        let row = self.getItem(at: self.contactsTableView.clickedRow);
        guard (XmppService.instance.getClient(for: row.account)?.state ?? .disconnected) == .connected else {
            item.isEnabled = false;
            return true;
        }
        guard let identifier = item.identifier else {
            item.isEnabled = true;
            item.submenu?.items.forEach { subitem in
                subitem.isEnabled = true;
            }
            print("menu item:", item.title)
        
            return true;
        }
        
        switch identifier.rawValue {
        case "RoomInvite":
            let rooms = XmppService.instance.clients.values.filter({ (client) -> Bool in
                return client.state == .connected;
            }).map { (client) -> MucModule? in
                return client.modulesManager.getModule(MucModule.ID);
                }.flatMap { (mucModule) -> [Room] in
                    return mucModule?.roomsManager.getRooms().filter({ (room) -> Bool in
                        return (room.presences[room.nickname]?.role ?? .none) != .none;
                    }) ?? [];
            };
            item.isEnabled = rooms.count > 0;
            item.isHidden = rooms.count == 0;
            item.submenu?.removeAllItems();
            rooms.forEach { room in
                let roomItem = InviteToRoomMenuItem(room: room, invitee: row.jid);
                roomItem.isEnabled = true;
                item.submenu?.addItem(roomItem);
            }
            break;
        default:
            break;
        }
        return true;
    }
    
    @IBAction func detailsSelected(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        let storyboard = NSStoryboard(name: "ConversationDetails", bundle: nil);
        guard let viewController = storyboard.instantiateController(withIdentifier: "ContactDetailsViewController") as? ContactDetailsViewController else {
            return;
        }
        viewController.account = item.account;
        viewController.jid = item.jid;
        
        let popover = NSPopover();
        popover.contentViewController = viewController;
        popover.behavior = .semitransient;
        popover.animates = true;
        let rect = self.contactsTableView.frameOfCell(atColumn: 0, row: self.contactsTableView.clickedRow);
        popover.show(relativeTo: rect, of: self.contactsTableView, preferredEdge: .maxX);

    }
    
    @IBAction func renameSelected(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        print("rename item:", item.account, item.jid);
        
        let alert = NSAlert();
        alert.messageText = "Enter new name:";
        alert.icon = NSImage(named: NSImage.userName);//AvatarManager.instance.avatar(for: item.jid, on: item.account).rounded();
        alert.addButton(withTitle: "OK");
        alert.addButton(withTitle: "Cancel");
        
//        let textField = NSTextField(string: item.name ?? item.jid.stringValue);
        let textField = NSTextField(frame: NSRect(x: 0, y:0, width: 300, height: 24));
        textField.stringValue = item.name ?? item.jid.stringValue;
        alert.accessoryView = textField;
        
        alert.beginSheetModal(for: self.view.window!) { (response) in
            if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                guard let rosterModule: RosterModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(RosterModule.ID) else {
                    return;
                }

                let jid = JID(item.jid);
                guard let ri = rosterModule.store.get(for: jid) else {
                    return;
                }
                
                rosterModule.store.update(item: ri, name: textField.stringValue.isEmpty ? nil : textField.stringValue, completionHandler: nil);
            }
        }
    }
    
    @IBAction func authorizationResendTo(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(PresenceModule.ID) else {
            return;
        }
        
        presenceModule.subscribed(by: JID(item.jid));
        //presenceModule.sendInitialPresence();
    }
    
    @IBAction func authorizationRequestFrom(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(PresenceModule.ID) else {
            return;
        }
        
        presenceModule.subscribe(to: JID(item.jid));
    }
    
    @IBAction func authorizationRemoveFrom(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        guard let presenceModule: PresenceModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(PresenceModule.ID) else {
            return;
        }
        
        presenceModule.unsubscribed(by: JID(item.jid));
    }
    
    @IBAction func removeSelected(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        guard let rosterModule: RosterModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(RosterModule.ID) else {
            return;
        }
        
        rosterModule.store.remove(jid: JID(item.jid), completionHandler: nil);
    }
 
    fileprivate class InviteToRoomMenuItem: NSMenuItem {
        
        let room: Room;
        let invitee: BareJID;
        
        init(room: Room, invitee: BareJID) {
            self.room = room;
            self.invitee = invitee;
            super.init(title: room.roomJid.stringValue, action: #selector(invite), keyEquivalent: "");
            self.target = self;
        }
        
        required init(coder decoder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc func invite() {
            room.invite(JID(invitee), reason: nil);
        }
        
    }
}
