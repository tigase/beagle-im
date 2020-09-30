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

enum Settings: String {
    case requestPresenceSubscription
    case allowPresenceSubscription
    case currentStatus
    case automaticallyConnectAfterStart
    case rememberLastStatus
    case enableAutomaticStatus
    case showRoomDetailsSidebar
    case defaultAccount
    
    case enableMessageCarbons
    case markMessageCarbonsAsRead
    case markMessageDeliveredToOtherResourceAsRead
    case enableBookmarksSync
    case fileDownloadSizeLimit
    
    case enableMarkdownFormatting
    case showEmoticons
    case messageEncryption
    case notificationsFromUnknownSenders
    case systemMenuIcon
    case spellchecking
    
    case appearance
    
    case ignoreJingleSupportCheck
    case usePublicStunServers
    
    // new and highly experimental
    case alternateMessageColoringBasedOnDirection
    case messageGrouping
    
    case boldKeywords
    case markKeywords
    
    @available(macOS 10.15, *)
    case linkPreviews

    case commonChatsList
    
    public static let CHANGED = Notification.Name("settingChanged");
    
    fileprivate static var observers: [Settings: [UUID: (Settings, Any?)->Void]] = [:];
    
    public static func initialize() {
        let defaults: [String: Any] = [
            "automaticallyConnectAfterStart": true,
            "requestPresenceSubscription": true,
            "allowPresenceSubscription": true,
            "enableMessageCarbons": true,
            "enableAutomaticStatus": true,
            "messageEncryption": "none",
            "markMessageCarbonsAsRead": true,
            "enableMarkdownFormatting": true,
            "showEmoticons": true,
            "notificationsFromUnknownSenders": false,
            "systemMenuIcon": false,
            "spellchecking": true,
            "appearance": Appearance.auto.rawValue,
            "fileDownloadSizeLimit": Int(10*1024*1024),
            "messageGrouping": "smart",
            "linkPreviews": true,
            "usePublicStunServers": true
        ];
        UserDefaults.standard.register(defaults: defaults);
        if UserDefaults.standard.object(forKey: "imageDownloadSizeLimit") != nil {
            let downloadLimit = UserDefaults.standard.integer(forKey: "imageDownloadSizeLimit");
            UserDefaults.standard.removeObject(forKey: "imageDownloadSizeLimit");
            Settings.fileDownloadSizeLimit.set(value: downloadLimit);
        }
        UserDefaults.standard.removeObject(forKey: "turnServer");
    }
    
    func set(value: Bool) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
        valueChanged();
    }
    
    func bool() -> Bool {
        return UserDefaults.standard.bool(forKey: self.rawValue);
    }
    
    func integer() -> Int {
        return UserDefaults.standard.integer(forKey: self.rawValue);
    }
    
    func set(value: Int) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
        valueChanged();
    }
    
    func set(value: String?) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
        valueChanged();
    }
    
    func set(values: [String]?) {
        UserDefaults.standard.set(values, forKey: self.rawValue);
        valueChanged();
    }
    
    func string() -> String? {
        return UserDefaults.standard.string(forKey: self.rawValue);
    }
    
    func stringArrays() -> [String]? {
        return UserDefaults.standard.stringArray(forKey: self.rawValue);
    }
    
    func bareJid() -> BareJID? {
        guard let str = string() else {
            return nil;
        }
        return BareJID(str);
    }
    
    func set(bareJid: BareJID?) {
        UserDefaults.standard.set(bareJid?.stringValue, forKey: self.rawValue);
        valueChanged();
    }
    
    func set(value: CustomDictionaryConvertible) {
        let dict = value.toDict();
        UserDefaults.standard.set(dict, forKey: self.rawValue);
        valueChanged();
    }
    
    func object<T: CustomDictionaryConvertible>() -> T? {
        guard let dict = UserDefaults.standard.dictionary(forKey: self.rawValue) else {
            return nil;
        }
        return T(from: dict);
    }
    
    fileprivate func valueChanged() {
        NotificationCenter.default.post(name: Settings.CHANGED, object: self);
    }
}

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
