//
// ItemType.swift
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

public enum ItemType: Int, Sendable {
    case message = 0
    case attachment = 1
    // how about new type called link preview? this way we would have a far less data kept in a single item..
    // we could even have them separated to the new item/entry during adding message to the store..
    case linkPreview = 2
    // with that in place we can have separate metadata kept "per" message as it is only one, so message id can be id of associated metadata..
    case invitation = 3
    case retraction = 4
    case location = 6;
}

