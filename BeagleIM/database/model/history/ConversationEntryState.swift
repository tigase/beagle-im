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

public enum ConversationEntryState: Equatable {

    case incoming
    case outgoing

    case incoming_unread
    case outgoing_unsent

    case incoming_error(errorMessage: String?)
    case outgoing_error(errorMessage: String?)

    case incoming_error_unread(errorMessage: String?)
    case outgoing_error_unread(errorMessage: String?)

    case outgoing_delivered
    case outgoing_read
    
    static func from(code: Int, errorMessage: String?) -> ConversationEntryState {
        switch code {
        case 0:
            return .incoming;
        case 1:
            return .outgoing;
        case 2:
            return .incoming_unread;
        case 3:
            return .outgoing_unsent;
        case 4:
            return .incoming_error(errorMessage: errorMessage);
        case 5:
            return .outgoing_error(errorMessage: errorMessage);
        case 6:
            return .incoming_error_unread(errorMessage: errorMessage);
        case 7:
            return .outgoing_error_unread(errorMessage: errorMessage);
        case 9:
            return .outgoing_delivered;
        case 11:
            return .outgoing_read;
        default:
            assert(false, "Invalid conversation entry state code")
            return .incoming;
        }
    }
    
    // x % 2 == 0 - incoming
    // x % 2 == 1 - outgoing
    var code: Int {
        switch self {
        case .incoming:
            return 0;
        case .outgoing:
            return 1;
        case .incoming_unread:
            return 2;
        case .outgoing_unsent:
            return 3;
        case .incoming_error(_):
            return 4;
        case .outgoing_error(_):
            return 5;
        case .incoming_error_unread(_):
            return 6;
        case .outgoing_error_unread(_):
            return 7;
        case .outgoing_delivered:
            return 9;
        case .outgoing_read:
            return 11;
        }
    }
    
    var direction: MessageDirection {
        switch self {
        case .incoming, .incoming_unread, .incoming_error, .incoming_error_unread:
            return .incoming;
        case .outgoing, .outgoing_unsent, .outgoing_delivered, .outgoing_read, .outgoing_error_unread, .outgoing_error:
            return .outgoing;
        }
    }

    var isError: Bool {
        switch self {
        case .incoming_error, .incoming_error_unread, .outgoing_error, .outgoing_error_unread:
            return true;
        default:
            return false;
        }
    }

    var isUnread: Bool {
        switch self {
        case .incoming_unread, .incoming_error_unread, .outgoing_error_unread:
            return true;
        default:
            return false;
        }
    }
    
    var isUnsent: Bool {
        switch self {
        case .outgoing_unsent:
            return true;
        default:
            return false;
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .incoming_error(let msg), .incoming_error_unread(let msg), .outgoing_error(let msg), .outgoing_error_unread(let msg):
            return msg;
        default:
            return nil;
        }
    }

}
