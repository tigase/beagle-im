//
// Collection+calculateChanges.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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

extension BidirectionalCollection where Element: Hashable {
    
    func calculateChanges<C>(from other: C) -> [CollectionChange] where C: BidirectionalCollection, Element == C.Element {
        let diffs = self.difference(from: other).inferringMoves();
        
        var changes: [CollectionChange] = []
        var movedOffsets: [Element:Int] = [:];

        for action in diffs {
            print("action:", action)
            switch action {
            case .remove(let offset, let el, let to):
                if to != nil {
                    movedOffsets[el] = offset;
                } else {
                    changes.append(.remove(offset + movedOffsets.values.filter({ $0 < offset}).count))
                }
            case .insert(let offset, let el, let from):
                if let idx = from {
                    movedOffsets.removeValue(forKey: el);
                    changes.append(.move(idx + movedOffsets.values.filter({ $0 < idx}).count, offset + movedOffsets.values.filter({ $0 < offset}).count));
                } else {
                    changes.append(.insert(offset + movedOffsets.values.filter({ $0 < offset}).count));
                }
            }
        }
        return changes;
    }
    
}

enum CollectionChange {
    case remove(Int)
    case insert(Int)
    case move(Int,Int)
}
