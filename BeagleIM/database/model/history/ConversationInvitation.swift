//
// ConversationInvitation.swift
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
import Martin

public struct ChatInvitationAppendix: AppendixProtocol, Hashable {
    
    let type: InvitationType;
    let inviter: BareJID;
    let invitee: BareJID;
    let channel: BareJID;
    let token: String?;
    
    public init(mixInvitation: MixInvitation) {
        type = .mix;
        inviter = mixInvitation.inviter;
        invitee = mixInvitation.invitee;
        channel = mixInvitation.channel;
        token = mixInvitation.token;
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        type = InvitationType(rawValue: try container.decode(Int.self, forKey: .type))!;
        inviter = try container.decode(BareJID.self, forKey: .inveter);
        invitee = try container.decode(BareJID.self, forKey: .invetee);
        channel = try container.decode(BareJID.self, forKey: .channel);
        token = try container.decodeIfPresent(String.self, forKey: .token);
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(type.rawValue, forKey: .type);
        try container.encode(inviter, forKey: .inveter);
        try container.encode(invitee, forKey: .invetee);
        try container.encode(channel, forKey: .channel);
        try container.encodeIfPresent(token, forKey: .token);
    }
        
    public func mixInvitation() -> MixInvitation? {
        guard type == .mix else {
            return nil;
        }
        return MixInvitation(inviter: inviter, invitee: invitee, channel: channel, token: token);
    }
    
    enum CodingKeys: String, CodingKey {
        case type = "type"
        case invetee = "invitee";
        case inveter = "inviter";
        case channel = "channel";
        case token = "token";
   }

    enum InvitationType: Int {
        case mix = 1
    }
}
