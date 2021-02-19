//
// PEPBookmarksModule_extension.swift
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

import Foundation
import TigaseSwift

extension PEPBookmarksModule {
    
    static func updateOrAdd(for account: BareJID, bookmark item: Bookmarks.Item) {
        guard Settings.enableBookmarksSync, let pepBookmarksModule = XmppService.instance.getClient(for: account)?.module(.pepBookmarks) else {
            return;
        }
        
        if let updated = pepBookmarksModule.currentBookmarks.updateOrAdd(bookmark: item) {
            pepBookmarksModule.publish(bookmarks: updated);
        }
    }
    
    static func remove(from account: BareJID, bookmark item: Bookmarks.Item) {
        guard Settings.enableBookmarksSync, let pepBookmarksModule = XmppService.instance.getClient(for: account)?.module(.pepBookmarks) else {
            return;
        }
        
        if let updated = pepBookmarksModule.currentBookmarks.remove(bookmark: item) {
            pepBookmarksModule.publish(bookmarks: updated);
        }
    }
}
