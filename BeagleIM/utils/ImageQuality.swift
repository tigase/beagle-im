//
// ImageQuality.swift
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

enum ImageQuality: String {
    case original
    case highest
    case high
    case medium
    case low
    
    static var current: ImageQuality {
        return Settings.imageQuality;
    }
    
    var label: String {
        switch self {
        case .original:
            return NSLocalizedString("Original", comment: "image quality")
        case .highest:
            return NSLocalizedString("Highest", comment: "image quality")
        case .high:
            return NSLocalizedString("High", comment: "image quality")
        case .medium:
            return NSLocalizedString("Medium", comment: "image quality")
        case .low:
            return NSLocalizedString("Low", comment: "image quality")
        }
    }
    
    var size: CGFloat {
        switch self {
        case .original:
            return CGFloat.greatestFiniteMagnitude;
        case .highest:
            return CGFloat.greatestFiniteMagnitude;
        case .high:
            return 2048;
        case .medium:
            return 1536;
        case .low:
            return 1024;
        }
    }
    
    var quality: CGFloat {
        switch self {
        case .original:
            return 1;
        case .highest:
            return 1;
        case .high:
            return 0.85;
        case .medium:
            return 0.7;
        case .low:
            return 0.6;
        }
    }
}
