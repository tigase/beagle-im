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
import Martin
import MartinOMEMO
import TigaseSQLite3

extension Query {
    static let omemoKeyPairForAccount = Query("SELECT key FROM omemo_identities WHERE account = :account AND name = :name AND device_id = :deviceId AND own = 1");
    static let omemoKeyPairExists = Query("SELECT count(1) FROM omemo_identities WHERE account = :account AND name = :name AND fingerprint = :fingerprint");
    static let omemoKeyPairInsert = Query("INSERT INTO omemo_identities (account, name, device_id, key, fingerprint, own, status) VALUES (:account,:name,:deviceId,:key,:fingerprint,:own,:status) ON CONFLICT(account, name, fingerprint) DO UPDATE SET device_id = :deviceId, status = :status");
    static let omemoKeyPairLoadStatus = Query("SELECT status FROM omemo_identities WHERE account = :account AND name = :name AND device_id = :deviceId");
    static let omemoKeyPairUpdateStatus = Query("UPDATE omemo_identities SET status = :status WHERE account = :account AND name = :name AND device_id = :deviceId");
    
    static let omemoIdentitiesWipe = Query("DELETE FROM omemo_identities WHERE account = :account");
    static let omemoIdentityFind = Query("SELECT device_id, fingerprint, status, key, own FROM omemo_identities WHERE account = :account AND name = :name");
    static let omemoIdentityFingerprintFind = Query("SELECT fingerprint FROM omemo_identities WHERE account = :account AND name = :name AND device_id = :deviceId");
    
    static let omemoPreKeyCurrent = Query("SELECT max(id) FROM omemo_pre_keys WHERE account = :account");
    static let omemoPreKeyLoad = Query("SELECT key FROM omemo_pre_keys WHERE account = :account AND id = :id");
    static let omemoPreKeyInsert = Query("INSERT INTO omemo_pre_keys (account, id, key) VALUES (:account,:id,:key)");
    static let omemoPreKeyDelete = Query("DELETE FROM omemo_pre_keys WHERE account = :account AND id = :id");
    static let omemoPreKeyWipe = Query("DELETE FROM omemo_pre_keys WHERE account = :account");
    
    static let omemoSignedPreKeyLoad = Query("SELECT key FROM omemo_signed_pre_keys WHERE account = :account AND id = :id");
    static let omemoSignedPreKeyInsert = Query("INSERT INTO omemo_signed_pre_keys (account, id, key) VALUES (:account,:id,:key)");
    static let omemoSignedPreKeyDelete = Query("DELETE FROM omemo_signed_pre_keys WHERE account = :account AND id = :id");
    static let omemoSignedPreKeyCount = Query("SELECT count(1) FROM omemo_signed_pre_keys WHERE account = :account");
    static let omemoSignedPreKeyWipe = Query("DELETE FROM omemo_signed_pre_keys WHERE account = :account");
    
    static let omemoSessionRecordLoad = Query("SELECT key FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId");
    static let omemoSessionRecordInsert = Query("INSERT INTO omemo_sessions (account, name, device_id, key) VALUES (:account, :name, :deviceId, :key)");
    static let omemoSessionRecordDelete = Query("DELETE FROM omemo_sessions WHERE account = :account AND name = :name AND device_id = :deviceId");
    static let omemoSessionRecordDeleteAll = Query("DELETE FROM omemo_sessions WHERE account = :account AND name = :name");
    static let omemoSessionRecordWipe = Query("DELETE FROM omemo_sessions WHERE account = :account");
    
    static let omemoDevicesFind = Query("SELECT device_id FROM omemo_sessions WHERE account = :account AND name = :name");
    static let omemoDevicesFindActiveAndTrusted = Query("SELECT s.device_id FROM omemo_sessions s LEFT JOIN omemo_identities i ON s.account = i.account AND s.name = i.name AND s.device_id = i.device_id WHERE s.account = :account AND s.name = :name AND ((i.status >= 0 AND i.status % 2 = 0) OR i.status IS NULL)");
}
    
class DBOMEMOStore {
    
    public static let instance = DBOMEMOStore();
        
    func keyPair(forAccount account: BareJID) -> SignalIdentityKeyPairProtocol? {
        guard let deviceId = localRegistrationId(forAccount: account) else {
            return nil;
        }
        
        guard let data = try! Database.main.reader({ database in
            return try database.select(query: .omemoKeyPairForAccount, params: ["account": account, "name": account.stringValue, "deviceId": deviceId]).mapFirst({ $0.data(for: "key") });
        }) else {
            return nil;
        }
        
        return SignalIdentityKeyPair(fromKeyPairData: data);
    }
    
    func identityFingerprint(forAccount account: BareJID, andAddress address: SignalAddress) -> String? {
        let params: [String: Any?] = ["account": account, "name": address.name, "deviceId": address.deviceId];
        return try! Database.main.reader({ database in
            return try database.select(query: .omemoIdentityFingerprintFind, params: params).mapFirst({ $0.string(for: "fingerprint")});
        })
    }
    
    func identities(forAccount account: BareJID, andName name: String) -> [Identity] {
        let params: [String: Any?] = ["account": account, "name": name];
        return try! Database.main.reader({ database in
            return try database.select(query: .omemoIdentityFind, params: params).mapAll({ cursor -> Identity? in
                guard let fingerprint: String = cursor["fingerprint"], let statusInt: Int = cursor["status"], let status = IdentityStatus(rawValue: statusInt), let deviceId: Int32 = cursor["device_id"], let own: Int = cursor["own"], let key: Data = cursor["key"] else {
                    return nil;
                }
                return Identity(address: SignalAddress(name: name, deviceId: deviceId), status: status, fingerprint: fingerprint, key: key, own: own > 0);
            })
        });
    }
    
    func localRegistrationId(forAccount account: BareJID) -> UInt32? {
        return AccountSettings.omemoRegistrationId(account).uint32();
    }
    
    func save(identity: SignalAddress, key: SignalIdentityKeyProtocol?, forAccount account: BareJID, own: Bool = false) -> Bool {
        guard let key = key else {
            // should we remove this key?
            return false;
        }
        guard let publicKeyData = key.publicKey else {
            return false;
        }
        
        let fingerprint: String = self.fingerprint(publicKey: publicKeyData);
                
        defer {
            _ = self.setStatus(.verifiedActive, forIdentity: identity, andAccount: account);
        }

        return save(identity: identity, fingerprint: fingerprint, own: own, data: key.serialized(), forAccount: account);
    }

    func fingerprint(publicKey: Data) -> String {
        return publicKey.map { (byte) -> String in
           return String(format: "%02x", byte)
        }.joined();
    }
    
    func save(identity: SignalAddress, publicKeyData: Data?, forAccount account: BareJID) -> Bool {
        guard let publicKeyData = publicKeyData else {
            // should we remove this key?
            return false;
        }
        
        let fingerprint: String = self.fingerprint(publicKey: publicKeyData);
        return save(identity: identity, fingerprint: fingerprint, own: false, data: publicKeyData, forAccount: account);
    }
        
    private func save(identity: SignalAddress, fingerprint: String, own: Bool, data: Data?, forAccount account: BareJID) -> Bool {
        return try! Database.main.writer({ database -> Bool in
            let paramsCount: [String: Any?] = ["account": account, "name": identity.name, "fingerprint": fingerprint];
            guard try database.count(query: .omemoKeyPairExists, params: paramsCount) == 0 else {
                return true;
            }
            
            var params: [String: Any?] = paramsCount;
            params["deviceId"] = identity.deviceId;
            params["key"] = data;
            params["own"] = own ? 1 : 0;
            params["status"] = IdentityStatus.trustedActive.rawValue;
            try database.insert(query: .omemoKeyPairInsert, params: params);
            return true;
        });
    }
    
    func setStatus(_ status: IdentityStatus, forIdentity identity: SignalAddress,  andAccount account: BareJID) -> Bool {
        return try! Database.main.writer({ database in
            try database.update(query: .omemoKeyPairUpdateStatus, params: ["account": account, "name": identity.name, "deviceId": identity.deviceId, "status": status.rawValue]);
            return database.changes;
        }) > 0;
    }

    func setStatus(active: Bool, forIdentity identity: SignalAddress,  andAccount account: BareJID) -> Bool {
        guard let status = try! Database.main.reader({ database in
            return try database.select(query: .omemoKeyPairLoadStatus, params: ["account": account, "name": identity.name, "deviceId": identity.deviceId]).mapFirst({ cursor in
                return IdentityStatus(rawValue: cursor.int(for: "status") ?? 0);
            });
        }) else {
            return false;
        }
        return setStatus(active ? status.toActive() : status.toInactive(), forIdentity: identity, andAccount: account);
    }
    
    func currentPreKeyId(forAccount account: BareJID) -> UInt32 {
        return UInt32(try! Database.main.reader({ database in
            return try database.select(query: .omemoPreKeyCurrent, params: ["account": account]).mapFirst({ $0.int(at: 0) })
        }) ?? 0);
    }
    
    func loadPreKey(forAccount account: BareJID, withId: UInt32) -> Data? {
        return try! Database.main.reader({ database in
            try database.select(query: .omemoPreKeyLoad, params: ["account": account, "id": withId]).mapFirst({ $0.data(for: "key") });
        });
    }
    
    func store(preKey: Data, forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! Database.main.writer({ database in
            try database.insert(query: .omemoPreKeyInsert, params: ["account": account, "id": withId, "key": preKey]);
            return database.changes != 0;
        })
    }

    func containsPreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return loadPreKey(forAccount: account, withId: withId) != nil;
    }

    func deletePreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! Database.main.writer({ database in
            try database.delete(query: .omemoPreKeyDelete, cached: false, params: ["account": account, "id": withId]);
            return database.changes != 0;
        })
    }
    
    func countSignedPreKeys(forAccount account: BareJID) -> Int {
        return try! Database.main.reader({ database in
            try database.count(query: .omemoSignedPreKeyCount, cached: false, params: ["account": account]);
        });
    }

    func loadSignedPreKey(forAccount account: BareJID, withId: UInt32) -> Data? {
        return try! Database.main.reader({ database in
            return try database.select(query: .omemoSignedPreKeyLoad, params: ["account": account, "id": withId]).mapFirst({ $0.data(for: "key") });
        })
    }
    
    func store(signedPreKey: Data, forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! Database.main.writer({ database in
            try database.insert(query: .omemoSignedPreKeyInsert, params: ["account": account, "id": withId, "key": signedPreKey]);
            return database.changes > 0;
        });
    }
    
    func containsSignedPreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return loadPreKey(forAccount: account, withId: withId) != nil;
    }
    
    func deleteSignedPreKey(forAccount account: BareJID, withId: UInt32) -> Bool {
        return try! Database.main.writer({ database in
            try database.delete(query: .omemoSignedPreKeyDelete, cached: false, params: ["account": account, "id": withId]);
            return database.changes > 0;
        })
    }
    
    func sessionRecord(forAccount account: BareJID, andAddress address: SignalAddress) -> Data? {
        return try! Database.main.reader({ database in
            return try database.select(query: .omemoSessionRecordLoad, params: ["account": account, "name": address.name, "deviceId": address.deviceId]).mapFirst({ $0.data(for: "key") });
        })
    }

    func allDevices(forAccount account: BareJID, andName name: String, activeAndTrusted: Bool) -> [Int32] {
        let params: [String: Any?] = ["account": account, "name": name];
        return try! Database.main.reader({ database in
            return try database.select(query: activeAndTrusted ? .omemoDevicesFindActiveAndTrusted : .omemoDevicesFind, params: params).mapAll({ $0["device_id"] });
        })
    }
    
    func store(sessionRecord: Data, forAccount account: BareJID, andAddress address: SignalAddress) -> Bool {
        return try! Database.main.writer({ database in
            try database.insert(query: .omemoSessionRecordInsert, params: ["account": account, "name": address.name, "deviceId": address.deviceId, "key": sessionRecord]);
            return database.changes > 0;
        })
    }
    
    func containsSessionRecord(forAccount account: BareJID, andAddress address: SignalAddress) -> Bool {
        return sessionRecord(forAccount: account, andAddress: address) != nil;
    }
    
    func deleteSessionRecord(forAccount account: BareJID, andAddress address: SignalAddress) -> Bool {
        return try! Database.main.writer({ database in
            try database.delete(query: .omemoSessionRecordDelete, params: ["account": account, "name": address.name, "deviceId": address.deviceId]);
            return database.changes > 0;
        })
    }
    
    func deleteAllSessions(forAccount account: BareJID, andName name: String) -> Bool {
        return try! Database.main.writer({ database in
            try database.delete(query: .omemoSessionRecordDeleteAll, params: ["account": account, "name": name]);
            return database.changes > 0;
        });
    }
    
    func wipe(forAccount account: BareJID) {
        try! Database.main.writer({ database in
            try database.delete(query: .omemoSessionRecordWipe, params:["account": account]);
            try database.delete(query: .omemoPreKeyWipe, params: ["account": account]);
            try database.delete(query: .omemoSignedPreKeyWipe, params: ["account": account]);
            try database.delete(query: .omemoIdentitiesWipe, cached: false, params: ["account": account]);
        })
    }
}

class SignalIdentityKeyStore: SignalIdentityKeyStoreProtocol, ContextAware {
    
    weak var context: Context?;
    
    func keyPair() -> SignalIdentityKeyPairProtocol? {
        return DBOMEMOStore.instance.keyPair(forAccount: context!.sessionObject.userBareJid!);
    }
    
    func localRegistrationId() -> UInt32 {
        return DBOMEMOStore.instance.localRegistrationId(forAccount: context!.sessionObject.userBareJid!) ?? 0;
    }
    
    func save(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        return DBOMEMOStore.instance.save(identity: identity, key: key, forAccount: context!.sessionObject.userBareJid!, own: true)
    }
    
    func save(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        return DBOMEMOStore.instance.save(identity: identity, publicKeyData: publicKeyData, forAccount: context!.sessionObject.userBareJid!);
    }
    
    func setStatus(_ status: IdentityStatus, forIdentity: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.setStatus(status, forIdentity: forIdentity, andAccount: context!.sessionObject.userBareJid!);
    }
    
    func setStatus(active: Bool, forIdentity: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.setStatus(active: active, forIdentity: forIdentity, andAccount: context!.sessionObject.userBareJid!);
    }

    func isTrusted(identity: SignalAddress, key: SignalIdentityKeyProtocol?) -> Bool {
        return true;
    }
    
    func isTrusted(identity: SignalAddress, publicKeyData: Data?) -> Bool {
        return true;
    }
    
    func identityFingerprint(forAddress address: SignalAddress) -> String? {
        return DBOMEMOStore.instance.identityFingerprint(forAccount: self.context!.sessionObject.userBareJid!, andAddress: address);
    }
    
    func identities(forName name: String) -> [Identity] {
        return DBOMEMOStore.instance.identities(forAccount: self.context!.sessionObject.userBareJid!, andName: name);
    }
    
}

class SignalPreKeyStore: SignalPreKeyStoreProtocol, ContextAware {
    
    //fileprivate(set) var currentPreKeyId: UInt32 = 0;
    
    weak var context: Context?
//    {
//        didSet {
//            self.currentPreKeyId = AccountSettings.omemoCurrentPreKeyId(context.sessionObject.userBareJid!).uint32() ?? 0;
//        }
//    }

    private let queue = DispatchQueue(label: "SignalPreKeyRemovalQueue");
    private var preKeysMarkedForRemoval: [UInt32] = [];
    
    func currentPreKeyId() -> UInt32 {
        return DBOMEMOStore.instance.currentPreKeyId(forAccount: context!.sessionObject.userBareJid!);
    }
    
    func loadPreKey(withId: UInt32) -> Data? {
        return DBOMEMOStore.instance.loadPreKey(forAccount: context!.sessionObject.userBareJid!, withId: withId);
    }
    
    func storePreKey(_ data: Data, withId: UInt32) -> Bool {
        guard DBOMEMOStore.instance.store(preKey: data, forAccount: context!.sessionObject.userBareJid!, withId: withId) else {
            return false;
        }
//        AccountSettings.omemoCurrentPreKeyId(context.sessionObject.userBareJid!).set(value: withId);
        return true;
    }
    
    func containsPreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.containsPreKey(forAccount: context!.sessionObject.userBareJid!, withId: withId);
    }
    
    func deletePreKey(withId: UInt32) -> Bool {
        queue.async {
            print("queueing prekey with id \(withId) for removal..");
            self.preKeysMarkedForRemoval.append(withId);
        }
        return true;
    }
    
    func flushDeletedPreKeys() -> Bool {
        return queue.sync(execute: { () -> [UInt32] in
            defer {
                preKeysMarkedForRemoval.removeAll();
            }
            print("removing queued prekeys: \(preKeysMarkedForRemoval)");
            return preKeysMarkedForRemoval.filter({ id in DBOMEMOStore.instance.deletePreKey(forAccount: context!.sessionObject.userBareJid!, withId: id) });
        }).count > 0;
    }
}

class SignalSignedPreKeyStore: SignalSignedPreKeyStoreProtocol, ContextAware {
    
    weak var context: Context?;
    
    func countSignedPreKeys() -> Int {
        return DBOMEMOStore.instance.countSignedPreKeys(forAccount: context!.sessionObject.userBareJid!);
    }
    
    func loadSignedPreKey(withId: UInt32) -> Data? {
        return DBOMEMOStore.instance.loadSignedPreKey(forAccount: context!.sessionObject.userBareJid!, withId: withId);
    }
    
    func storeSignedPreKey(_ data: Data, withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.store(signedPreKey: data, forAccount: context!.sessionObject.userBareJid!, withId: withId);
    }
    
    func containsSignedPreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.containsSignedPreKey(forAccount: context!.sessionObject.userBareJid!, withId: withId);
    }
    
    func deleteSignedPreKey(withId: UInt32) -> Bool {
        return DBOMEMOStore.instance.deleteSignedPreKey(forAccount: context!.sessionObject.userBareJid!, withId: withId);
    }
}

class SignalSessionStore: SignalSessionStoreProtocol, ContextAware {
    
    weak var context: Context?;
    
    func sessionRecord(forAddress address: SignalAddress) -> Data? {
        return DBOMEMOStore.instance.sessionRecord(forAccount: context!.sessionObject.userBareJid!, andAddress: address);
    }
    
    func allDevices(for name: String, activeAndTrusted: Bool) -> [Int32] {
        return DBOMEMOStore.instance.allDevices(forAccount: context!.sessionObject.userBareJid!, andName: name, activeAndTrusted: activeAndTrusted);
    }
    
    func storeSessionRecord(_ data: Data, forAddress address: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.store(sessionRecord: data, forAccount: context!.sessionObject.userBareJid!, andAddress: address);
    }
    
    func containsSessionRecord(forAddress: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.containsSessionRecord(forAccount: context!.sessionObject.userBareJid!, andAddress: forAddress);
    }
    
    func deleteSessionRecord(forAddress: SignalAddress) -> Bool {
        return DBOMEMOStore.instance.deleteSessionRecord(forAccount: context!.sessionObject.userBareJid!, andAddress: forAddress);
    }
    
    func deleteAllSessions(for name: String) -> Bool {
        return DBOMEMOStore.instance.deleteAllSessions(forAccount: context!.sessionObject.userBareJid!, andName: name);
    }
}

class OMEMOStoreWrapper: SignalStorage {
    
    fileprivate weak var context: Context!;
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

            let keyPair = SignalIdentityKeyPair.generateKeyPair(context: signalContext);
            if !identityKeyStore.save(identity: SignalAddress(name: context!.sessionObject.userBareJid!.stringValue, deviceId: Int32(identityKeyStore.localRegistrationId())), key: keyPair) {
            }
        }
        return true;
    }
}

class SignalSenderKeyStore: SignalSenderKeyStoreProtocol {
    
    func storeSenderKey(_ key: Data, address: SignalAddress?, groupId: String?) -> Bool {
        return false;
    }
    
    func loadSenderKey(forAddress address: SignalAddress?, groupId: String?) -> Data? {
        return nil;
    }
    
    
    
}
