//
//  MucModule_RoomError_extension.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 23.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import TigaseSwift

extension MucModule.RoomError {
    
    var reason: String {
        switch self {
        case .banned:
            return "User is banned";
        case .invalidPassword:
            return "Invalid password";
        case .maxUsersExceeded:
            return "Maximum number of users exceeded";
        case .nicknameConflict:
            return "Nickname already in use";
        case .nicknameLockedDown:
            return "Nickname is locked down";
        case .registrationRequired:
            return "Membership is required to access the room";
        case .roomLocked:
            return "Room is locked";
        }
    }
    
}
