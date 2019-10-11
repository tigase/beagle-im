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

class MucEventHandler: XmppServiceEventHandler {
    
    static let ROOM_STATUS_CHANGED = Notification.Name("roomStatusChanged");
    static let ROOM_NAME_CHANGED = Notification.Name("roomNameChanged");
    static let ROOM_OCCUPANTS_CHANGED = Notification.Name("roomOccupantsChanged");

    let events: [Event] = [ SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE, MucModule.OccupantChangedNickEvent.TYPE, MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.PresenceErrorEvent.TYPE, MucModule.InvitationReceivedEvent.TYPE, MucModule.InvitationDeclinedEvent.TYPE, PEPBookmarksModule.BookmarksChangedEvent.TYPE ];
    
    func handle(event: Event) {
        switch event {
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            if let mucModule: MucModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MucModule.ID) {
                mucModule.roomsManager.getRooms().forEach { (room) in
                    _ = room.rejoin();
                    NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
                }
            }
        case let e as MucModule.YouJoinedEvent:
            guard let room = e.room as? DBChatStore.DBRoom else {
                return;
            }
            NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
            updateRoomName(room: room);
        case let e as MucModule.RoomClosedEvent:
            guard let room = e.room as? DBChatStore.DBRoom else {
                return;
            }
            NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
        case let e as MucModule.MessageReceivedEvent:
            guard let room = e.room as? DBChatStore.DBRoom else {
                return;
            }
            
            if e.message.findChild(name: "subject") != nil {
                room.subject = e.message.subject;
                NotificationCenter.default.post(name: MucEventHandler.ROOM_STATUS_CHANGED, object: room);
            }
            
            if let xUser = XMucUserElement.extract(from: e.message) {
                if xUser.statuses.contains(104) {
                    self.updateRoomName(room: room);
                }
            }
            
            guard let body = e.message.body else {
                return;
            }
            
            let authorJid = e.nickname == nil ? nil : room.presences[e.nickname!]?.jid?.bareJid;
            
            DBChatHistoryStore.instance.appendItem(for: room.account, with: room.roomJid, state: ((e.nickname == nil) || (room.nickname != e.nickname!)) ? .incoming_unread : .outgoing, authorNickname: e.nickname, authorJid: authorJid, type: .message, timestamp: e.timestamp, stanzaId: e.message.id, data: body, encryption: MessageEncryption.none, encryptionFingerprint: nil, completionHandler: nil);
        case let e as MucModule.AbstractOccupantEvent:
            NotificationCenter.default.post(name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: e);
            if let photoHash = e.presence.vcardTempPhoto {
                if e.occupant.jid == nil {
                    let jid = JID(e.room.roomJid, resource: e.occupant.nickname);
                    if !AvatarManager.instance.hasAvatar(withHash: photoHash) {
                        guard let vcardTempModule: VCardTempModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(VCardTempModule.ID) else {
                            return;
                        }
                        
                        vcardTempModule.retrieveVCard(from: jid, onSuccess: { (vcard) in
                            vcard.photos.forEach { (photo) in
                                AvatarManager.fetchData(photo: photo) { (result) in
                                    guard let data = result else {
                                        return;
                                    }
                                    AvatarManager.instance.storeAvatar(data: data);
                                }
                            }
                        }, onError: { (errorCondition) in
                            print("failed to retrieve vcard from", jid, "error:", errorCondition as Any);
                        })
                    }
                }
            }
        case let e as MucModule.PresenceErrorEvent:
            guard let error = MucModule.RoomError.from(presence: e.presence), e.nickname == nil || e.nickname! == e.room.nickname else {
                return;
            }
            print("received error from room:", e.room as Any, ", error:", error)
            
            if #available(OSX 10.14, *) {
                let content = UNMutableNotificationContent();
                content.title = "Room \(e.room.roomJid.stringValue)";
                content.body = "Could not join room. Reason:\n\(error.reason)";
                content.sound = UNNotificationSound.defaultCritical;
                if error != .banned && error != .registrationRequired {
                    content.userInfo = ["account": e.sessionObject.userBareJid!.stringValue, "roomJid": e.room.roomJid.stringValue, "nickname": e.room.nickname, "id": "room-join-error"];
                }
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
                UNUserNotificationCenter.current().add(request) { (error) in
                    print("could not show notification:", error as Any);
                }
            } else {
                let notification = NSUserNotification();
                notification.identifier = UUID().uuidString;
                notification.title = "Room \(e.room.roomJid.stringValue)";
                notification.informativeText = "Could not join room. Reason:\n\(error.reason)";
                notification.soundName = NSUserNotificationDefaultSoundName;
                notification.contentImage = NSImage(named: NSImage.userGroupName);
                if error != .banned && error != .registrationRequired {
                    notification.userInfo = ["account": e.sessionObject.userBareJid!.stringValue, "roomJid": e.room.roomJid.stringValue, "nickname": e.room.nickname, "id": "room-join-error"];
                }
                NSUserNotificationCenter.default.deliver(notification);
            }

            guard let mucModule: MucModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MucModule.ID) else {
                return;
            }
            mucModule.leave(room: e.room);
        case let e as MucModule.InvitationReceivedEvent:
            guard let mucModule: MucModule = XmppService.instance.getClient(for: e.sessionObject.userBareJid!)?.modulesManager.getModule(MucModule.ID), let roomName = e.invitation.roomJid.localPart else {
                return;
            }
            
            guard !mucModule.roomsManager.contains(roomJid: e.invitation.roomJid) else {
                mucModule.decline(invitation: e.invitation, reason: nil);
                return;
            }

            let alert = Alert();
            alert.messageText = "Invitation to groupchat";
            if let inviter = e.invitation.inviter {
                let name = XmppService.instance.clients.values.flatMap({ (client) -> [String] in
                    guard let n = client.rosterStore?.get(for: inviter)?.name else {
                        return [];
                    }
                    return ["\(n) (\(inviter))"];
                }).first ?? inviter.stringValue;
                alert.informativeText = "User \(name) invited you (\(e.sessionObject.userBareJid!)) to the groupchat \(e.invitation.roomJid)";
            } else {
                alert.informativeText = "You (\(e.sessionObject.userBareJid!)) were invited to the groupchat \(e.invitation.roomJid)";
            }
            alert.addButton(withTitle: "Accept");
            alert.addButton(withTitle: "Decline");
            
            DispatchQueue.main.async {
                alert.run { (response) in
                    if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                        let nickname = AccountManager.getAccount(for: e.sessionObject.userBareJid!)?.nickname ?? e.sessionObject.userBareJid!.localPart!;
                        _ = mucModule.join(roomName: roomName, mucServer: e.invitation.roomJid.domain, nickname: nickname, password: e.invitation.password);
                        
                        PEPBookmarksModule.updateOrAdd(for: e.sessionObject.userBareJid!, bookmark: Bookmarks.Conference(name: roomName, jid: JID(BareJID(localPart: roomName, domain: e.invitation.roomJid.domain)), autojoin: true, nick: nickname, password: e.invitation.password));
                    } else {
                        mucModule.decline(invitation: e.invitation, reason: nil);
                    }
                }
            }
            
            break;
        case let e as MucModule.InvitationDeclinedEvent:
            if #available(OSX 10.14, *) {
                let content = UNMutableNotificationContent();
                content.title = "Invitation rejected";
                let name = XmppService.instance.clients.values.flatMap({ (client) -> [String] in
                    guard let n = e.invitee != nil ? client.rosterStore?.get(for: e.invitee!)?.name : nil else {
                        return [];
                    }
                    return [n];
                }).first ?? e.invitee?.stringValue ?? "";
                
                content.body = "User \(name) rejected invitation to room \(e.room.roomJid)";
                content.sound = UNNotificationSound.default;
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
                UNUserNotificationCenter.current().add(request) { (error) in
                    print("could not show notification:", error as Any);
                }
            } else {
                let notification = NSUserNotification();
                notification.identifier = UUID().uuidString;
                notification.title = "Invitation rejected";
                let name = XmppService.instance.clients.values.flatMap({ (client) -> [String] in
                    guard let n = e.invitee != nil ? client.rosterStore?.get(for: e.invitee!)?.name : nil else {
                        return [];
                    }
                    return [n];
                }).first ?? e.invitee?.stringValue ?? "";
                
                notification.informativeText = "User \(name) rejected invitation to room \(e.room.roomJid)";
                notification.soundName = NSUserNotificationDefaultSoundName;
                notification.contentImage = NSImage(named: NSImage.userGroupName);
                NSUserNotificationCenter.default.deliver(notification);
            }
        case let e as PEPBookmarksModule.BookmarksChangedEvent:
            guard let client = XmppService.instance.getClient(for: e.sessionObject.userBareJid!), let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID), Settings.enableBookmarksSync.bool() else {
                return;
            }
            
            e.bookmarks?.items.filter { bookmark in bookmark is Bookmarks.Conference }.map { bookmark in bookmark as! Bookmarks.Conference }.filter { bookmark in
                return !mucModule.roomsManager.contains(roomJid: bookmark.jid.bareJid);
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
    
    fileprivate func updateRoomName(room: DBChatStore.DBRoom) {
        guard let client = XmppService.instance.getClient(for: room.account), let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        
        discoModule.getInfo(for: room.jid, onInfoReceived: { (node, identities, features) in
            let newName = identities.first(where: { (identity) -> Bool in
                return identity.category == "conference";
            })?.name?.trimmingCharacters(in: .whitespacesAndNewlines);
            
            DBChatStore.instance.updateChatName(for: room.account, with: room.roomJid, name: (newName?.isEmpty ?? true) ? nil : newName);
        }, onError: nil);
    }
}
