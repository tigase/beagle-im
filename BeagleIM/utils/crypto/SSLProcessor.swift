//
// SSLProcessor.swift
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
import Martin
import OpenSSL
import TigaseLogging

public enum TLSVersion: Comparable, CaseIterable {
    case TLSv1
    case TLSv1_1
    case TLSv1_2
    case TLSv1_3
    case unknown
}

extension TLSVersion {
    
    var ssl_op_no: UInt32 {
        switch self {
        case .TLSv1:
            return SSL_OP_NO_TLSv1;
        case .TLSv1_1:
            return SSL_OP_NO_TLSv1_1;
        case .TLSv1_2:
            return SSL_OP_NO_TLSv1_2;
        case .TLSv1_3:
            return SSL_OP_NO_TLSv1_3;
        case .unknown:
            return 0;
        }
    }
    
}

public typealias SSLProtocol = TLSVersion;

extension SSLProtocol {
    static func from(protocolId: Int32) -> SSLProtocol {
        switch protocolId {
        case TLS1_VERSION:
            return .TLSv1;
        case TLS1_1_VERSION:
            return .TLSv1_1;
        case TLS1_2_VERSION:
            return .TLSv1_2;
        case TLS1_3_VERSION:
            return .TLSv1_3;
        default:
            return .unknown;
        }
    }
    
    var name: String {
        switch self {
        case .TLSv1:
            return "TLSv1"
        case .TLSv1_1:
            return "TLSv1.1"
        case .TLSv1_2:
            return "TLSv1.2"
        case .TLSv1_3:
            return "TLSv1.3"
        case .unknown:
            return "Unknown";
        }
    }
}

extension SecTrustResultType {
    var name: String {
        switch self {
        case .deny:
            return "deny";
        case .fatalTrustFailure:
            return "fatal trust failure";
        case .invalid:
            return "invalid";
        case .otherError:
            return "other error";
        case .proceed:
            return "proceed";
        case .recoverableTrustFailure:
            return "recoverable trust failure";
        case .unspecified:
            return "unspecified";
        default:
            return "unknown"
        }
    }
}

open class SSLProcessor: ConnectorBase.NetworkProcessor, SSLNetworkProcessor {

    enum HandshakeResult {
        case complete
        case incomplete
        case failed
        
        static func from(code: Int32, connection: SSLProcessor) -> HandshakeResult {
            guard code != 1 else {
                return .complete;
            }
            
            let status = SSLStatus.from(code: code, connection: connection);
            switch status {
            case .want_read, .want_write:
                return .incomplete;
            default:
                return .failed;
            }
        }
    }
    
    enum State {
        case handshaking
        case active
        case closed
    }
    
    enum Operation {
        case write
        case read
        case handshake
    }
    
    enum SSLError: Error {
        case unknown
        case closed
    }
    
    enum SSLStatus {
        case ok
        case want_read
        case want_write
        case fail
        
        static func from(code: Int32, connection: SSLProcessor) -> SSLStatus {
            guard code != 0 else {
                return .ok;
            }
            let status = SSL_get_error(connection.ssl, code);
            switch status {
            case SSL_ERROR_NONE:
                return .ok;
            case SSL_ERROR_WANT_READ:
                return .want_read;
            case SSL_ERROR_WANT_WRITE:
                return .want_write;
            default:
                return .fail;
            }
        }
    }
    
    fileprivate let ssl: OpaquePointer;
    
    private var state: State = .handshaking;
    private var readBio: OpaquePointer;
    private var writeBio: OpaquePointer;
    
    public var serverName: String? {
        didSet {
            _ = serverName?.withCString({
                SSL_ctrl(ssl, SSL_CTRL_SET_TLSEXT_HOSTNAME, Int(TLSEXT_NAMETYPE_host_name), UnsafeMutableRawPointer(mutating: $0));
            })
        }
    }
    
    public var certificateValidation: SSLCertificateValidation = .default;
    public var certificateValidationFailed: ((SecTrust?)->Void)?;
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "SSLProcessor");
    
    public init?(ssl: OpaquePointer, context: SSLContext) {
        self.ssl = ssl;
        self.readBio = BIO_new(BIO_s_mem());
        self.writeBio = BIO_new(BIO_s_mem());
        SSL_set_bio(ssl, readBio, writeBio);
        SSL_set_connect_state(ssl);
    }
    
    private static func protocolToBytes(_ proto: String) -> [UInt8] {
        let data = proto.data(using: .utf8)!;
        var bytes: [UInt8] = [UInt8](repeating: 0, count: data.count);
        data.copyBytes(to: &bytes, count: data.count);
        return [UInt8(data.count)] + bytes;
    }
    
    deinit {
        SSL_free(ssl);
    }
    
    open func setALPNProtocols(_ alpnProtocols: [String]) {
        if !alpnProtocols.isEmpty {
            var bytes = alpnProtocols.map { SSLProcessor.protocolToBytes($0) }.reduce(into: [UInt8](repeating: 0, count: 0), { result, value in result.append(contentsOf: value) });
            SSL_set_alpn_protos(ssl, &bytes, UInt32(bytes.count));
        }
    }
    
    private func status(code n: Int32) -> SSLStatus {
        let status = SSL_get_error(ssl, n);
        switch status {
        case SSL_ERROR_NONE:
            return .ok;
        case SSL_ERROR_WANT_READ:
            return .want_read;
        case SSL_ERROR_WANT_WRITE:
            return .want_write;
        default:
            return .fail;
        }
    }
    
    open override func read(data: Data) {
        try? decrypt(data: data);
    }
    
    open override func write(data: Data, completion: WriteCompletion) {
        encrypt(data: data, completion: completion);
    }
    
    open func decrypt(data: Data) throws {
        guard data.withUnsafeBytes({ bufPtr in
            return BIO_write(readBio, bufPtr.baseAddress!, Int32(data.count));
        }) == Int32(data.count) else {
            throw SSLError.closed;
        }
        
        switch state {
        case .handshaking:
            doHandshaking();
        case .active:
            readDataFromNetwork();
        case .closed:
            break;
        }
    }
     
    open func readDataFromNetwork() {
        var n: Int32 = 0;
        repeat {
            var buffer = [UInt8](repeating: 0, count: 2048);
            n = SSL_read(ssl, &buffer, 2048);
            if n > 0 {
                super.read(data: Data(bytes: &buffer, count: Int(n)));
            }
        } while n > 0;

        switch SSLStatus.from(code: n, connection: self) {
        case .want_write:
            writeDataToNetwork(completion: .none);
            break;
        case .want_read, .ok:
            break;
        case .fail:
            state = .closed;
            writeDataToNetwork(completion: .none);
        }
    }
    
    open func doHandshaking() {
        let result = HandshakeResult.from(code: SSL_do_handshake(ssl), connection: self);
        switch result {
        case .incomplete:
            state = .handshaking;
            writeDataToNetwork(completion: .none);
        case .complete:
            // we have completed handshake but we need to verify SSL certificate..
            guard let trust = getPeerTrust() else {
                self.certificateValidationFailed?(nil);
                return;
            }
            
            if let cert = SecTrustGetCertificateAtIndex(trust, 0 as CFIndex) {
                var commonName: CFString?;
                SecCertificateCopyCommonName(cert, &commonName);
                logger.debug("received SSL certificate for common name: \(String(describing: commonName))");
            }

            switch certificateValidation {
            case .default:
                let policy = SecPolicyCreateSSL(false, serverName as CFString?);
                var result = SecTrustResultType.invalid;
                SecTrustSetPolicies(trust, policy);
                _ = SecTrustEvaluateWithError(trust, nil);
                SecTrustGetTrustResult(trust, &result);
                logger.debug("certificate validation result: \(result.name)");
                guard result == .proceed || result == .unspecified else {
                    self.certificateValidationFailed?(trust);
                    return;
                }
            case .fingerprint(let fingerprint):
                guard SslCertificateValidator.validateSslCertificate(domain: self.serverName ?? "", fingerprint: fingerprint, trust: trust) else {
                    self.certificateValidationFailed?(trust);
                    return;
                }
            case .customValidator(let validator):
                guard validator(trust) else {
                    self.certificateValidationFailed?(trust);
                    return;
                }
            }
            state = .active;

            // we need to detect ALPN protocols
            logger.debug("negotiated \(self.getProtocol().name) ALPN: \(self.getSelectedAlpnProtocol() ?? "nil")");
            
            readDataFromNetwork();
            writeDataToNetwork(completion: .none);
            encryptWaiting();
        case .failed:
            state = .closed;
            writeDataToNetwork(completion: .none);
        }
    }
    
    open func getPeerCertificate() -> SSLCertificate? {
        guard let ptr: OpaquePointer = SSL_get_peer_certificate(ssl) else {
            return nil;
        }
        return SSLCertificate(withOwnedReference: ptr);
    }
    
    open func getPeerCertificateChain() -> [SSLCertificate]? {
        guard let chainPtr = SSL_get_peer_cert_chain(ssl) else {
            return nil
        }
        
        var chains: [SSLCertificate] = [];
        var ptr: OpaquePointer?;
        repeat {
            ptr = sk_X509_shift(chainPtr)
            if ptr != nil {
                chains.append(SSLCertificate(withOwnedReference: ptr!));
            }
        } while ptr != nil;
        
        return chains;
    }
    
    open func getPeerTrust() -> SecTrust? {
        guard let chain = getPeerCertificateChain(), let cert = chain.first?.secCertificate() else {
            return nil;
        }
        
        var commonName: CFString?;
        SecCertificateCopyCommonName(cert, &commonName);
        var trust: SecTrust?;
        guard SecTrustCreateWithCertificates(chain.compactMap({ $0.secCertificate() }) as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess else {
            return nil;
        }
        return trust;
    }
    
    open func getSelectedAlpnProtocol() -> String? {
        var name = UnsafePointer<UInt8>(bitPattern: 0);
        var len: UInt32 = 0;
        
        SSL_get0_alpn_selected(ssl, &name, &len);
        guard len > 0 else {
            return nil;
        }
        return String(decoding: UnsafeBufferPointer(start: name, count: Int(len)), as: UTF8.self);
    }
    
    open func getProtocol() -> SSLProtocol {
        guard let session = SSL_get_session(ssl) else {
            return .unknown;
        }
        return SSLProtocol.from(protocolId: SSL_SESSION_get_protocol_version(session));
    }
    
    private struct Entry {
        public let data: Data;
        public let completion: WriteCompletion;
    }
    private var awaitingEncryption = Queue<Entry>();
    
    open func encryptWaiting() {
        guard !awaitingEncryption.isEmpty else {
            writeDataToNetwork(completion: .none);
            return;
        }
        var shouldContinue = true;
        while shouldContinue, let entry = awaitingEncryption.poll() {
            let n = entry.data.withUnsafeBytes({ bufPtr in
                return SSL_write(ssl, bufPtr.baseAddress!, Int32(entry.data.count));
            })
            switch SSLStatus.from(code: n, connection: self) {
            case .want_write, .ok:
                writeDataToNetwork(completion: entry.completion);
            case .want_read:
                shouldContinue = true;
                break;
            case .fail:
                shouldContinue = false;
                state = .closed;
                writeDataToNetwork(completion: .none);
                entry.completion.completed(result: .failure(XMPPError.undefined_condition));
            }
        }
    }
    
    open func encrypt(data: Data, completion: WriteCompletion) {
        if !data.isEmpty {
            awaitingEncryption.offer(.init(data: data, completion: completion));
        }
        
        switch state {
        case .handshaking:
            doHandshaking();
        case .active:
            encryptWaiting();
        case .closed:
            break;
        }
    }
    
    open func writeDataToNetwork(completion: WriteCompletion) {
        var n: Int32 = 0;
        repeat {
            let waiting = BIO_ctrl_pending(writeBio);
            var buffer = [UInt8](repeating: 0, count: waiting);
            n = BIO_read(writeBio, &buffer, Int32(waiting));
            if n > 0 {
                super.write(data: Data(bytes: &buffer, count: Int(n)), completion: completion);
            }
        } while n > 0;
    }

}

public struct SSLProcessorProvider: NetworkProcessorProvider {
    
    public let providedFeatures: [ConnectorFeature] = [.TLS];
    public let supportedTlsVersions: ClosedRange<TLSVersion>;
        
    public init(supportedTlsVersions: ClosedRange<TLSVersion> = TLSVersion.TLSv1_2...TLSVersion.TLSv1_3) {
        self.supportedTlsVersions = supportedTlsVersions;
    }
    
    public func supply() -> SocketConnector.NetworkProcessor {
        let context = SSLContext(supportedTlsVersions: supportedTlsVersions)!;
        return context.createConnection()!;
    }
    
}
