//
//  ChatItemProtocol.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 20.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

protocol ChatItemProtocol {
    
    var chat: DBChatProtocol { get };
    
    var name: String { get };
    var lastMessageText: String? { get }
    var lastMessageTs: Date { get }
    var unread: Int { get }
    
}
