//
// Array+IndexChanges.swift
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

extension Array {

    public struct IndexSetChanges {
        let removed: IndexSet;
        let inserted: IndexSet;
    }

}

extension Array where Element: Hashable {
    
    func calculateChanges(from source: Array<Element>) -> IndexSetChanges {
        if #available(macOS 10.15, *) {
            let diff = self.difference(from: source);
            
            let removed = diff.removals.map({ change -> Int in
                switch change {
                case .insert(let offset, _, _):
                    return offset;
                case .remove(let offset, _, _):
                    return offset;
                }
            })
            
            let inserted = diff.insertions.map({ change -> Int in
                switch change {
                case .insert(let offset, _, _):
                    return offset;
                case .remove(let offset, _, _):
                    return offset;
                }
            })
            
            return .init(removed: IndexSet(removed), inserted: IndexSet(inserted));
        } else {
            let thisSet = Set(self);
            let removed = source.filter({ !thisSet.contains($0) }).map({ source.firstIndex(of: $0 )! });
            
            let originSet = Set(source);
            let inserted = self.filter({ !originSet.contains($0) }).map({ self.firstIndex(of: $0 )! });
            
            return .init(removed: IndexSet(removed), inserted: IndexSet(inserted));
        }
    }
    
}
