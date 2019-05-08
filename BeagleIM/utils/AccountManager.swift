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
import TigaseSwift

open class AccountManager {
    
    public static let ACCOUNT_CHANGED = Notification.Name(rawValue: "accountChanged");

    static var defaultAccount: BareJID? {
        get {
            return Settings.defaultAccount.bareJid();
        }
        set {
            Settings.defaultAccount.set(bareJid: newValue);
        }
    }
    
    static func getAccounts() -> [BareJID] {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnAttributes as String: kCFBooleanTrue as Any, kSecAttrService as String: "xmpp"];
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return [];
        }
        
        guard let results = result as? [[String: NSObject]] else {
            return [];
        }
        
        return results.map { item -> BareJID in
            return BareJID(item[kSecAttrAccount as String] as! String);
            }.sorted(by: { (j1, j2) -> Bool in
                j1.stringValue.compare(j2.stringValue) == .orderedAscending
            });
    }
    
    static func getActiveAccounts() -> [BareJID] {
        return getAccounts().filter({ jid -> Bool in
            return AccountManager.getAccount(for: jid)?.active ?? false
        });
    }
    
    static func getAccount(for jid: BareJID) -> Account? {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnAttributes as String: kCFBooleanTrue as Any, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : jid.stringValue as NSObject ];
        
        var result: CFTypeRef?;
        
        guard SecItemCopyMatching(query as CFDictionary, &result) == noErr else {
            return nil;
        }
        
        guard let r = result as? [String: NSObject] else {
            return nil;
        }
        
        let dict = AccountManager.parseDict(from: r[kSecAttrGeneric as String] as? Data);
        
        return Account(name: jid, data: dict);
    }
    
    static func save(account: Account) -> Bool {
        var query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : account.name.stringValue as NSObject ];
        var update: [String: Any] = [ kSecAttrGeneric as String: try! NSKeyedArchiver.archivedData(withRootObject: account.data, requiringSecureCoding: false), kSecAttrAccessible as String: kSecAttrAccessibleAlwaysThisDeviceOnly ];
        if let newPassword = account.newPassword {
            update[kSecValueData as String] = newPassword.data(using: .utf8)!;
        }
        var result = false;
        if getAccount(for: account.name) == nil {
            query.merge(update) { (v1, v2) -> Any in
                return v1;
            }
            result = SecItemAdd(query as CFDictionary, nil) == noErr;
        } else {
            result = SecItemUpdate(query as CFDictionary, update as CFDictionary) == noErr;
        }
        if result {
            account.newPassword = nil;
        }
        
        if defaultAccount == nil {
            defaultAccount = account.name;
        }
        
        AccountManager.accountChanged(account: account);
        
        return result;
    }
    
    static func delete(account: Account) -> Bool {
        let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : account.name.stringValue as NSObject ];
        
        guard SecItemDelete(query as CFDictionary) == noErr else {
            return false;
        }
        
        if let defAccount = defaultAccount, defAccount == account.name {
            defaultAccount = AccountManager.getAccounts().first;
        }
        
        AccountManager.accountChanged(account: account);

        return true;
    }
    
    static fileprivate func parseDict(from data: Data?) -> [String: Any]? {
        guard data != nil else {
            return nil;
        }
        
        return try? NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data!) as? [String: Any];
    }
    
    static fileprivate func accountChanged(account: Account) {
        NotificationCenter.default.post(name: AccountManager.ACCOUNT_CHANGED, object: account);
    }
    
    class Account {
        
        fileprivate var data: [String: Any];
        fileprivate var newPassword: String?;
        
        public let name: BareJID;
        
        open var password: String? {
            get {
                guard newPassword == nil else {
                    return newPassword;
                }
                return getPassword();
            }
            set {
                self.newPassword = newValue;
            }
        }
        
        open var active: Bool {
            get {
                return data["active"] as? Bool ?? false;
            }
            set {
                data["active"] = newValue;
            }
        }
        
        open var nickname: String? {
            get {
                return data["nickname"] as? String;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "nickname");
                } else {
                    data["nickname"] = newValue;
                }
            }
        }
        
        open var resourceType: ResourceType {
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
        
        open var resourceName: String? {
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
        
        open var serverCertificate: ServerCertificateInfo? {
            get {
                return data["serverCertificateInfo"] as? ServerCertificateInfo;
            }
            set {
                if newValue == nil {
                    data.removeValue(forKey: "serverCertificateInfo");
                } else {
                    data["serverCertificateInfo"] = newValue;
                }
            }
        }
        
        public init(name: BareJID) {
            self.name = name;
            self.data = ["active": true];
        }
        
        fileprivate init(name: BareJID, data: [String: Any]?) {
            self.name = name;
            self.data = data ?? [:];
        }
        
        fileprivate func getPassword() -> String? {
            let query: [String: Any] = [ kSecClass as String: kSecClassGenericPassword, kSecMatchLimit as String: kSecMatchLimitOne, kSecReturnData as String: kCFBooleanTrue as Any, kSecAttrService as String: "xmpp" as NSObject, kSecAttrAccount as String : name.stringValue as NSObject ];
            var result: CFTypeRef?;
                
            let r = SecItemCopyMatching(query as CFDictionary, &result);
            guard r == noErr else {
                return nil;
            }
                
            guard let data = result as? Data else {
                return nil;
            }
                
            return String(data: data, encoding: .utf8);
        }
     
        enum ResourceType: String {
            case automatic
            case hostname
            case custom
        }
    }
}
