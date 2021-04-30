//
// ShowMainWindowSegue.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class ShowMainWindowSegue: NSStoryboardSegue {
    
    override func perform() {
        (NSApplication.shared.delegate as? AppDelegate)?.mainWindowController?.showWindow(self);
    }
    
}

class ChatWithWindowSegue: NSStoryboardSegue {
    
    override func perform() {
        if let mainWindow = (NSApplication.shared.delegate as? AppDelegate)?.mainWindowController {
            mainWindow.showWindow(self);
            ((mainWindow.contentViewController as? NSSplitViewController)?.splitViewItems.first?.viewController as? ChatsListViewController)?.searchField.becomeFirstResponder();
        }
    }
    
}

class JoinChannelWindowSegue: NSStoryboardSegue {

    override func perform() {
        if let mainWindow = (NSApplication.shared.delegate as? AppDelegate)?.mainWindowController {
            mainWindow.showWindow(self);
            ((mainWindow.contentViewController as? NSSplitViewController)?.splitViewItems.first?.viewController as? ChatsListViewController)?.openChannel(self);
        }
    }

}
