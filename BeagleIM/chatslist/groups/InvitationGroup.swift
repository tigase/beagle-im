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
import Combine

class InvitationGroup: ChatsListGroupProtocol {
    
    var items: [InvitationItem] = [];
    
    let name: String = "Invitations";
    
    var count: Int {
        return items.count;
    }
    
    let canOpenChat: Bool = false;
    
    weak var delegate: ChatsListViewController?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    init(delegate: ChatsListViewController) {
        self.delegate = delegate;
        
        InvitationManager.instance.itemsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] items in
            self?.update(items: items);
        }).store(in: &cancellables);
    }
    
    func getItem(at: Int) -> ChatsListItemProtocol? {
        return items[at];
    }
    
    func forChat(_ chat: Conversation, execute: @escaping (ConversationItem) -> Void) {
        // nothing to do...
    }
    
    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ConversationItem) -> Void) {
        // nothing to do..
    }
    
    private func update(items: Set<InvitationItem>) {
        let newItems = items.sorted(by: { (i1, i2) -> Bool in i1.order > i2.order });
        let oldItems = self.items;
        
        let diffs = newItems.difference(from: oldItems).inferringMoves();
        var removed: [Int] = [];
        var inserted: [Int] = [];
        var moved: [(Int,Int)] = [];
        for action in diffs {
            switch action {
            case .remove(let offset, _, let to):
                if let idx = to {
                    moved.append((offset, idx));
                } else {
                    removed.append(offset);
                }
            case .insert(let offset, _, let from):
                if from == nil {
                    inserted.append(offset);
                }
            }
        }
        
        self.items = newItems;
        self.delegate?.beginUpdates();
        if !removed.isEmpty {
            self.delegate?.itemsRemoved(at: IndexSet(removed), inParent: self);
            if newItems.isEmpty && !oldItems.isEmpty {
                self.delegate?.invitationGroup(show: false);
            }
        }
        for (from,to) in moved {
            self.delegate?.itemMoved(from: from, fromParent: self, to: to, toParent: self);
        }
        if !inserted.isEmpty {
            if oldItems.isEmpty && !newItems.isEmpty {
                self.delegate?.invitationGroup(show: true);
            } else {
                self.delegate?.itemsInserted(at: IndexSet(inserted), inParent: self);
            }
        }
        self.delegate?.endUpdates();
    }
    
//    @objc func invitationsAdded(_ notification: Notification) {
//        DispatchQueue.main.async {
//            guard let toAdd = notification.object as? [InvitationItem], !toAdd.isEmpty else {
//                return;
//            }
//
//            let added = self.items.isEmpty && !toAdd.isEmpty;
//            if added {
//                self.delegate?.groups.insert(self, at: 0);
//                self.delegate?.itemsInserted(at: IndexSet(integer: 0), inParent: nil);
//            }
//
//            self.items = toAdd + self.items;
//            self.delegate?.itemsInserted(at: IndexSet(integersIn: 0..<toAdd.count), inParent: self);
//            if added {
//                self.delegate?.outlineView.expandItem(self);
//            }
//        }
//    }
//
//    @objc func invitationsRemoved(_ notification: Notification) {
//        DispatchQueue.main.async {
//            guard let toRemove = notification.object as? [InvitationItem], !toRemove.isEmpty else {
//                return;
//            }
//
//            let dict = Dictionary(uniqueKeysWithValues: self.items.enumerated().map({ ($0.1, $0.0 )}));
//
//            let removeSet = Set(toRemove);
//            self.items = self.items.filter({ !removeSet.contains($0) });
//            let removedIdx = toRemove.map({ dict[$0]! });
//            self.delegate?.itemsRemoved(at: IndexSet(removedIdx), inParent: self)
//
//            if self.items.isEmpty {
//                self.delegate?.groups.remove(at: 0);
//                self.delegate?.itemsRemoved(at: IndexSet(integer: 0), inParent: nil);
//            }
//        }
//    }
    
}
