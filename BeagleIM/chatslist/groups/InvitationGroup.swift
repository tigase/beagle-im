//
//  InvitationGroup.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 17/02/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
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
