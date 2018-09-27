//
//  ChatViewItemProtocol.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 21.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Foundation
import TigaseSwift

protocol ChatViewItemProtocol: class {
    var id: Int { get };
    var account: BareJID { get }
    var jid: BareJID { get }
    var timestamp: Date { get };
    var state: MessageState { get };
}
