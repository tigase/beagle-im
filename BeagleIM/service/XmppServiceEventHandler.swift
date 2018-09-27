//
//  XmppServiceEventHandler.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 27/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

protocol XmppServiceEventHandler: EventHandler {
    
    var events: [Event] { get }
    
}
