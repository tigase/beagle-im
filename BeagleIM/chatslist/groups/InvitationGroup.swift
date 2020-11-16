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
    
    init(delegate: ChatsListViewController) {
        self.delegate = delegate;
        InvitationManager.instance.dispatcher.sync {
            NotificationCenter.default.addObserver(self, selector: #selector(invitationsAdded(_:)), name: InvitationManager.INVITATIONS_ADDED, object: nil);
            NotificationCenter.default.addObserver(self, selector: #selector(invitationsRemoved(_:)), name: InvitationManager.INVITATIONS_REMOVED, object: nil);
            self.items = Array(InvitationManager.instance.items);
        }
    }
    
    func getItem(at: Int) -> ChatsListItemProtocol? {
        return items[at];
    }
    
    func forChat(_ chat: Conversation, execute: @escaping (ChatItemProtocol) -> Void) {
        // nothing to do...
    }
    
    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ChatItemProtocol) -> Void) {
        // nothing to do..
    }
    
    @objc func invitationsAdded(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let toAdd = notification.object as? [InvitationItem], !toAdd.isEmpty else {
                return;
            }
        
            let added = self.items.isEmpty && !toAdd.isEmpty;
            if added {
                self.delegate?.groups.insert(self, at: 0);
                self.delegate?.itemsInserted(at: IndexSet(integer: 0), inParent: nil);
            }
            
            self.items = toAdd + self.items;
            self.delegate?.itemsInserted(at: IndexSet(integersIn: 0..<toAdd.count), inParent: self);
            if added {
                self.delegate?.outlineView.expandItem(self);
            }
        }
    }

    @objc func invitationsRemoved(_ notification: Notification) {
        DispatchQueue.main.async {
            guard let toRemove = notification.object as? [InvitationItem], !toRemove.isEmpty else {
                return;
            }
            
            let dict = Dictionary(uniqueKeysWithValues: self.items.enumerated().map({ ($0.1, $0.0 )}));
            
            let removeSet = Set(toRemove);
            self.items = self.items.filter({ !removeSet.contains($0) });
            let removedIdx = toRemove.map({ dict[$0]! });
            self.delegate?.itemsRemoved(at: IndexSet(removedIdx), inParent: self)
            
            if self.items.isEmpty {
                self.delegate?.groups.remove(at: 0);
                self.delegate?.itemsRemoved(at: IndexSet(integer: 0), inParent: nil);
            }
        }
    }
    
}
