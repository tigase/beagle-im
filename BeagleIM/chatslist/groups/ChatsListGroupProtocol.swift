//
//  ChatListGroupProtocol.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 20.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

protocol ChatsListGroupProtocol {
    
    var name: String { get }
    
    var count: Int { get }
    
    var canOpenChat: Bool { get }
    
    func getChat(at: Int) -> ChatItemProtocol?;
    
    func forChat(_ chat: DBChatProtocol, execute: @escaping (ChatItemProtocol)->Void);
    
    func forChat(account: BareJID, jid: BareJID, execute: @escaping (ChatItemProtocol)->Void);
}
