//
// ConversationEntryState.swift
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

public enum ConversationEntryIncomingState: Equatable {
    case received
    case displayed
    
    var isUnread: Bool {
        return self == .received;
    }
}

public enum ConversationEntryOutogingState: Equatable {
    case unsent
    case sent
    case delivered
    case displayed
}

public enum ConversationEntryState: Equatable {

    case incoming(ConversationEntryIncomingState)
    case outgoing(ConversationEntryOutogingState)

    case incoming_error(ConversationEntryIncomingState, errorMessage: String? = nil)
    case outgoing_error(ConversationEntryIncomingState, errorMessage: String? = nil)
    
    public static func ==(lhs: ConversationEntryState, rhs: ConversationEntryState) -> Bool {
        return lhs.code == rhs.code;
    }
    
    static func from(code: Int, errorMessage: String?) -> ConversationEntryState {
        switch code {
        case 0:
            return .incoming(.displayed);
        case 1:
            return .outgoing(.sent);
        case 2:
            return .incoming(.received);
        case 3:
            return .outgoing(.unsent)
        case 4:
            return .incoming_error(.displayed, errorMessage: errorMessage);
        case 5:
            return .outgoing_error(.displayed, errorMessage: errorMessage);
        case 6:
            return .incoming_error(.received, errorMessage: errorMessage);
        case 7:
            return .outgoing_error(.received, errorMessage: errorMessage);
        case 9:
            return .outgoing(.delivered);
        case 11:
            return .outgoing(.displayed);
        default:
            assert(false, "Invalid conversation entry state code")
        }
    }
    
    // x % 2 == 0 - incoming
    // x % 2 == 1 - outgoing
    var code: Int {
        switch self {
        case .incoming(let state):
            switch state {
            case .received:
                return 2;
            case .displayed:
                return 0;
            }
        case .outgoing(let state):
            switch state {
            case .unsent:
                return 3;
            case .sent:
                return 1;
            case .delivered:
                return 9;
            case .displayed:
                return 11;
            }
        case .incoming_error(let state, _):
            switch state {
            case .received:
                return 6;
            case .displayed:
                return 4;
            }
        case .outgoing_error(let state, _):
            switch state {
            case .received:
                return 7;
            case .displayed:
                return 5;
            }
        }
    }
    
    var rawValue: Int {
        return code;
    }
    
    var direction: MessageDirection {
        switch self {
        case .incoming(_), .incoming_error(_, _):
            return .incoming;
        case .outgoing(_), .outgoing_error(_, _):
            return .outgoing;
        }
    }

    var isError: Bool {
        switch self {
        case .incoming_error(_, _), .outgoing_error(_, _):
            return true;
        default:
            return false;
        }
    }

    var isUnread: Bool {
        switch self {
        case .incoming(let state):
            return state.isUnread;
        default:
            return false;
        }
    }
    
    var isUnsent: Bool {
        switch self {
        case .outgoing(let state):
            return state == .unsent;
        default:
            return false;
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .incoming_error(_, let msg), .outgoing_error(_, let msg):
            return msg;
        default:
            return nil;
        }
    }

}
