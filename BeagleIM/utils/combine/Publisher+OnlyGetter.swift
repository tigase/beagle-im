//
// Publisher+OnlyGetter.swift
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
import Combine

extension Publisher where Self.Output : Comparable {
    
    func onlyGreater(than initialValue: Output? = nil) -> Publishers.Filter<Self> {
        var value: Output? = initialValue;
        return self.filter({ nextValue in
            if value == nil || (value! < nextValue) {
                value = nextValue;
                return true;
            }
            return false;
        });
    }
    
}
