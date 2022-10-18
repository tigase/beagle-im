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
import Martin

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
        guard (XmppService.instance.getClient(for: row.account)?.state ?? .disconnected()) == .connected() else {
            item.isEnabled = false;
            return true;
        }
        guard let identifier = item.identifier else {
            item.isEnabled = true;
            item.submenu?.items.forEach { subitem in
                subitem.isEnabled = true;
            }
        
            return true;
        }
        
        switch identifier.rawValue {
        case "RoomInvite":
            let rooms = XmppService.instance.clients.values.filter(\.isConnected).flatMap({ client -> [Room] in
                DBChatStore.instance.rooms(for: client).filter({ $0.occupant(nickname: $0.nickname)?.role ?? .none != .none })
            });
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
        
        let alert = NSAlert();
        alert.messageText = NSLocalizedString("Enter new name", comment: "alert window title") + ":";
        alert.icon = NSImage(named: NSImage.userName);//AvatarManager.instance.avatar(for: item.jid, on: item.account).rounded();
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        
//        let textField = NSTextField(string: item.name ?? item.jid.stringValue);
        let textField = NSTextField(frame: NSRect(x: 0, y:0, width: 300, height: 24));
        textField.stringValue = item.displayName;
        alert.accessoryView = textField;
        
        alert.beginSheetModal(for: self.view.window!) { (response) in
            if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                guard let rosterModule: RosterModule = XmppService.instance.getClient(for: item.account)?.module(.roster) else {
                    return;
                }

                let oldItem = DBRosterStore.instance.item(for: item.account, jid: JID(item.jid));
                let groups = oldItem?.groups ?? [];
                Task {
                    do {
                        _ = try await rosterModule.updateItem(jid: JID(item.jid), name: textField.stringValue.isEmpty ? nil : textField.stringValue, groups: groups);
                    } catch {
                        await MainActor.run(body: {
                            guard let window = self.view.window else {
                                return;
                            }
                            let alert = NSAlert();
                            alert.alertStyle = .warning;
                            alert.messageText = NSLocalizedString("Modifying contact", comment: "roster controller");
                            alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to modify contact %@. Received an error: %@", comment: "roster controller"), item.jid.description, error.localizedDescription);
                            alert.beginSheetModal(for: window, completionHandler: { _ in });
                        })
                    }
                }
            }
        }
    }
    
    @IBAction func authorizationResendTo(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        XmppService.instance.getClient(for: item.account)?.module(.presence).subscribed(by: JID(item.jid));
        //presenceModule.sendInitialPresence();
    }
    
    @IBAction func authorizationRequestFrom(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        XmppService.instance.getClient(for: item.account)?.module(.presence).subscribe(to: JID(item.jid));
    }
    
    @IBAction func authorizationRemoveFrom(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        
        XmppService.instance.getClient(for: item.account)?.module(.presence).unsubscribed(by: JID(item.jid));
    }
    
    @IBAction func removeSelected(_ sender: NSMenuItem) {
        let item = self.getItem(at: self.contactsTableView.clickedRow);
        guard let rosterModule = XmppService.instance.getClient(for: item.account)?.module(.roster) else {
            return;
        }
        Task {
            do {
                _ = try await rosterModule.removeItem(jid: item.jid.jid());
            } catch {
                await MainActor.run(body: {
                    guard let window = self.view.window else {
                        return;
                    }
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Removing contact", comment: "roster controller");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to remove contact %@. Received an error: %@", comment: "roster controller"), item.jid.description, error.localizedDescription);
                    alert.beginSheetModal(for: window, completionHandler: { _ in });
                })
            }
        }
    }
 
    fileprivate class InviteToRoomMenuItem: NSMenuItem {
        
        let room: Room;
        let invitee: BareJID;
        
        init(room: Room, invitee: BareJID) {
            self.room = room;
            self.invitee = invitee;
            super.init(title: room.roomJid.description, action: #selector(invite), keyEquivalent: "");
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
