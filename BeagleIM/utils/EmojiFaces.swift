//
// EmojiFaces.swift
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

class EmojiFaces {
    
    static func search(contains query: String) -> EmojiFace? {
        guard let value = String.emojis[query] else {
            return nil;
        }
        
        return EmojiFace(key: query, value: value);
    }
    
}

struct EmojiFace {
    
    let key: String;
    let value: String;
    
}
