//
// ExternalServiceDiscoveryModule_Service_extension.swift
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
import Network
import WebRTC
import Martin

extension ExternalServiceDiscoveryModule.Service {
    
    static let VALID_SERVICE_TYPES = ["stun", "stuns", "turn", "turns"];
    
    func rtcIceServer() -> RTCIceServer? {
        guard ExternalServiceDiscoveryModule.Service.VALID_SERVICE_TYPES.contains(type) else {
            return nil;
        }
        guard !type.hasSuffix("s") || transport == .tcp else {
            return nil;
        }
        guard !type.hasPrefix("turn") || username != nil else {
            return nil;
        }
        
        let url = urlString();
        return RTCIceServer(urlStrings: [url], username: username, credential: password, tlsCertPolicy: .insecureNoCheck);
    }
    
    private func urlString() -> String {
        let host = IPv6Address(self.host) != nil ? "[\(self.host)]" : self.host;
        
        if let port = self.port {
            if let transport = self.transport {
                return "\(type):\(host):\(port)?transport=\(transport.rawValue)"
            } else {
                return "\(type):\(host):\(port)"
            }
        } else {
            if let transport = self.transport {
                return "\(type):\(host)?transport=\(transport.rawValue)"
            } else {
                return "\(type):\(host)"
            }
        }
    }
}
