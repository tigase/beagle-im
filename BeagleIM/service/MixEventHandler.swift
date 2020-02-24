//
// MixEventHandler.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import TigaseSwift

class MixEventHandler: XmppServiceEventHandler {
    
    static let instance = MixEventHandler();
    
    let events: [Event] = [MixModule.MessageReceivedEvent.TYPE];
    
    func handle(event: Event) {
        switch event {
        case let e as MixModule.MessageReceivedEvent:
            // only mix message (with `mix` element) are processed here...
            guard let mix = e.message.mix, let from = e.message.from, let account = e.sessionObject.userBareJid else {
                return;
            }
            
            DBChatHistoryStore.instance.append(for: account, message: e.message, source: .stream);            
        default:
            break;
        }
    }

}
