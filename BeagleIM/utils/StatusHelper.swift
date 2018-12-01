//
// StatusHelper.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift

class StatusHelper {
    
    public static func imageFor(status: Presence.Show?) -> NSImage {
        return NSImage(named: StatusHelper.imageNameFor(status: status))!;
    }
    
    fileprivate static func imageNameFor(status: Presence.Show?) -> NSImage.Name {
        if status == nil {
            return NSImage.statusNoneName;
        } else {
            switch status! {
            case .online, .chat:
                return NSImage.statusAvailableName;
            case .away, .xa:
                return NSImage.statusPartiallyAvailableName;
            case .dnd:
                return NSImage.statusUnavailableName;
            }
        }
    }
    
}
