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
    case showRoomDetailsSidebar
    case defaultAccount
    
    case enableMessageCarbons
    case markMessageCarbonsAsRead
    
    public static let CHANGED = Notification.Name("settingChanged");
    
    fileprivate static var observers: [Settings: [UUID: (Settings, Any?)->Void]] = [:];
    
    func set(value: Bool) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
        valueChanged();
    }
    
    func bool() -> Bool {
        return UserDefaults.standard.bool(forKey: self.rawValue);
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

protocol CustomDictionaryConvertible {
    
    init(from: [String: Any?]);
    
    func toDict() -> [String: Any?];
    
}
