//
// AcceptableServerCertificate.swift
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

public struct AcceptableServerCertificate: Codable, Equatable {
    
    enum CodingKeys: CodingKey {
        case certificate
        case accepted
    }
    
    public let certificate: SSLCertificateInfo;
    public var accepted: Bool;
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        certificate = try container.decode(SSLCertificateInfo.self, forKey: .certificate)
        accepted = try container.decode(Bool.self, forKey: .accepted);
    }
    
    public init(certificate: SSLCertificateInfo, accepted: Bool) {
        self.certificate = certificate;
        self.accepted = accepted;
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(certificate, forKey: .certificate)
        try container.encode(accepted, forKey: .accepted);
    }
}

open class ServerCertificateInfoOld: SslCertificateInfoOld {

    public var accepted: Bool;
        
    public override init(trust: SecTrust) {
        self.accepted = false;
        super.init(trust: trust);
    }
    
    public init(sslCertificateInfo: SslCertificateInfoOld, accepted: Bool) {
        self.accepted = accepted;
        super.init(sslCertificateInfo: sslCertificateInfo);
    }
    
    public required init?(coder aDecoder: NSCoder) {
        accepted = aDecoder.decodeBool(forKey: "accepted");
        super.init(coder: aDecoder);
    }
    
    public override func encode(with aCoder: NSCoder) {
        aCoder.encode(accepted, forKey: "accepted");
        super.encode(with: aCoder);
    }
    
    public func acceptableServerCertificate() -> AcceptableServerCertificate {
        return AcceptableServerCertificate(certificate: self.sslCertificateInfo(), accepted: accepted);
    }
}

