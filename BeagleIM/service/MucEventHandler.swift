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

class MucEventHandler: XmppServiceExtension {

    static let instance = MucEventHandler();
    
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
                        mamVersions = info.features.compactMap({ MessageArchiveManagementModule.Version(rawValue: $0) });
                    default:
                        break;
                    }
                    if let timestamp = (room as? Room)?.timestamp {
                        if !mamVersions.isEmpty {
                            room.rejoin(fetchHistory: .skip).handle({ result in
                                guard case .success(let r) = result else {
                                    return;
                                }
                                switch r {
                                case .created(let room), .joined(let room):
                                    guard let client = room.context as? XMPPClient else {
                                        return;
                                    }
                                    MessageEventHandler.syncMessages(for: client, version: mamVersions.contains(.MAM2) ? .MAM2 : .MAM1, componentJID: JID(room.jid), since: timestamp);
                                }
                            });
                        } else {
                            _ = room.rejoin(fetchHistory: .from(timestamp));
                        }
                    } else {
                        _ = room.rejoin(fetchHistory: .initial);
                    }
                });
            }
        }).store(in: &cancellables);
        client.module(.muc).messagesPublisher.sink(receiveValue: { e in
            let room = e.room as! Room;
            if let subject = e.message.subject {
                // how can we find room from here?
                room.subject = subject;
            }
            if let xUser = XMucUserElement.extract(from: e.message) {
                if xUser.statuses.contains(104) {
                    self.updateRoomName(room: room);
                    VCardManager.instance.refreshVCard(for: room.roomJid, on: room.account, completionHandler: nil);
                }
            }
            DBChatHistoryStore.instance.append(for: room, message: e.message, source: .stream);
        }).store(in: &cancellables);
        client.module(.muc).inivitationsPublisher.sink(receiveValue: { [weak client] invitation in
            guard let client = client, invitation.roomJid.localPart != nil else {
                return;
            }
            
            let mucModule = client.module(.muc);
            guard mucModule.roomManager.room(for: client, with: invitation.roomJid) == nil else {
                mucModule.decline(invitation: invitation, reason: nil);
                return;
            }
            
            InvitationManager.instance.addMucInvitation(for: client.userBareJid, roomJid: invitation.roomJid, invitation: invitation);
        }).store(in: &cancellables);
        client.module(.pepBookmarks).$currentBookmarks.sink(receiveValue: { [weak client] bookmarks in
            guard let client = client else {
                return;
            }
            let mucModule = client.module(.muc);
            bookmarks.items.compactMap({ $0 as? Bookmarks.Conference }).filter { bookmark in
                return mucModule.roomManager.room(for: client, with: bookmark.jid.bareJid) == nil;
                }.forEach({ (bookmark) in
                    guard let nick = bookmark.nick, bookmark.autojoin else {
                        return;
                    }
                    _ = mucModule.join(roomName: bookmark.jid.localPart!, mucServer: bookmark.jid.domain, nickname: nick, password: bookmark.password);
                });
        }).store(in: &cancellables);
    }
    
    static func showJoinError(_ err: XMPPError, for room: Room) {
        guard let error = MucModule.RoomError.from(error: err), let context = room.context else {
            return;
        }
        print("received error from room:", room, ", error:", error)
        
        DispatchQueue.main.async {
            let alert = Alert();
            alert.messageText = "Room \(room.jid.stringValue)";
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
                    let roomJid = room.jid;
                    openRoomController.searchField.stringValue = roomJid.stringValue;
                    openRoomController.componentJids = [BareJID(roomJid.domain)];
                    openRoomController.account = context.userBareJid;
                    openRoomController.nicknameField.stringValue = room.nickname;
                    guard let window = (NSApplication.shared.delegate as? AppDelegate)?.mainWindowController?.window else {
                        return;
                    }
                    window.windowController?.showWindow(self);
                    window.beginSheet(windowController.window!, completionHandler: nil);
                }
            })
        }
        
        context.module(.muc).leave(room: room);
    }
        
    public func updateRoomName(room: Room) {
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

class CustomMucModule: MucModule {
    
    override func join(room: RoomProtocol, fetchHistory: RoomHistoryFetch) -> Future<RoomJoinResult, XMPPError> {
        return Future({ promise in
            super.join(room: room, fetchHistory: fetchHistory).handle({ result in
                switch result {
                case .success(_):
                    MucEventHandler.instance.updateRoomName(room: room as! Room);
                case .failure(_):
                    break;
                }
                promise(result);
            })
        });
    }
    
}
