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
    
    func set(value: Bool) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
    }
    
    func bool() -> Bool {
        return UserDefaults.standard.bool(forKey: self.rawValue);
    }
    
    func set(value: String?) {
        UserDefaults.standard.set(value, forKey: self.rawValue);
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
    }
    
    func set(value: CustomDictionaryConvertible) {
        let dict = value.toDict();
        UserDefaults.standard.set(dict, forKey: self.rawValue);
    }
    
    func object<T: CustomDictionaryConvertible>() -> T? {
        guard let dict = UserDefaults.standard.dictionary(forKey: self.rawValue) else {
            return nil;
        }
        return T(from: dict);
    }
}

protocol CustomDictionaryConvertible {
    
    init(from: [String: Any?]);
    
    func toDict() -> [String: Any?];
    
}
