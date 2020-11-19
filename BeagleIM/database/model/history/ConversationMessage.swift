//
// ConversationMessage.swift
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

class ConversationMessage: ConversationEntryWithSender {

    let message: String;
    let correctionTimestamp: Date?;
    
    var isCorrected: Bool {
        return correctionTimestamp != nil;
    }
    
    init(id: Int, conversation: ConversationKey, timestamp: Date, state: ConversationEntryState, sender: ConversationSenderProtocol, encryption: ConversationEntryEncryption, message: String, correctionTimestamp: Date?) {
        self.message = message;
        self.correctionTimestamp = correctionTimestamp;
        super.init(id: id, conversation: conversation, timestamp: timestamp, state: state, sender: sender, encryption: encryption);
    }

    override func isMergeable() -> Bool {
        return !message.starts(with: "/me ");
    }
}

//public struct ChatMessageAppendix: Codable {
//
//    var previews: [Preview];
//
//    public init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self);
//        if let previews: [Preview] = try container.decodeIfPresent([Preview].self, forKey: .previews) {
//            self.previews = previews;
//        } else {
//            self.previews = [];
//        }
//    }
//
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self);
//        if !previews.isEmpty {
//            try container.encode(previews, forKey: .previews);
//        }
//    }
//
//    public struct Preview: Codable {
//
//        let url: URL;
//        let state: State;
//        let metadataId: String?;
//
//        public init(from decoder: Decoder) throws {
//            let container = try decoder.container(keyedBy: CodingKeys.self);
//            url = URL(string: try container.decode(String.self, forKey: .url))!;
//            state = State(rawValue: try container.decode(Int.self, forKey: .state))!;
//            metadataId = try container.decodeIfPresent(String.self, forKey: .metadataId);
//        }
//
//        public func encode(to encoder: Encoder) throws {
//            var container = encoder.container(keyedBy: CodingKeys.self);
//            try container.encode(url.absoluteString, forKey: .url);
//            try container.encode(state.rawValue, forKey: .state);
//            if let metadataId = self.metadataId {
//                try container.encode(metadataId, forKey: .metadataId);
//            }
//        }
//
//        enum CodingKeys: String, CodingKey {
//            case url = "url";
//            case state = "state"
//            case metadataId = "metadataId"
//        }
//
//        enum State: Int {
//            case new
//            case generated
//            case error
//        }
//    }
//
//    enum CodingKeys: String, CodingKey {
//        case previews = "previews"
//    }
//
//}

