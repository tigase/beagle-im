//
//  XMPPClient_extension.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 27/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

extension XMPPClient {
    
    fileprivate static let RETRY_NO_KEY = "retryNo";
    
    var retryNo: Int {
        get {
            return sessionObject.getProperty(XMPPClient.RETRY_NO_KEY) ?? 0;
        }
        set {
            sessionObject.setUserProperty(XMPPClient.RETRY_NO_KEY, value: newValue);
        }
    }
    
    var presenceStore: PresenceStore? {
        get {
            guard let presenceModule: PresenceModule = modulesManager.getModule(PresenceModule.ID) else {
                return nil;
            }
            return presenceModule.presenceStore;
        }
    }
    
    var rosterStore: RosterStore? {
        get {
            guard let rosterModule: RosterModule = modulesManager.getModule(RosterModule.ID) else {
                return nil;
            }
            return rosterModule.rosterStore;
        }
    }
}
