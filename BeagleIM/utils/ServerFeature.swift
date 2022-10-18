//
// ServerFeature.swift
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
import Martin

public enum ServerFeature: String, Codable {
    case mam
    case push
    
    public static func from(info: DiscoveryModule.DiscoveryInfoResult) -> [ServerFeature] {
        return from(features: info.features);
    }
    
    public static func from(features: [String]) -> [ServerFeature] {
        var serverFeatures: [ServerFeature] = [];
        if features.contains(MessageArchiveManagementModule.MAM_XMLNS) || features.contains(MessageArchiveManagementModule.MAM2_XMLNS) {
            serverFeatures.append(.mam);
        }
        if features.contains(PushNotificationsModule.PUSH_NOTIFICATIONS_XMLNS) {
            serverFeatures.append(.push);
        }
        return serverFeatures;
    }
}
