//
// MucModule_RoomError_extension.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
import Martin

extension MucModule.RoomError {
    
    var reason: String {
        switch self {
        case .banned:
            return NSLocalizedString("User is banned", comment: "muc module - room error");
        case .invalidPassword:
            return NSLocalizedString("Invalid password", comment: "muc module - room error");
        case .maxUsersExceeded:
            return NSLocalizedString("Maximum number of users exceeded", comment: "muc module - room error");
        case .nicknameConflict:
            return NSLocalizedString("Nickname already in use", comment: "muc module - room error");
        case .nicknameLockedDown:
            return NSLocalizedString("Nickname is locked down", comment: "muc module - room error");
        case .registrationRequired:
            return NSLocalizedString("Membership is required to access the room", comment: "muc module - room error");
        case .roomLocked:
            return NSLocalizedString("Room is locked", comment: "muc module - room error");
        }
    }
    
}
