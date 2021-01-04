//
// Settings.swift
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

import AppKit
import TigaseSwift
import Combine

enum MessageGrouping: String {
    case none
    case smart
    case always
}

@propertyWrapper class UserDefaultsSetting<Value> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value,Never>;
        
    var projectedValue: AnyPublisher<Value,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value = storage.value(forKey: key) as? Value ?? defaultValue;
        self.value = CurrentValueSubject<Value,Never>(value);
    }
}

@propertyWrapper class UserDefaultsRawSetting<Value: RawRepresentable> {
    let key: String;
    var storage: UserDefaults = .standard;
    
    var value: CurrentValueSubject<Value,Never>;
        
    var projectedValue: AnyPublisher<Value,Never> {
        get {
            return value.eraseToAnyPublisher();
        }
        set {
            // nothing to do..
        }
    }
    
    var wrappedValue: Value {
        get {
            return value.value;
        }
        set {
            storage.setValue(newValue, forKey: key);
            self.value.value = newValue;
        }
    }
    
    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key;
        self.storage = storage;
        let value: Value = storage.value(forKey: key) ?? defaultValue;
        self.value = CurrentValueSubject<Value,Never>(value);
    }
}

extension UserDefaultsSetting where Value: ExpressibleByNilLiteral {
    convenience init(key: String, storage: UserDefaults = .standard) {
        self.init(key: key, defaultValue: nil, storage: storage);
    }
}

extension UserDefaults {

    func value<T: RawRepresentable>(forKey key: String) -> T? {
        guard let value = value(forKey: key) as? T.RawValue else {
            return nil;
        }
        return T(rawValue: value);
    }
    
    func setValue<T: RawRepresentable>(_ value: T?, forKey key: String) {
        print("called setting raw representable!");
        set(value?.rawValue, forKey: key);
    }
}

class SettingsStore {
    @UserDefaultsSetting(key: "showRoomDetailsSidebar", defaultValue: true)
    var showRoomDetailsSidebar: Bool;
    @UserDefaultsSetting(key: "defaultAccount")
    var defaultAccount: String?
    @UserDefaultsSetting(key: "enableBookmarksSync", defaultValue: false)
    var enableBookmarksSync: Bool;
    @UserDefaultsSetting(key: "fileDownloadSizeLimit", defaultValue: Int(10*1024*1024))
    var fileDownloadSizeLimit: Int;
    @UserDefaultsSetting(key: "enableMarkdownFormatting", defaultValue: true)
    var enableMarkdownFormatting: Bool;
    @UserDefaultsSetting(key: "showEmoticons", defaultValue: true)
    var showEmoticons: Bool;
    @UserDefaultsRawSetting(key: "messageEncryption", defaultValue: ConversationEncryption.none)
    var messageEncryption: ConversationEncryption
    @UserDefaultsSetting(key: "notificationsFromUnknownSenders", defaultValue: false)
    var notificationsFromUnknownSenders: Bool;
    @UserDefaultsSetting(key: "systemMenuIcon", defaultValue: false)
    var systemMenuIcon: Bool;
    @UserDefaultsSetting(key: "spellchecking", defaultValue: true)
    var spellchecking: Bool
    @UserDefaultsRawSetting(key: "appearance", defaultValue: .auto)
    var appearance: Appearance
    @UserDefaultsSetting(key: "ignoreJingleSupportCheck", defaultValue: false)
    var ignoreJingleSupportCheck: Bool
    @UserDefaultsSetting(key: "usePublicStunServers", defaultValue: true)
    var usePublicStunServers: Bool
    @UserDefaultsSetting(key: "alternateMessageColoringBasedOnDirection", defaultValue: false)
    var alternateMessageColoringBasedOnDirection: Bool
    @UserDefaultsRawSetting(key: "messageGrouping", defaultValue: .smart)
    var messageGrouping: MessageGrouping
    @UserDefaultsSetting(key: "linkPreviews", defaultValue: true)
    var linkPreviews: Bool;
    @UserDefaultsSetting(key: "boldKeywords", defaultValue: false)
    var boldKeywords: Bool;
    @UserDefaultsSetting(key: "markKeywords", defaultValue: [])
    var markKeywords: [String]
    @UserDefaultsSetting(key: "commonChatsList", defaultValue: true)
    var commonChatsList: Bool
    @UserDefaultsSetting(key: "showAdvancedXmppFeatures", defaultValue: false)
    var showAdvancedXmppFeatures: Bool
    @UserDefaultsRawSetting(key: "imageQuality", defaultValue: .medium)
    var imageQuality: ImageQuality
    @UserDefaultsRawSetting(key: "videoQuality", defaultValue: .medium)
    var videoQuality: VideoQuality
    
    @UserDefaultsRawSetting(key: "chatslistStyle", defaultValue: .small)
    var chatslistStyle: ChatsListStyle;
    
    var automaticallyConnectAfterStart: Bool {
        return true;
    }
    var enableAutomaticStatus: Bool {
        return false;
    }
    var rememberLastStatus: Bool {
        return false;
    }
    
    public static func initialize() {
        if UserDefaults.standard.object(forKey: "imageDownloadSizeLimit") != nil {
            let downloadLimit = UserDefaults.standard.integer(forKey: "imageDownloadSizeLimit");
            UserDefaults.standard.removeObject(forKey: "imageDownloadSizeLimit");
            UserDefaults.standard.set(downloadLimit, forKey: "fileDownloadSizeLimit");
        }
        UserDefaults.standard.removeObject(forKey: "turnServer");
        UserDefaults.standard.removeObject(forKey: "automaticallyConnectAfterStart");
        UserDefaults.standard.removeObject(forKey: "requestPresenceSubscription");
        UserDefaults.standard.removeObject(forKey: "allowPresenceSubscription");
        UserDefaults.standard.removeObject(forKey: "enableAutomaticStatus");
        UserDefaults.standard.removeObject(forKey: "currentStatus");
        UserDefaults.standard.removeObject(forKey: "rememberLastStatus");
        UserDefaults.standard.removeObject(forKey: "markMessageCarbonsAsRead");
    }
}

let Settings: SettingsStore = {
    SettingsStore.initialize();
    return SettingsStore()
}();

enum Appearance: String {
    case auto
    case light
    case dark
}

enum AccountSettings {
    case messageSyncAuto(BareJID)
    case messageSyncPeriod(BareJID)
    case omemoRegistrationId(BareJID)
//    case omemoCurrentPreKeyId(BareJID)
    
    public static let CHANGED = Notification.Name("accountSettingChanged");
    
    public static func initialize() {
        let accountJids = AccountManager.getAccounts().map { (jid) -> String in
            return jid.stringValue
        };
        let toRemove = UserDefaults.standard.dictionaryRepresentation().keys.filter { key -> Bool in
            return key.hasPrefix("accounts.") && accountJids.first(where: { jid -> Bool in
                return key.hasPrefix("accounts.\(jid).");
            }) == nil;
        }
        toRemove.forEach { key in
            UserDefaults.standard.removeObject(forKey: key);
        }
    }
    
    public var account: BareJID {
        switch self {
        case .messageSyncAuto(let account):
            return account;
        case .messageSyncPeriod(let account):
            return account;
        case .omemoRegistrationId(let account):
            return account;
//        case .omemoCurrentPreKeyId(let account):
//            return account;
        }
    }
    
    public var name: String {
        switch self {
        case .messageSyncAuto(_):
            return "messageSyncAuto";
        case .messageSyncPeriod(_):
            return "messageSyncPeriod";
        case .omemoRegistrationId(_):
            return "omemoRegistrationId";
//        case .omemoCurrentPreKeyId(_):
//            return "omemoCurrentPreKeyId";
        }
    }
    
    public var key: String {
        return "accounts.\(account).\(name)";
    }
    
    func bool() -> Bool {
        return UserDefaults.standard.bool(forKey: key);
    }
    
    func set(value: Bool) {
        UserDefaults.standard.set(value, forKey: key);
        valueChanged();
    }
    
    func object() -> Any? {
        return UserDefaults.standard.object(forKey: key);
    }
    
    func double() -> Double {
        return UserDefaults.standard.double(forKey: key);
    }
    
    func uint32() -> UInt32? {
        guard let tmp = UserDefaults.standard.string(forKey: key) else {
            return nil;
        }
        return UInt32(tmp);
    }
        
    func set(value: Double) {
        UserDefaults.standard.set(value, forKey: key);
        valueChanged();
    }
    
    func date() -> Date? {
        let value = UserDefaults.standard.double(forKey: key);
        return value == 0 ? nil : Date(timeIntervalSince1970: value);
    }
    
    func set(value: Date) {
        UserDefaults.standard.set(value.timeIntervalSince1970, forKey: key);
        valueChanged();
    }
    
    func set(value: UInt32?) {
        if value != nil {
            UserDefaults.standard.set(String(value!), forKey: key)
        } else {
            UserDefaults.standard.set(nil, forKey: key);
        }
    }
    
    fileprivate func valueChanged() {
        NotificationCenter.default.post(name: AccountSettings.CHANGED, object: self);
    }
}

protocol CustomDictionaryConvertible {
    
    init(from: [String: Any?]);
    
    func toDict() -> [String: Any?];
    
}
