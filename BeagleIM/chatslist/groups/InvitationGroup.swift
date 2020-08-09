//
// InvitationGroup.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import TigaseSwift

class InvitationGroup: ChatsListGroupProtocol {
    
    var items: [InvitationItem] = [];
    
    let name: String = "Invitations";
    
    var count: Int {
        return items.count;
    }
    
    let canOpenChat: Bool = false;
    
    weak var delegate: ChatsListViewController?;
    
    init(delegate: ChatsListViewController, items: [InvitationItem]) {
        self.delegate = delegate;
        self.items = items;
        NotificationCenter.default.addObserver(self, selector: #selector(invitationsChanged(_:)), name: InvitationManager.INVITATIONS_CHANGED, object: nil);
    }
    
    func getItem(at: Int) -> ChatsListItemProtocol? {
        return items[at];
    }
    
    func forChat(_ chat: DBChatProtocol, execute: @escaping (ChatItemProtocol) -> Void) {
        // nothing to do...
    }
    
    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ChatItemProtocol) -> Void) {
        // nothing to do..
    }
    
    @objc func invitationsChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            let oldItems = self.items;
            let items = InvitationManager.instance.items;
            var added = false;
            if oldItems.isEmpty && !items.isEmpty {
                added = true;
                self.delegate?.groups.insert(self, at: 0);
                self.delegate?.itemsInserted(at: IndexSet(integer: 0), inParent: nil);
            } else if items.isEmpty && !oldItems.isEmpty {
                self.delegate?.groups.remove(at: 0);
                self.delegate?.itemsRemoved(at: IndexSet(integer: 0), inParent: nil);
            }
            
            for i in (0..<oldItems.count).reversed() {
                if !items.contains(oldItems[i]) {
                    self.items.remove(at: i);
                    self.delegate?.itemsRemoved(at: IndexSet(integer: i), inParent: self);
                }
            }
            for i in 0..<items.count {
                if self.items.count <= i {
                    self.items.append(items[i]);
                    self.delegate?.itemsInserted(at: IndexSet(integer: i), inParent: self);
                } else if !self.items.contains(items[i]) {
                    self.items.insert(items[i], at: i);
                    self.delegate?.itemsInserted(at: IndexSet(integer: i), inParent: self);
                }
            }
            if added {
                self.delegate?.outlineView.expandItem(self);
            }
        }
    }
    
    
}
