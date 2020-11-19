//
// ConversationEntryEncryption.swift
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

public enum ConversationEntryEncryption: Equatable {
    case none
    case decrypted(fingerprint: String?)
    case decryptionFailed
    case notForThisDevice
    
    static func from(messageEncryption: MessageEncryption, fingerprint: String?) -> ConversationEntryEncryption {
        switch messageEncryption {
        case .decrypted:
            return .decrypted(fingerprint: fingerprint);
        case .none:
            return .none;
        case .decryptionFailed:
            return .decryptionFailed;
        case .notForThisDevice:
            return .notForThisDevice;
        }
    }
    
    func message() -> String? {
        switch self {
        case .none, .decrypted(_):
            return nil;
        case .decryptionFailed:
            return "Message decryption failed!";
        case .notForThisDevice:
            return "Message was not encrypted for this devices";
        }
    }
    
    var fingerprint: String? {
        switch self {
        case .decrypted(let fingerprint):
            return fingerprint;
        default:
            return nil;
        }
    }
    
    var value: MessageEncryption {
        switch self {
        case .none:
            return .none;
        case .decrypted(_):
            return .decrypted;
        case .decryptionFailed:
            return .decryptionFailed;
        case .notForThisDevice:
            return .notForThisDevice;
        }
    }
    
    public static func == (lhs: ConversationEntryEncryption, rhs: ConversationEntryEncryption) -> Bool {
        return lhs.value == rhs.value;
    }
}
