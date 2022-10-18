//
// Account.swift
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
import Combine
import Martin
import TigaseSQLite3

public struct Account {

    public var state = CurrentValueSubject<XMPPClient.State,Never>(.disconnected());

    public let name: BareJID;
    public var password: String;
    public var enabled: Bool;
    public var serverEndpoint: SocketConnectorNetwork.Endpoint?; // replaces server and endpoint..
    public var lastEndpoint: SocketConnectorNetwork.Endpoint?;
    public var rosterVersion: String?;
    public var statusMessage: String?;

    public var additional: Additional;

    public var omemoDeviceId: UInt32? {
        get {
            return additional.omemoDeviceId;
        }
        set {
            additional.omemoDeviceId = newValue;
        }
    }

    public var acceptedCertificate: AcceptableServerCertificate? {
        get {
            return additional.acceptedCertificate;
        }
        set {
            additional.acceptedCertificate = newValue;
        }
    }

    public var nickname: String? {
        get {
            return additional.nick;
        }
        set {
            additional.nick = newValue;
        }
    }

    public var disableTLS13: Bool {
        get {
            return additional.disableTLS13;
        }
        set {
            additional.disableTLS13 = newValue;
        }
    }
    
    public enum ResourceType: Codable, Equatable {
        case automatic
        case hostname
        case manual(String)
    }

    public struct Additional: Codable, DatabaseConvertibleStringValue, Equatable {
        public var omemoDeviceId: UInt32?;
        public var acceptedCertificate: AcceptableServerCertificate?;
        public var nick: String?;
        public var disableTLS13: Bool;
        public var knownServerFeatures: [ServerFeature];
        public var resourceType: ResourceType;

        public init() {
            self.omemoDeviceId = nil
            self.acceptedCertificate = nil;
            self.nick = nil;
            self.disableTLS13 = false;
            self.knownServerFeatures = [];
            self.resourceType = .automatic;
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self);
            omemoDeviceId = try container.decodeIfPresent(UInt32.self, forKey: .omemoId);
            acceptedCertificate = try container.decodeIfPresent(AcceptableServerCertificate.self, forKey: .acceptedCertificate)
            nick = try container.decodeIfPresent(String.self, forKey: .nick)
            disableTLS13 = try container.decode(Bool.self, forKey: .disableTLS13);
            knownServerFeatures = try container.decodeIfPresent([ServerFeature].self, forKey: .knownServerFeatures) ?? [];
            resourceType = try container.decodeIfPresent(ResourceType.self, forKey: .resourceType) ?? .automatic;
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self);
            try container.encodeIfPresent(omemoDeviceId, forKey: .omemoId);
            try container.encodeIfPresent(acceptedCertificate, forKey: .acceptedCertificate);
            try container.encodeIfPresent(nick, forKey: .nick)
            try container.encodeIfPresent(disableTLS13, forKey: .disableTLS13);
            if !knownServerFeatures.isEmpty {
                try container.encode(knownServerFeatures, forKey: .knownServerFeatures);
            }
        }

        enum CodingKeys: CodingKey {
            case omemoId
            case acceptedCertificate
            case nick
            case disableTLS13
            case knownServerFeatures
            case resourceType
        }
    }

    public init(name: BareJID, enabled: Bool, password: String = "", serverEndpoint: SocketConnectorNetwork.Endpoint? = nil, lastEndpoint: SocketConnectorNetwork.Endpoint? = nil, rosterVersion: String? = nil, statusMessage: String? = nil, additional: Additional = Additional())  {
        self.name = name;
        self.password = password;
        self.enabled = enabled;
        self.serverEndpoint = serverEndpoint;
        self.lastEndpoint = lastEndpoint;
        self.rosterVersion = rosterVersion;
        self.additional = additional;
    }
            
}
