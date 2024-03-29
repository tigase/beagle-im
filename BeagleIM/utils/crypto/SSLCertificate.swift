//
// SSLCertificate.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import OpenSSL

open class SSLCertificate {
    
    private let ref: OpaquePointer;
    
    init(withOwnedReference ref: OpaquePointer) {
        self.ref = ref;
    }
    
    deinit {
        X509_free(ref);
    }
    
    open func derCertificateData() -> Data? {
        var buf: UnsafeMutablePointer<UInt8>? = nil;
        
        let len = i2d_X509(self.ref, &buf);
        guard len >= 0 else {
            return nil;
        }
        
        defer {
            X509_free(OpaquePointer.init(buf));
        }
        
        return Data(bytes: UnsafeRawPointer(buf!), count: Int(len));
    }
    
    open func secCertificate() -> SecCertificate? {
        guard let data = derCertificateData() else {
            return nil;
        }
        return SecCertificateCreateWithData(nil, data as CFData);
    }
    
    open func secTrust() -> SecTrust? {
        guard let cert = secCertificate() else {
            return nil;
        }
        var commonName: CFString?;
        SecCertificateCopyCommonName(cert, &commonName);
        var trust: SecTrust?;
        guard SecTrustCreateWithCertificates([cert] as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess else {
            return nil;
        }
        return trust;
    }
}
