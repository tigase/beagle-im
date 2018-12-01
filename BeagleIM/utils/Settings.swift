//
//  Settings.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 15.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
    case imageDownloadSizeLimit
    
    case enableMarkdownFormatting
    case notificationsFromUnknownSenders
    case systemMenuIcon
    case spellchecking
    
    case appearance
    
    public static let CHANGED = Notification.Name("settingChanged");
    
    fileprivate static var observers: [Settings: [UUID: (Settings, Any?)->Void]] = [:];
    
    public static func initialize() {
        let defaults: [String: Any] = [
            "automaticallyConnectAfterStart": true,
            "requestPresenceSubscription": true,
            "allowPresenceSubscription": true,
            "enableMessageCarbons": true,
            "enableAutomaticStatus": true,
            "markMessageCarbonsAsRead": true,
            "enableMarkdownFormatting": true,
            "notificationsFromUnknownSenders": false,
            "systemMenuIcon": false,
            "spellchecking": true,
            "appearance": Appearance.auto.rawValue,
            "imageDownloadSizeLimit": (10*1024*1024)
        ];
        UserDefaults.standard.register(defaults: defaults);
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
    }
    
    func set(value: String?) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
        valueChanged();
    }
    
    func string() -> String? {
        return UserDefaults.standard.string(forKey: self.rawValue);
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
        }
    }
    
    public var name: String {
        switch self {
        case .messageSyncAuto(_):
            return "messageSyncAuto";
        case .messageSyncPeriod(_):
            return "messageSyncPeriod";
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
    
    fileprivate func valueChanged() {
        NotificationCenter.default.post(name: AccountSettings.CHANGED, object: self);
    }
}

protocol CustomDictionaryConvertible {
    
    init(from: [String: Any?]);
    
    func toDict() -> [String: Any?];
    
}
