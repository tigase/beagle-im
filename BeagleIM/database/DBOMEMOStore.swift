//
// OMEMOStore.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import TigaseSwift
import TigaseSwiftOMEMO

class DBOMEMOStore {
    
    public static let instance = DBOMEMOStore();
    
    fileprivate let keyPairForAccountStmt = try! DBConnection.main.prepareStatement("SELECT key FROM omemo_identities WHERE account = :account AND own = 1");
    fileprivate let updateKeyPairStmt = try! DBConnection.main.prepareStatement("UPDATE omemo_identities SET key = :key, fingerprint = :fingerprint, own = :own WHERE account = :account AND name = :name AND device_id = :deviceId");
    fileprivate let loadKeyPairStatusStmt = try! DBConnection.main.prepareStatement("SELECT status FROM omemo_identities WHERE account = :account AND name = :name AND device_id = :deviceId");
    fileprivate let updateKeyPairStatusStmt = try! DBConnection.main.prepareStatement("UPDATE omemo_identities SET status = :status WHERE account = :account AND name = :name AND device_id = :deviceId");
    fileprivate let insertKeyPairStmt = try! DBConnection.main.prepareStatement("INSERT INTO omemo_identities (account, name, device_id, key, fingerprint, own, status) VALUES (:account,:name,:deviceId,:key,:fingerprint,:own,:status)");
    fileprivate let wipeIdentitiesKeyStoreStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_identities WHERE account = :account");
    fileprivate let getIdentityStmt = try! DBConnection.main.prepareStatement("SELECT device_id, fingerprint, status, key, own FROM omemo_identities WHERE account = :account AND name = :name");
    fileprivate let getIdentityFingerprintStmt = try! DBConnection.main.prepareStatement("SELECT fingerprint FROM omemo_identities WHERE account = :account AND name = :name AND device_id = :deviceId");

    fileprivate let currentPreKeyStmt = try! DBConnection.main.prepareStatement("SELECT max(id) FROM omemo_pre_keys WHERE account = :account");
    fileprivate let loadPreKeyStmt = try! DBConnection.main.prepareStatement("SELECT key FROM omemo_pre_keys WHERE account = :account AND id = :id");
    fileprivate let insertPreKeyStmt = try! DBConnection.main.prepareStatement("INSERT INTO omemo_pre_keys (account, id, key) VALUES (:account,:id,:key)");
    fileprivate let containsPreKeyStmt = try! DBConnection.main.prepareStatement("SELECT count(1) FROM omemo_pre_keys WHERE account = :account AND id = :id");
    fileprivate let deletePreKeyStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_pre_keys WHERE account = :account AND id = :id");
    fileprivate let wipePreKeyStoreStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_pre_keys WHERE account = :account");

    fileprivate let loadSignedPreKeyStmt = try! DBConnection.main.prepareStatement("SELECT key FROM omemo_signed_pre_keys WHERE account = :account AND id = :id");
    fileprivate let insertSignedPreKeyStmt = try! DBConnection.main.prepareStatement("INSERT INTO omemo_signed_pre_keys (account, id, key) VALUES (:account,:id,:key)");
    fileprivate let containsSignedPreKeyStmt = try! DBConnection.main.prepareStatement("SELECT count(1) FROM omemo_signed_pre_keys WHERE account = :account AND id = :id");
    fileprivate let deleteSignedPreKeyStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_signed_pre_keys WHERE account = :account AND id = :id");
    fileprivate let countSignedPreKeysStmt = try! DBConnection.main.prepareStatement("SELECT count(1) FROM omemo_signed_pre_keys WHERE account = :account");
    fileprivate let wipeSignedPreKeyStoreStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_signed_pre_keys WHERE account = :account");

    fileprivate let loadSessionRecordStmt = try! DBConnection.main.prepareStatement("SELECT key FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId");
    fileprivate let getAllDevicesStmt = try! DBConnection.main.prepareStatement("SELECT device_id FROM omemo_sessions WHERE account = :account AND name = :name");
    fileprivate let getAllActivateAndTrustedDevicesStmt = try! DBConnection.main.prepareStatement("SELECT s.device_id FROM omemo_sessions s INNER JOIN omemo_identities i ON s.account = i.account AND s.name = i.name AND s.device_id = i.device_id WHERE s.account = :account AND s.name = :name AND (i.status >= 0 AND i.status % 2 = 0)");
    fileprivate let insertSessionRecordStmt = try! DBConnection.main.prepareStatement("INSERT INTO omemo_sessions (account, name, device_id, key) VALUES (:account, :name, :deviceId, :key)");
    fileprivate let containsSessionRecordStmt = try! DBConnection.main.prepareStatement("SELECT count(1) FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId");
    fileprivate let deleteSessionRecordStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId");
    fileprivate let deleteAllSessionRecordStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_sessions WHERE account = :account AND name = :name");
    fileprivate let wipeSessionsStoreStmt = try! DBConnection.main.prepareStatement("DELETE FROM omemo_sessions WHERE account = :account");
    
    func keyPair(forAccount account: BareJID) -> SignalIdentityKeyPairProtocol? {
        guard let data = try! keyPairForAccountStmt.queryFirstMatching(["account": account], forEachRowUntil: { (cursor) -> Data? in
            return cursor["key"];
        }) else {
            return nil;
        }
        
        return SignalIdentityKeyPair(fromKeyPairData: data);
    }
    
    func identityFingerprint(forAccount account: BareJID, andAddress address: SignalAddress) -> String? {
        let params: [String: Any?] = ["account": account, "name": address.name, "deviceId": address.deviceId];
        return try! getIdentityFingerprintStmt.queryFirstMatching(params, forEachRowUntil: { (cursor) -> String? in
            return cursor["fingerprint"];
        });
    }
    
    func identities(forAccount account: BareJID, andName name: String) -> [Identity] {
        let params: [String: Any?] = ["account": account, "name": name];
        return try! getIdentityStmt.query(params, map: { (cursor) -> Identity? in
            guard let deviceId: Int32 = cursor["device_id"], let fingerprint: String = cursor["fingerprint"], let statusInt: Int = cursor["status"], let status = IdentityStatus(rawValue: statusInt), let own: Int = cursor["own"], let key: Data = cursor["key"] else {
                return nil;
            }
            return Identity(address: SignalAddress(name: name, deviceId: deviceId), status: status, fingerprint: fingerprint, key: key, own: own > 0);
        })
    }
    
    func localRegistrationId(forAccount account: BareJID) -> UInt32? {
        return AccountSettings.omemoRegistrationId(account).uint32();
    }
    
    func save(identity: SignalAddress, key: SignalIdentityKeyProtocol?, forAccount account: BareJID, own: Bool = false) -> Bool {
        guard key != nil else {
            // should we remove this key?
            return false;
        }
        guard let publicKeyData = key?.publicKey else {
            return false;
        }
        
        let fingerprint: String = publicKeyData.map { (byte) -> String in
            return String(format: "%02x", byte)
            }.joined();
        var params: [String: Any?] = ["account": account, "name": identity.name, "deviceId": identity.deviceId, "key": key!.serialized(), "fingerprint": fingerprint, "own": (own ? 1 : 0)];
        
        defer {
            _ = self.setStatus(.verifiedActive, forIdentity: identity, andAccount: account);
        }
        if try! updateKeyPairStmt.update(params) == 0 {
            params["status"] = IdentityStatus.verifiedActive.rawValue;
            return try! insertKeyPairStmt.insert(params) != 0;
        }
        
        return true;
    }

    func save(identity: SignalAddress, publicKeyData: Data?, forAccount account: BareJID, own: Bool = false) -> Bool {
        guard publicKeyData != nil else {
            // should we remove this key?
            return false;
        }
        
        let fingerprint: String = publicKeyData!.map { (byte) -> String in
            return String(format: "%02x", byte)
            }.joined();
        var params: [String: Any?] = ["account": account, "name": identity.name, "deviceId": identity.deviceId, "key": publicKeyData!, "fingerprint": fingerprint, "own": (own ? 1 : 0)];
        if try! updateKeyPairStmt.update(params) == 0 {
            // we are blindtrusting the remote identity
            params["status"] = IdentityStatus.trustedActive.rawValue;
            return try! insertKeyPairStmt.insert(params) != 0;
        }
        return true;
    }
    
    func setStatus(_ status: IdentityStatus, forIdentity identity: SignalAddress,  andAccount account: BareJID) -> Bool {
        return try! updateKeyPairStatusStmt.update(["account": account, "name": identity.name, "deviceId": identity.deviceId, "status": status.rawValue] as [String: Any?]) > 0;
    }

    func setStatus(active: Bool, forIdentity identity: SignalAddress,  andAccount account: BareJID) -> Bool {
        var params = ["account": account, "name": identity.name, "deviceId": identity.deviceId] as [String: Any?];
        guard let status = try! loadKeyPairStatusStmt.findFirst(params, map: { (cursor) -> IdentityStatus in
            guard let val: Int = cursor["status"] else {
                return IdentityStatus.undecidedActive;
            };
            return IdentityStatus(rawValue: val) ?? .undecidedActive;
        }) else {
            return false;
        }
        params["status"] = (active ? status.toActive() : status.toInactive()).rawValue;
        return try! updateKeyPairStatusStmt.update(params) > 0;
    }
    
    func currentPreKeyId(forAccount account: BareJID) -> UInt32 {
        return try! UInt32(currentPreKeyStmt.scalar(["account": account] as [String: Any?]) ?? 0);
    }
    
    func loadPreKey(forAccount account: BareJID, withId: UInt32) -> Data? {
        return try! loadPreKeyStmt.findFirst(["account": account, "id": withId] as [String: Any?], map: { (cursor) -> Data? in
            return cursor["key"];
        })
    }
    
    func store(preKey: Data, forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! insertPreKeyStmt.insert(["account": account, "id": withId, "key": preKey] as [String: Any?]) != 0;
    }

    func containsPreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return (try! containsPreKeyStmt.scalar(["account": account, "id": withId] as [String: Any?]) ?? 0) > 0;
    }

    func deletePreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! deletePreKeyStmt.update(["account": account, "id": withId] as [String: Any?]) > 0;
    }
    
    func countSignedPreKeys(forAccount account: BareJID) -> Int {
        return try! countSignedPreKeysStmt.scalar(["account": account] as [String: Any?]) ?? 0;
    }

    func loadSignedPreKey(forAccount account: BareJID, withId: UInt32) -> Data? {
        return try! loadSignedPreKeyStmt.findFirst(["account": account, "id": withId] as [String: Any?], map: { (cursor) -> Data? in
            return cursor["key"];
        })
    }
    
    func store(signedPreKey: Data, forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! insertSignedPreKeyStmt.insert(["account": account, "id": withId, "key": signedPreKey] as [String: Any?]) != 0;
    }
    
    func containsSignedPreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return (try! containsSignedPreKeyStmt.scalar(["account": account, "id": withId] as [String: Any?]) ?? 0) > 0;
    }
    
    func deleteSignedPreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! deleteSignedPreKeyStmt.update(["account": account, "id": withId] as [String: Any?]) > 0;
    }
    
    func sessionRecord(forAccount account: BareJID, andAddress address: SignalAddress) -> Data? {
        return try! loadSessionRecordStmt.findFirst(["account": account, "name": address.name, "deviceId": address.deviceId] as [String: Any?], map: { (cursor) -> Data? in
            return cursor["key"];
        });
    }

    func allDevices(forAccount account: BareJID, andName name: String, activeAndTrusted: Bool) -> [Int32] {
        let params: [String: Any?] = ["account": account, "name": name];
        if activeAndTrusted {
            return try! getAllActivateAndTrustedDevicesStmt.query(params, map: { (cursor) in
                return cursor["device_id"];
            });
        } else {
            return try! getAllDevicesStmt.query(params, map: { (cursor) in
                return cursor["device_id"];
            });
        }
    }
    
    func store(sessionRecord: Data, forAccount account: BareJID, andAddress address: SignalAddress) -> Bool {
        return (try! insertSessionRecordStmt.insert(["account": account, "name": address.name, "deviceId": address.deviceId, "key": sessionRecord] as [String: Any?]) ?? 0) > 0;
    }
    
    func containsSessionRecord(forAccount account: BareJID, andAddress address: SignalAddress) -> Bool {
        return (try! containsSessionRecordStmt.scalar(["account": account, "name": address.name, "deviceId": address.deviceId] as [String: Any?]) ?? 0) > 0;
    }
    
    func deleteSessionRecord(forAccount account: BareJID, andAddress address: SignalAddress) -> Bool {
        return try! deleteSessionRecordStmt.update(["account": account, "name": address.name, "deviceId": address.deviceId] as [String: Any?]) > 0;
    }
    
    func deleteAllSessions(forAccount account: BareJID, andName name: String) -> Bool {
        return try! deleteAllSessionRecordStmt.update(["account": account, "name": name] as [String: Any?]) > 0;
    }
    
    func wipe(forAccount account: BareJID) {
        try! wipeSessionsStoreStmt.update(["account": account] as [String: Any?]);
        try! wipePreKeyStoreStmt.update(["account": account] as [String: Any?]);
        try! wipeSignedPreKeyStoreStmt.update(["account": account] as [String: Any?]);
        try! wipeIdentitiesKeyStoreStmt.update(["account": account] as [String: Any?]);
    }
}

class SignalIdentityKeyStore: SignalIdentityKeyStoreProtocol, ContextAware {
    
    var context: Context!;
    
    func keyPair() -> SignalIdentityKeyPairProtocol? {
        return DBOMEMOStore.instance.keyPair(forAccount: context.sessionObject.userBareJid!);
    }
    
    func localRegistrationId() -> UInt32 {
        return DBOMEMOStore.instance.localRegistrationId(forAccount: context.sessionObject.userBareJid!) ?? 0;
    }
    
    func save(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        return DBOMEMOStore.instance.save(identity: identity, key: key, forAccount: context.sessionObject.userBareJid!, own: true)
    }
    
    func save(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        return DBOMEMOStore.instance.save(identity: identity, publicKeyData: publicKeyData, forAccount: context.sessionObject.userBareJid!);
    }
    
    func setStatus(_ status: IdentityStatus, forIdentity: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.setStatus(status, forIdentity: forIdentity, andAccount: context.sessionObject.userBareJid!);
    }
    
    func setStatus(active: Bool, forIdentity: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.setStatus(active: active, forIdentity: forIdentity, andAccount: context.sessionObject.userBareJid!);
    }

    func isTrusted(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        return true;
    }
    
    func isTrusted(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        return true;
    }
    
    func identityFingerprint(forAddress address: SignalAddress) -> String? {
        return DBOMEMOStore.instance.identityFingerprint(forAccount: self.context.sessionObject.userBareJid!, andAddress: address);
    }
    
    func identities(forName name: String) -> [Identity] {
        return DBOMEMOStore.instance.identities(forAccount: self.context.sessionObject.userBareJid!, andName: name);
    }
    
}

class SignalPreKeyStore: SignalPreKeyStoreProtocol, ContextAware {
    
    //fileprivate(set) var currentPreKeyId: UInt32 = 0;
    
    var context: Context!
//    {
//        didSet {
//            self.currentPreKeyId = AccountSettings.omemoCurrentPreKeyId(context.sessionObject.userBareJid!).uint32() ?? 0;
//        }
//    }

    func currentPreKeyId() -> UInt32 {
        return DBOMEMOStore.instance.currentPreKeyId(forAccount: context.sessionObject.userBareJid!);
    }
    
    func loadPreKey(withId: UInt32) -> Data? {
        return DBOMEMOStore.instance.loadPreKey(forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
    
    func storePreKey(_ data: Data, withId: UInt32) -> Bool {
        guard DBOMEMOStore.instance.store(preKey: data, forAccount: context.sessionObject.userBareJid!, withId: withId) else {
            return false;
        }
//        AccountSettings.omemoCurrentPreKeyId(context.sessionObject.userBareJid!).set(value: withId);
        return true;
    }
    
    func containsPreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.containsPreKey(forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
    
    func deletePreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.deletePreKey(forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
}

class SignalSignedPreKeyStore: SignalSignedPreKeyStoreProtocol, ContextAware {
    
    var context: Context!;
    
    func countSignedPreKeys() -> Int {
        return DBOMEMOStore.instance.countSignedPreKeys(forAccount: context.sessionObject.userBareJid!);
    }
    
    func loadSignedPreKey(withId: UInt32) -> Data? {
        return DBOMEMOStore.instance.loadSignedPreKey(forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
    
    func storeSignedPreKey(_ data: Data, withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.store(signedPreKey: data, forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
    
    func containsSignedPreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.containsSignedPreKey(forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
    
    func deleteSignedPreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.deleteSignedPreKey(forAccount: context.sessionObject.userBareJid!, withId: withId);
    }
}

class SignalSessionStore: SignalSessionStoreProtocol, ContextAware {
    
    var context: Context!;
    
    func sessionRecord(forAddress address: SignalAddress) -> Data? {
        return DBOMEMOStore.instance.sessionRecord(forAccount: context.sessionObject.userBareJid!, andAddress: address);
    }
    
    func allDevices(for name: String, activeAndTrusted: Bool) -> [Int32] {
        return DBOMEMOStore.instance.allDevices(forAccount: context.sessionObject.userBareJid!, andName: name, activeAndTrusted: activeAndTrusted);
    }
    
    func storeSessionRecord(_ data: Data, forAddress address: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.store(sessionRecord: data, forAccount: context.sessionObject.userBareJid!, andAddress: address);
    }
    
    func containsSessionRecord(forAddress: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.containsSessionRecord(forAccount: context.sessionObject.userBareJid!, andAddress: forAddress);
    }
    
    func deleteSessionRecord(forAddress: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.deleteSessionRecord(forAccount: context.sessionObject.userBareJid!, andAddress: forAddress);
    }
    
    func deleteAllSessions(for name: String) -> Bool {
        return DBOMEMOStore.instance.deleteAllSessions(forAccount: context.sessionObject.userBareJid!, andName: name);
    }
}

class OMEMOStoreWrapper: SignalStorage {
    
    fileprivate weak var context: Context?;
    fileprivate var signalContext: SignalContext?;
    
    init(context: Context) {
        self.context = context;
        let preKeyStore = SignalPreKeyStore();
        preKeyStore.context = context;
        let signedPreKeyStore = SignalSignedPreKeyStore();
        signedPreKeyStore.context = context;
        let identityKeyStore = SignalIdentityKeyStore();
        identityKeyStore.context = context;
        let sessionStore = SignalSessionStore();
        sessionStore.context = context;
        super.init(sessionStore: sessionStore, preKeyStore: preKeyStore, signedPreKeyStore: signedPreKeyStore, identityKeyStore: identityKeyStore, senderKeyStore: SignalSenderKeyStore());
    }
 
    override func setup(withContext signalContext: SignalContext) {
        self.signalContext = signalContext;
        _ = regenerateKeys(wipe: false);
        super.setup(withContext: signalContext);
    }
    
    override func regenerateKeys(wipe: Bool = false) -> Bool {
        guard let signalContext = self.signalContext else {
            return false;
        }

        if wipe {
            DBOMEMOStore.instance.wipe(forAccount: context!.sessionObject.userBareJid!);
        }

        let hasKeyPair = identityKeyStore.keyPair() != nil;
        if wipe || identityKeyStore.localRegistrationId() == 0 || !hasKeyPair {
            let regId: UInt32 = signalContext.generateRegistrationId();
            AccountSettings.omemoRegistrationId(context!.sessionObject.userBareJid!).set(value: regId);
        }
        if !hasKeyPair {
            print("no identity key pair! generating new one!");
            let keyPair = SignalIdentityKeyPair.generateKeyPair(context: signalContext);
            if !identityKeyStore.save(identity: SignalAddress(name: context!.sessionObject.userBareJid!.stringValue, deviceId: Int32(identityKeyStore.localRegistrationId())), key: keyPair) {
                print("failed to store identity key pair!");
            }
        }
        return true;
    }
}

class SignalSenderKeyStore: SignalSenderKeyStoreProtocol {
    
    func storeSenderKey(_ key: Data, address: SignalAddress?, groupId: String?) -> Bool {
        print("trying to store key for address:", address?.name as Any, " and group id:", groupId as Any);
        return false;
    }
    
    func loadSenderKey(forAddress address: SignalAddress?, groupId: String?) -> Data? {
        print("trying to load key for address:", address?.name as Any, " and group id:", groupId as Any);
        return nil;
    }
    
    
    
}
