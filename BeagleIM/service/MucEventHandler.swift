//
// MucEventHandler.swift
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
import UserNotifications
import Combine

class MucEventHandler: XmppServiceEventHandler {
    
    static let ROOM_STATUS_CHANGED = Notification.Name("roomStatusChanged");
    static let ROOM_NAME_CHANGED = Notification.Name("roomNameChanged");
    static let ROOM_OCCUPANTS_CHANGED = Notification.Name("roomOccupantsChanged");

    static let instance = MucEventHandler();
    
    let events: [Event] = [ MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE, MucModule.OccupantChangedNickEvent.TYPE, MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.PresenceErrorEvent.TYPE, MucModule.InvitationReceivedEvent.TYPE, MucModule.InvitationDeclinedEvent.TYPE, PEPBookmarksModule.BookmarksChangedEvent.TYPE ];
    
    func register(for client: XMPPClient, cancellables: inout Set<AnyCancellable>) {
        client.$state.sink(receiveValue: { [weak client] state in
            guard let client = client, case .connected(let resumed) = state, !resumed else {
                return;
            }
            client.module(.muc).roomManager.rooms(for: client).forEach { (room) in
                // first we need to check if room supports MAM
                client.module(.disco).getInfo(for: JID(room.jid), completionHandler: { result in
                    var mamVersions: [MessageArchiveManagementModule.Version] = [];
                    switch result {
                    case .success(let info):
                        mamVersions = info.features.map({ MessageArchiveManagementModule.Version(rawValue: $0) }).filter({ $0 != nil}).map({ $0! });
                    default:
                        break;
                    }
                    if let timestamp = (room as? Room)?.timestamp {
                        if !mamVersions.isEmpty {
                            _ = room.rejoin(fetchHistory: .skip, onJoined: { [weak client] room in
                                guard let client = client else {
                                    return;
                                }
                                MessageEventHandler.syncMessages(for: client, version: mamVersions.contains(.MAM2) ? .MAM2 : .MAM1, componentJID: JID(room.jid), since: timestamp);
                            });
                        } else {
                            _ = room.rejoin(fetchHistory: .from(timestamp), onJoined: nil);
                        }
                    } else {
                        _ = room.rejoin(fetchHistory: .initial, onJoined: nil);
                    }
                    NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
                });
            }
        }).store(in: &cancellables);
    }
    
    func handle(event: Event) {
        switch event {
        case let e as MucModule.YouJoinedEvent:
            guard let room = e.room as? Room else {
                return;
            }
            NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
            InvitationManager.instance.mucJoined(on: e.sessionObject.userBareJid!, roomJid: room.roomJid);
            updateRoomName(room: room);
        case let e as MucModule.RoomClosedEvent:
            guard let room = e.room as? Room else {
                return;
            }
            NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
        case let e as MucModule.MessageReceivedEvent:
            guard let room = e.room as? Room else {
                return;
            }
            
            if e.message.findChild(name: "subject") != nil {
                room.subject = e.message.subject;
                NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
            }

            if let xUser = XMucUserElement.extract(from: e.message) {
                if xUser.statuses.contains(104) {
                    self.updateRoomName(room: room);
                    VCardManager.instance.refreshVCard(for: room.roomJid, on: room.account, completionHandler: nil);
                }
            }

            DBChatHistoryStore.instance.append(for: room, message: e.message, source: .stream);
        case let e as MucModule.AbstractOccupantEvent:
            NotificationCenter.default.post(name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: e);
            // Photo hash support is in AvatarEventHandler!!
        case let e as MucModule.PresenceErrorEvent:
            guard let error = MucModule.RoomError.from(presence: e.presence), e.nickname == nil || e.nickname! == e.room.nickname else {
                return;
            }
            print("received error from room:", e.room as Any, ", error:", error)
            
            DispatchQueue.main.async {
                let alert = Alert();
                alert.messageText = "Room \(e.room.jid.stringValue)";
                alert.informativeText = "Could not join room. Reason:\n\(error.reason)";
                alert.icon = NSImage(named: NSImage.userGroupName);
                alert.addButton(withTitle: "OK");
                alert.run(completionHandler: { response in
                    if error != .banned && error != .registrationRequired {
                        let storyboard = NSStoryboard(name: "Main", bundle: nil);
                        guard let windowController = storyboard.instantiateController(withIdentifier: "OpenGroupchatController") as? NSWindowController else {
                            return;
                        }
                        guard let openRoomController = windowController.contentViewController as? OpenGroupchatController else {
                            return;
                        }
                        let roomJid = e.room.jid;
                        openRoomController.searchField.stringValue = roomJid.stringValue;
                        openRoomController.componentJids = [BareJID(roomJid.domain)];
                        openRoomController.account = e.sessionObject.userBareJid!;
                        openRoomController.nicknameField.stringValue = e.room.nickname;
                        guard let window = (NSApplication.shared.delegate as? AppDelegate)?.mainWindowController?.window else {
                            return;
                        }
                        window.windowController?.showWindow(self);
                        window.beginSheet(windowController.window!, completionHandler: nil);
                    }
                })
            }
            
            e.context.module(.muc).leave(room: e.room);
        case let e as MucModule.InvitationReceivedEvent:
            guard e.invitation.roomJid.localPart != nil else {
                return;
            }
            
            let mucModule = e.context.module(.muc);
            guard mucModule.roomManager.room(for: e.context, with: e.invitation.roomJid) == nil else {
                mucModule.decline(invitation: e.invitation, reason: nil);
                return;
            }
            
            InvitationManager.instance.addMucInvitation(for: e.sessionObject.userBareJid!, roomJid: e.invitation.roomJid, invitation: e.invitation);
            
            break;
        case let e as MucModule.InvitationDeclinedEvent:
            if #available(OSX 10.14, *) {
                let content = UNMutableNotificationContent();
                content.title = "Invitation rejected";
                let name = XmppService.instance.clients.values.compactMap({ (client) -> String? in
                    if let invitee = e.invitee {
                        return DBRosterStore.instance.item(for: client, jid: invitee)?.name;
                    } else {
                        return nil;
                    }
                }).first ?? e.invitee?.stringValue ?? "";
                
                content.body = "User \(name) rejected invitation to room \(e.room.jid)";
                content.sound = UNNotificationSound.default;
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
                UNUserNotificationCenter.current().add(request) { (error) in
                    print("could not show notification:", error as Any);
                }
            } else {
                let notification = NSUserNotification();
                notification.identifier = UUID().uuidString;
                notification.title = "Invitation rejected";
                let name = XmppService.instance.clients.values.compactMap({ (client) -> String? in
                    if let invitee = e.invitee {
                        return DBRosterStore.instance.item(for: client, jid: invitee)?.name;
                    } else {
                        return nil;
                    }
                }).first ?? e.invitee?.stringValue ?? "";
                
                notification.informativeText = "User \(name) rejected invitation to room \(e.room.jid)";
                notification.soundName = NSUserNotificationDefaultSoundName;
                notification.contentImage = NSImage(named: NSImage.userGroupName);
                NSUserNotificationCenter.default.deliver(notification);
            }
        case let e as PEPBookmarksModule.BookmarksChangedEvent:
            guard Settings.enableBookmarksSync else {
                return;
            }
            
            let mucModule = e.context.module(.muc);
            e.bookmarks?.items.filter { bookmark in bookmark is Bookmarks.Conference }.map { bookmark in bookmark as! Bookmarks.Conference }.filter { bookmark in
                return mucModule.roomManager.room(for: e.context, with: bookmark.jid.bareJid) == nil;
                }.forEach({ (bookmark) in
                    guard let nick = bookmark.nick, bookmark.autojoin else {
                        return;
                    }
                    _ = mucModule.join(roomName: bookmark.jid.localPart!, mucServer: bookmark.jid.domain, nickname: nick, password: bookmark.password);
                });
        default:
            break;
        }
    }
        
    fileprivate func updateRoomName(room: Room) {
        room.context?.module(.disco).getInfo(for: JID(room.jid), completionHandler: { result in
            switch result {
            case .success(let info):
                let newName = info.identities.first(where: { (identity) -> Bool in
                    return identity.category == "conference";
                })?.name?.trimmingCharacters(in: .whitespacesAndNewlines);
                
                room.updateRoom(name: newName);
            case .failure(_):
                break;
            }
        });
    }
}
