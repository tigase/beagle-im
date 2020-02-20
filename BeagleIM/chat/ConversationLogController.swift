//
// ConversationLogController.swift
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

class ConversationLogController: AbstractConversationLogController {
    
    override func prepareContextMenu(_ menu: NSMenu, forRow row: Int) {
        super.prepareContextMenu(menu, forRow: row);
        (self.logTableViewDelegate as? ConversationLogContextMenuDelegate)?.prepareConversationLogContextMenu(dataSource: self.dataSource, menu: menu, forRow: row);
    }
    
}

protocol ConversationLogContextMenuDelegate {
    
    func prepareConversationLogContextMenu(dataSource: ChatViewDataSource, menu: NSMenu, forRow row: Int);
    
}
