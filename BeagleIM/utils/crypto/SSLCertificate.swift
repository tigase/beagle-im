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
import Martin

open class SSLCertificate: Martin.SSLCertificate {
    
    private let ref: OpaquePointer;
    
    init(withOwnedReference ref: OpaquePointer) {
        self.ref = ref;
    }
    
    deinit {
        X509_free(ref);
    }
    
    open var algorithmName: String {
        let algPtr = X509_get0_tbs_sigalg(ref).pointee.algorithm;
        var tmp = [CChar](repeating: 0, count: 100);
        let read = i2t_ASN1_OBJECT(&tmp, 100, algPtr);
        return String(cString: tmp);
    }
    
    open func derCertificateData() -> Data? {
        var buf: UnsafeMutablePointer<UInt8>? = nil;
        
        let len = i2d_X509(self.ref, &buf);
        guard len >= 0 else {
            return nil;
        }
        
        defer {
            free(buf);
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
