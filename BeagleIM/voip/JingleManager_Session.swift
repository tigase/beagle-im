//
// JingleManager_Session.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
import WebRTC
import os
import Combine

protocol JingleSessionActionDelegate: AnyObject {
    
    func received(action: JingleManager.Session.Action);
    
}

extension JingleManager {
    
    public class Session: JingleSession {
                        
        private static let queue = DispatchQueue(label: "JingleSessionQueue");

        private weak var delegate: JingleSessionActionDelegate?;
        private var actionsQueue: [Action] = [];
        
        public enum Action {
            case contentSet(SDP)
            case contentApply(Jingle.ContentAction, SDP)
            case transportAdd(Jingle.Transport.ICEUDPTransport.Candidate, String);
            case sessionInfo([Jingle.SessionInfo])
            
            var order: Int {
                switch self {
                case .contentSet(_):
                    return 0;
                case .contentApply(_,_):
                    return 0;
                case .transportAdd(_, _):
                    return 1;
                case .sessionInfo(_):
                    return 2;
                }
            }
        }
        
        override init(context: Context, jid: JID, sid: String, role: Jingle.Content.Creator, initiationType: JingleSessionInitiationType) {
            super.init(context: context, jid: jid, sid: sid, role: role, initiationType: initiationType);
        }
                
        override func initiated(contents: [Jingle.Content], bundle: Jingle.Bundle?) {
            super.initiated(contents: contents, bundle: bundle)
            received(action: .contentSet(SDP(contents: contents, bundle: bundle)));
        }
        
        
        private func received(action: Action) {
            Session.queue.async {
                if self.delegate == nil {
                    if let idx = self.actionsQueue.firstIndex(where: { $0.order > action.order }) {
                        self.actionsQueue.insert(action, at: idx);
                    } else {
                        self.actionsQueue.append(action);
                    }
                } else {
                    self.delegate?.received(action: action);
                }
            }
        }
        
        public func setDelegate(_ delegate: JingleSessionActionDelegate) {
            Session.queue.async {
                self.delegate = delegate;
                for action in self.actionsQueue {
                    self.delegate?.received(action: action);
                }
                self.actionsQueue.removeAll();
            }
        }
        
        override func accepted(contents: [Jingle.Content], bundle: Jingle.Bundle?) {
            super.accepted(contents: contents, bundle: bundle)
            received(action: .contentSet(SDP(contents: contents, bundle: bundle)));
        }
        
        func decline() async throws {
            try await self.terminate(reason: .decline);
        }
        

        open override func contentModified(action: Jingle.ContentAction, contents: [Jingle.Content], bundle: Jingle.Bundle?) {
            let sdp = SDP(contents: contents, bundle: bundle);
            received(action: .contentApply(action, sdp));
        }
        
        func addCandidate(_ candidate: Jingle.Transport.ICEUDPTransport.Candidate, for contentName: String) {
            received(action: .transportAdd(candidate, contentName));
        }
        
        open override func sessionInfoReceived(info: [Jingle.SessionInfo]) {
            received(action: .sessionInfo(info));
        }
    }
    
}

extension JingleSessionState {
    var rawValue: String {
        switch self {
        case .accepted:
            return "accepted";
        case .created:
            return "created";
        case .initiating:
            return "initiating";
        case .terminated:
            return "terminated";
        }
    }
}
