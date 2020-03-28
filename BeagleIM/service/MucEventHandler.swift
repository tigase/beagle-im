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

    static let instance = MucEventHandler();
    
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
            InvitationManager.instance.mucJoined(on: e.sessionObject.userBareJid!, roomJid: room.roomJid);
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
                    VCardManager.instance.refreshVCard(for: room.roomJid, on: room.account, completionHandler: nil);
                }
            }

            DBChatHistoryStore.instance.append(for: room.account, message: e.message, source: .stream);
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
            
            DispatchQueue.main.async {
                let alert = Alert();
                alert.messageText = "Room \(e.room.roomJid.stringValue)";
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
                        let roomJid = e.room.roomJid;
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
            
            InvitationManager.instance.addMucInvitation(for: e.sessionObject.userBareJid!, roomJid: e.invitation.roomJid, invitation: e.invitation);
            
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
    
    open func sendPrivateMessage(room: DBChatStore.DBRoom, recipientNickname: String, body: String) {
        let message = room.createPrivateMessage(body, recipientNickname: recipientNickname);
        DBChatHistoryStore.instance.appendItem(for: room.account, with: room.roomJid, state: .outgoing, authorNickname: room.nickname, authorJid: nil, recipientNickname: recipientNickname, participantId: nil, type: .message, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: body, encryption: .none, encryptionFingerprint: nil, appendix: nil, linkPreviewAction: .auto, completionHandler: nil);
        room.context.writer?.write(message);
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
