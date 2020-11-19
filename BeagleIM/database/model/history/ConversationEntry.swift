//
// ConversationEntry.swift
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

import AppKit
import TigaseSwift

public class ConversationEntry {
    
    let id: Int;
    let conversation: ConversationKey;
    let timestamp: Date;
    
    init(id: Int, conversation: ConversationKey, timestamp: Date) {
        self.id = id;
        self.conversation = conversation;
        self.timestamp = timestamp;
    }
    
    func isMergeable() -> Bool {
        return false;
    }

    func isMergeable(with item: ConversationEntry) -> Bool {
        // check if entries can be mergable (some are not mergable)
        guard isMergeable() && item.isMergeable() else {
            return false;
        }
        return true;
    }
    
}


