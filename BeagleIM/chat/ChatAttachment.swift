//
// ChatAttachment.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class ChatAttachment: ChatEntry {
    
    let url: String;
    var appendix: ChatAttachmentAppendix;
    
    init(id: Int, timestamp: Date, account: BareJID, jid: BareJID, state: MessageState, url: String, authorNickname: String?, authorJid: BareJID?, encryption: MessageEncryption, encryptionFingerprint: String?, appendix: ChatAttachmentAppendix, error: String?) {
        self.url = url;
        self.appendix = appendix;
        super.init(id: id, timestamp: timestamp, account: account, jid: jid, state: state, authorNickname: authorNickname, authorJid: authorJid, encryption: encryption, encryptionFingerprint: encryptionFingerprint, error: error);
    }
    
}

public struct ChatAttachmentAppendix: Codable {
    
//    var localId: String?; // how about using message/entry id for that...
//    var metadataId: String?; // this can be the same as message/entry id...
    var state: State = .new; // do we need a state? most likely yes, to know if we should try to download now or not..
//    var filesize: Int? = nil;
//    var mimetype: String? = nil;
//    var filename: String? = nil;
    
    init() {}
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self);
        state = State(rawValue: try container.decode(Int.self, forKey: .state))!;
//        localId = try container.decodeIfPresent(String.self, forKey: .localId);
//        metadataId = try container.decodeIfPresent(String.self, forKey: .metadataId);
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self);
        try container.encode(state.rawValue, forKey: .state);
//        if let localId = self.localId {
//            try container.encode(localId, forKey: .localId);
//        }
//        if let metadataId = self.metadataId {
//            try container.encode(metadataId, forKey: .metadataId);
//        }
    }
    
    enum CodingKeys: String, CodingKey {
        case state = "state"
//        case localId = "localId"
//        case metadataId = "metadataId"
    }
    
    enum State: Int {
        case new
        case downloaded
        case tooBig
        case error
        case gone
    }
}
