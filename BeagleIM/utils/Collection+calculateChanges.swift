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

private class QueuedForRemoval {
    var idx: Int;
    var removed: Bool = false;
    init(idx: Int) {
        self.idx = idx;
    }
}

extension BidirectionalCollection where Element: Hashable {
    
    func calculateChanges<C>(from other: C) -> [CollectionChange] where C: BidirectionalCollection, Element == C.Element {

        let diffs = self.difference(from: other).inferringMoves();
        
        var changes: [CollectionChange] = []

        var queuedForRemoval: [QueuedForRemoval] = [];
        var mappedForRemoval: [Element: QueuedForRemoval] = [:];
        
        let recalculateTarget = { (offset: Int) -> Int in
            var newTarget = offset;
            // we check all not removed before insertion place and bump insertion place index
            for item in queuedForRemoval.reversed() {
                if (!item.removed) && item.idx <= newTarget {
                    newTarget = newTarget + 1;
                }
            }
            return newTarget;
        }
        
        for action in diffs {
            switch action {
            case .remove(let offset, let element, let associatedWith):
                if associatedWith != nil {
                    let item = QueuedForRemoval(idx: offset);
                    queuedForRemoval.append(item);
                    mappedForRemoval[element] = item;
                } else {
                    queuedForRemoval.forEach({ $0.idx = $0.idx - 1 });
                    // we are not updating offset as they are descending (no impact on removal)
                    changes.append(.remove(offset));
                }
            case .insert(let offset, let element, let associatedWith):
                // we need to update offsets as those are ascending
                if associatedWith != nil {
                    let removedItem = mappedForRemoval[element]!;
                    removedItem.removed = true;
                    
                    let newSource = removedItem.idx;
                    let newTarget = recalculateTarget(offset);
                    
                    
                    for item in queuedForRemoval {
                        if !item.removed {
                            if item.idx > newSource {
                                item.idx = item.idx - 1;
                            }
                            if item.idx >= newTarget {
                                item.idx = item.idx + 1;
                            }
                        }
                    }
                    
                    changes.append(.move(newSource, newTarget))
                } else {
                    let newTarget = recalculateTarget(offset);
                    changes.append(.insert(newTarget));
                    for item in queuedForRemoval {
                        if (!item.removed) {
                            if item.idx < offset {
                                break;
                            }
                            item.idx = item.idx + 1;
                        }
                    }
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
