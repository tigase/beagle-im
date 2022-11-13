//
// AccountManager.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
import Security
import Martin
import Combine

open class AccountManager {
    
    private static let serviceName = "BeagleIM";
    private static let queue = DispatchQueue(label: "AccountManager");
    private static var _accounts: [BareJID: Account] = [:];
    
    public static var accounts: [Account] {
        return queue.sync {
            return Array(_accounts.values);
        }
    }
    
    public static let accountEventsPublisher = PassthroughSubject<Event,Never>();
    
    static var defaultAccount: BareJID? {
        get {
            return BareJID(Settings.defaultAccount);
        }
        set {
            Settings.defaultAccount = newValue?.description;
        }
    }
    
    public static func initialize() throws {
        try queue.sync {
            try reloadAccounts();
        }
    }
    
    @available(*, deprecated, message: "Will be removed in future versions after account data conversion is completed")
    public static func convertOldAccounts() throws {
        try queue.sync {
            guard _accounts.isEmpty else {
                return;
            }
            
            let query = [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitAll, String(kSecReturnAttributes) : kCFBooleanTrue as Any, String(kSecAttrService) : "xmpp" ] as [String : Any];
            var result: CFTypeRef?;

            guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
                return;
            }
            
            guard let results = result as? [[String: NSObject]] else {
                return;
            }

            let accounts = results.filter({ $0[kSecAttrAccount as String] != nil}).map { item -> BareJID in
                return BareJID(item[kSecAttrAccount as String] as! String);
            }.sorted(by: { (j1, j2) -> Bool in
                j1.description.compare(j2.description) == .orderedAscending
            });
            
            for name in accounts {
                if let oldAccount = getAccountOld(for: name) {
                    var newAccount = Account(name: name, enabled: oldAccount.active);
                    newAccount.serverEndpoint = oldAccount.endpoint;
                    newAccount.rosterVersion = oldAccount.rosterVersion;
                    newAccount.disableTLS13 = oldAccount.disableTLS13;
                    newAccount.acceptedCertificate = oldAccount.serverCertificate?.acceptableServerCertificate();
                    newAccount.nickname = oldAccount.nickname;
                    newAccount.statusMessage = oldAccount.presenceDescription;
                    switch oldAccount.resourceType {
                    case .automatic:
                        newAccount.additional.resourceType = .automatic;
                    case .hostname:
                        newAccount.additional.resourceType = .hostname;
                    case .custom:
                        newAccount.additional.resourceType = .manual(oldAccount.resourceName ?? "UNKNOWN");
                    }

                    newAccount.omemoDeviceId = UserDefaults.standard.value(forKey: "accounts.\(name).omemoRegistrationId") as? UInt32;
                    if let features = UserDefaults.standard.value(forKey: "accounts.\(name).KnownServerFeatures") as? [String] {
                        newAccount.additional.knownServerFeatures = features.compactMap({ ServerFeature(rawValue: $0) });
                    }

                    try DBAccountStore.create(account: newAccount);
                }
                
                let prefix = "accounts.\(name).";
                let toRemove = UserDefaults.standard.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) };
                toRemove.forEach { (key) in
                    UserDefaults.standard.removeObject(forKey: key);
                }
            }
            try reloadAccounts();
        }
    }
    
    @available(*, deprecated, message: "Will be removed in future versions after account data conversion is completed")
    private static func getAccountOld(for jid: BareJID) -> AccountOld? {
        let query = AccountManager.getAccountQueryOld(jid.description);
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return nil;
        }
        
        guard let r = result as? [String: NSObject] else {
            return nil;
        }
        
        var dict: [String: Any]? = nil;
        if let data = r[String(kSecAttrGeneric)] as? NSData {
            NSKeyedUnarchiver.setClass(ServerCertificateInfoOld.self, forClassName: "BeagleIM.ServerCertificateInfo");
            dict = NSKeyedUnarchiver.unarchiveObject(with: data as Data) as? [String: Any];
        }
        
        return AccountOld(name: jid, data: dict);
    }
    
    private static func reloadAccounts() throws {
//        self._accounts.removeAll();
        let accounts = try DBAccountStore.list();
        for source in accounts {
            if var account = self._accounts[source.name] {
                if let credentials = credentials(for: account.name) {
                    account.credentials = credentials;
                    account.serverEndpoint = source.serverEndpoint;
                    account.acceptedCertificate = source.acceptedCertificate;
                    account.enabled = source.enabled;
                    account.additional = source.additional;
                    self._accounts[account.name] = account;
                    
                    DispatchQueue.main.async {
                        self.accountEventsPublisher.send(account.enabled ? .enabled(account, false) : .disabled(account));
                    }
                }
            } else {
                var account = source;
                if let credentials = credentials(for: account.name) {
                    account.credentials = credentials;
                    self._accounts[account.name] = account;
                }
            }
        }
    }
    
    public static func activeAccounts() -> [Account] {
        return queue.sync {
            return _accounts.values.filter({ $0.enabled });
        }
    }
    
    public static func accountNames() -> [BareJID] {
        return self.queue.sync {
            return _accounts.keys.sorted(by: { (j1, j2) -> Bool in
                j1.description.compare(j2.description) == .orderedAscending;
            });
        }
    }

    public static func account(for jid: BareJID) -> Account? {
        return self.queue.sync {
            return self._accounts[jid];
        }
    }
    
    private static func credentials(for account: BareJID) -> Credentials? {
        let query = AccountManager.accountQuery(account.description, withData: kSecReturnData);
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr, let data = result as? Data else {
            do {
                guard let password = passwordOld(for: account) else {
                    return nil;
                }
                let newCred = Credentials.password(password);
                try credentials(newCred, for: account);
                try deleteAccountOldCredentials(for: account);
                return newCred;
            } catch {
                return nil;
            }
        }
        
        guard let credentials = try? JSONDecoder().decode(Credentials.self, from: data) else {
            return nil;
        }

        return credentials;
    }
    
    private static func passwordOld(for account: BareJID) -> String? {
        let query = AccountManager.getAccountQueryOld(account.description, withData: kSecReturnData);

        
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return nil;
        }
        
        guard let data = result as? Data else {
            return nil;
        }
        
        return String(data: data, encoding: .utf8);
    }
    
    private static func credentials(_ credentials: Credentials, for account: BareJID) throws {
        var query = AccountManager.accountQuery(account.description);
        query.removeValue(forKey: String(kSecMatchLimit));
        query.removeValue(forKey: String(kSecReturnAttributes));
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock;

        let data = try JSONEncoder().encode(credentials);
        if let updateError = AccountManagerError(status: SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)) {
            if updateError.status == errSecItemNotFound {
                query[kSecValueData as String] = data;
                if let insertError = AccountManagerError(status: SecItemAdd(query as CFDictionary, nil)) {
                    throw insertError;
                }
            } else {
                throw updateError;
            }
        }
    }
    
    public static func modifyAccount(for jid: BareJID, _ block: @escaping (inout Account)->Void) throws {
        try self.queue.sync {
            let oldValue = _accounts[jid];
            
            var newValue = oldValue ?? Account(name: jid, enabled: true);
            block(&newValue);
            
            guard !newValue.credentials.isEmpty else {
                throw XMPPError(condition: .bad_request);
            }

            if newValue.credentials != oldValue?.credentials {
                try self.credentials(newValue.credentials, for: newValue.name);
            }
            
            if let oldValue = oldValue {
                try DBAccountStore.update(from: oldValue, to: newValue)
            } else {
                try DBAccountStore.create(account: newValue);
            }
                         
            self._accounts[newValue.name] = newValue;
                        
            let reconnect = oldValue?.credentials.password != newValue.credentials.password || oldValue?.acceptedCertificate != newValue.acceptedCertificate || oldValue?.enabled != newValue.enabled || oldValue?.serverEndpoint != newValue.serverEndpoint || oldValue?.omemoDeviceId != newValue.omemoDeviceId;
            
            DispatchQueue.main.async {
                self.accountEventsPublisher.send(newValue.enabled ? .enabled(newValue, reconnect) : .disabled(newValue));
            }
        }
    }

    public static func deleteAccount(for jid: BareJID) throws {
        try queue.sync {
            var query = AccountManager.accountQuery(jid.description);
            query.removeValue(forKey: String(kSecMatchLimit));
            query.removeValue(forKey: String(kSecReturnAttributes));
            
            if let error = AccountManagerError(status: SecItemDelete(query as CFDictionary)) {
                throw error;
            }
            
            guard let account = self._accounts.removeValue(forKey: jid) else {
                return;
            }
            
            DispatchQueue.main.async {
                self.accountEventsPublisher.send(.removed(account));
            }
        }
    }
    
    private static func deleteAccountOldCredentials(for jid: BareJID) throws {
        var query = AccountManager.getAccountQueryOld(jid.description);
        query.removeValue(forKey: String(kSecMatchLimit));
        query.removeValue(forKey: String(kSecReturnAttributes));
        
        if let error = AccountManagerError(status: SecItemDelete(query as CFDictionary)) {
            throw error;
        }
    }
    
    fileprivate static func getAccountQueryOld(_ name:String, withData:CFString = kSecReturnAttributes) -> [String: Any] {
        return [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(withData) : kCFBooleanTrue!, String(kSecAttrService) : "xmpp" as NSObject, String(kSecAttrAccount) : name as NSObject ];
    }

    fileprivate static func accountQuery(_ name:String, withData:CFString = kSecReturnAttributes) -> [String: Any] {
        return [ String(kSecClass) : kSecClassGenericPassword, String(kSecMatchLimit) : kSecMatchLimitOne, String(withData) : kCFBooleanTrue!, String(kSecAttrService) : serviceName as NSObject, String(kSecAttrAccount) : name as NSObject ];
    }
    
    public enum Event {
            case enabled(Account,Bool)
            case disabled(Account)
            case removed(Account)
        }
        
    public struct AccountManagerError: LocalizedError, CustomDebugStringConvertible {
        public let status: OSStatus;
        public let message: String?;
        
        public var errorDescription: String? {
            return "\(NSLocalizedString("It was not possible to modify account.", comment: "error description message"))\n\(message ?? "\(NSLocalizedString("Error code", comment: "error description message - detail")): \(status)")";
        }
        
        public var failureReason: String? {
            return message;
        }
        
        public var recoverySuggestion: String? {
            return NSLocalizedString("Try again. If removal failed, try accessing Keychain to update account credentials manually.", comment: "error recovery suggestion");
        }
        
        public var debugDescription: String {
            return "AccountManagerError(status: \(status), message: \(message ?? "nil"))";
        }
        
        public init?(status: OSStatus) {
            guard status != noErr else {
                return nil;
            }
            self.status = status;
            message = SecCopyErrorMessageString(status, nil) as String?;
        }
    }
        
    @available(*, deprecated, message: "Will be removed in future versions after account data conversion is completed")
    struct AccountOld {
        
        public var state = CurrentValueSubject<XMPPClient.State,Never>(.disconnected());
                
        public let name: BareJID;

        fileprivate var data:[String: Any];

        public var active:Bool {
            get {
                return (data["active"] as? Bool) ?? true;
            }
            set {
                data["active"] = newValue as AnyObject?;
            }
        }
        
        public var nickname: String? {
            get {
                guard let nick = data["nickname"] as? String, !nick.isEmpty else {
                    return name.localPart;
                }
                return nick;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "nickname");
                } else {
                    data["nickname"] = newValue;
                }
            }
        }
        
        public var resourceName: String? {
            get {
                return data["resourceName"] as? String;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "resourceName")
                } else {
                    data["resourceName"] = newValue;
                }
            }
        }
        
        public var resourceType: ResourceType {
            get {
                guard let val = data["resourceType"] as? String, let r = ResourceType(rawValue: val) else {
                    return .automatic;
                }
                return r;
            }
            set {
                data["resourceType"] = newValue.rawValue;
            }
        }
        
        public var server:String? {
            get {
                return data["serverHost"] as? String;
            }
            set {
                if newValue != nil {
                    data["serverHost"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "serverHost");
                }
            }
        }
        
        public var rosterVersion:String? {
            get {
                return data["rosterVersion"] as? String;
            }
            set {
                if newValue != nil {
                    data["rosterVersion"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "rosterVersion");
                }
            }
        }
        
        public var presenceDescription: String? {
            get {
                return data["presenceDescription"] as? String;
            }
            set {
                if newValue != nil {
                    data["presenceDescription"] = newValue as AnyObject?;
                } else {
                    data.removeValue(forKey: "presenceDescription");
                }
            }
        }
        
        public var pushNotifications: Bool {
            get {
                return (data["pushNotifications"] as? Bool) ?? false;
            }
            set {
                data["pushNotifications"] = newValue as AnyObject?;
            }
        }
                
        public var serverCertificate: ServerCertificateInfoOld? {
            get {
                return data["serverCert"] as? ServerCertificateInfoOld;
            }
            set {
                if newValue != nil {
                    data["serverCert"] = newValue;
                } else {
                    data.removeValue(forKey: "serverCert");
                }
            }
        }
        
        public var saltedPassword: SaltEntry? {
            get {
                return SaltEntry(dict: data["saltedPassword"] as? [String: Any]);
            }
            set {
                if newValue != nil {
                    data["saltedPassword"] = newValue!.dictionary() as AnyObject?;
                } else {
                    data.removeValue(forKey: "saltedPassword");
                }
            }
        }
        
        public var disableTLS13: Bool {
            get {
                return data["disableTLS13"] as? Bool ?? false;
            }
            set {
                if newValue {
                    data["disableTLS13"] = newValue;
                } else {
                    data.removeValue(forKey: "disableTLS13");
                }
            }
        }
        
        public var endpoint: SocketConnectorNetwork.Endpoint? {
            get {
                guard let values = data["endpoint"] as? [String: Any], let protoStr = values["proto"] as? String, let proto = ConnectorProtocol(rawValue: protoStr), let host = values["host"] as? String, let port = values["port"] as? Int else {
                    return nil;
                }
                return SocketConnectorNetwork.Endpoint(proto: proto, host: host, port: port);
            }
            set {
                if let value = newValue {
                    data["endpoint"] = [ "proto": value.proto.rawValue, "host": value.host, "port": value.port ];
                } else {
                    data.removeValue(forKey: "endpoint");
                }
            }
        }
                
        public init(name: BareJID, data: [String: Any]? = nil) {
            self.name = name;
            self.data = data ?? [String: Any]();
        }
        
        public mutating func acceptCertificate(_ certData: SslCertificateInfoOld?) {
            guard let data = certData else {
                self.serverCertificate = nil;
                return;
            }
            self.serverCertificate = ServerCertificateInfoOld(sslCertificateInfo: data, accepted: true);
        }
        
        enum ResourceType: String {
            case automatic
            case hostname
            case custom
        }
    }
    
    @available(*, deprecated, message: "Not used any more")
    open class SaltEntry {
        public let id: String;
        public let value: [UInt8];
        
        convenience init?(dict: [String: Any]?) {
            guard let id = dict?["id"] as? String, let value = dict?["value"] as? [UInt8] else {
                return nil;
            }
            self.init(id: id, value: value);
        }
        
        public init(id: String, value: [UInt8]) {
            self.id = id;
            self.value = value;
        }
        
        open func dictionary() -> [String: Any] {
            return ["id": id, "value": value];
        }
    }
}
