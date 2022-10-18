//
// ChatEncryption.swift
//
// BeagleIM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

public enum ChatEncryption: String, Codable, CustomStringConvertible, Sendable {
    case none = "none";
    case omemo = "omemo";
    
    public var description: String {
        switch self {
        case .none:
            return NSLocalizedString("None", comment: "encyption option");
        case .omemo:
            return NSLocalizedString("OMEMO", comment: "encryption option");
        }
    }
}
