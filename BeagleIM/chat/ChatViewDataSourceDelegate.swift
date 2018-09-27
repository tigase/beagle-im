//
//  ChatViewDataSourceDelegate.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 21.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

protocol ChatViewDataSourceDelegate: class {
    
    var account: BareJID! { get }
    var jid: BareJID! { get }
    
    var hasFocus: Bool { get }
    
    func itemAdded(at: IndexSet);
    
    func itemUpdated(indexPath: IndexPath);
    
    func itemsReloaded();
}
