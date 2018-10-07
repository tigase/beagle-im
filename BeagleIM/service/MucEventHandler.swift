//
//  MucEventHandler.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 27/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class MucEventHandler: XmppServiceEventHandler {
    
    static let ROOM_STATUS_CHANGED = Notification.Name("roomStatusChanged");
    static let ROOM_OCCUPANTS_CHANGED = Notification.Name("roomOccupantsChanged");

    let events: [Event] = [ SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, MucModule.YouJoinedEvent.TYPE, MucModule.RoomClosedEvent.TYPE, MucModule.MessageReceivedEvent.TYPE, MucModule.OccupantChangedNickEvent.TYPE, MucModule.OccupantChangedPresenceEvent.TYPE, MucModule.OccupantLeavedEvent.TYPE, MucModule.OccupantComesEvent.TYPE, MucModule.PresenceErrorEvent.TYPE, MucModule.InvitationReceivedEvent.TYPE, MucModule.InvitationDeclinedEvent.TYPE ];
    
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
            NotificationCenter.default.post(name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: room.presences[room.nickname]);
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
            
            guard let body = e.message.body else {
                return;
            }
            
            let authorJid = e.nickname == nil ? nil : room.presences[e.nickname!]?.jid?.bareJid;
            
            DBChatHistoryStore.instance.appendItem(for: room.account, with: room.roomJid, state: ((e.nickname == nil) || (room.nickname != e.nickname!)) ? .incoming_unread : .outgoing, authorNickname: e.nickname, authorJid: authorJid, type: .message, timestamp: e.timestamp, stanzaId: e.message.id, data: body, completionHandler: nil);
        case let e as MucModule.AbstractOccupantEvent:
            NotificationCenter.default.post(name: MucEventHandler.ROOM_OCCUPANTS_CHANGED, object: e);
        case let e as MucModule.PresenceErrorEvent:
            guard let error = MucModule.RoomError.from(presence: e.presence), e.nickname == nil || e.nickname! == e.room.nickname else {
                return;
            }
            print("received error from room:", e.room, ", error:", error)
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
                    } else {
                        mucModule.decline(invitation: e.invitation, reason: nil);
                    }
                }
            }
            
            break;
        case let e as MucModule.InvitationDeclinedEvent:
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
        default:
            break;
        }
    }
    
}
