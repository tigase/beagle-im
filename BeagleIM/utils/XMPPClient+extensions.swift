//
// XMPPClient+extensions.swift
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

extension XMPPClient {
    
    public func configure(for account: Account) {
        connectionConfiguration.credentials = account.credentials //.password(password: account.password, authenticationName: nil, cache: nil);
        connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            if let acceptableCertificate = account.acceptedCertificate, acceptableCertificate.accepted, let fingerprint = acceptableCertificate.certificate.subject.fingerprints.first {
                options.sslCertificateValidation = .fingerprint(fingerprint);
            } else {
                options.sslCertificateValidation = .default;
            }
            options.connectionDetails = account.serverEndpoint;
            if let idx = options.networkProcessorProviders.firstIndex(where: { $0 is SSLProcessorProvider }) {
                options.networkProcessorProviders.remove(at: idx);
            }
            options.networkProcessorProviders.append(account.disableTLS13 ? SSLProcessorProvider(supportedTlsVersions: TLSVersion.TLSv1_2...TLSVersion.TLSv1_2) : SSLProcessorProvider());
        });
    }
    
}
