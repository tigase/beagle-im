//
// ChatMarkerCellView.swift
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
import AppKit
import Combine

class ChatMarkerCellView: NSTableCellView {

    @IBOutlet var label: NSTextField!;
    @IBOutlet var avatars: NSStackView!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    func set(item: ConversationEntry, type: ChatMarker.MarkerType, senders: [ConversationEntrySender]) {
        cancellables.removeAll();
        
        let avatars = (0..<min(4, senders.count)).map({ idx -> AvatarView in
            let view = AvatarView(frame: .init(x: 0, y: 0, width: 14, height: 14));
            NSLayoutConstraint.activate([view.heightAnchor.constraint(equalToConstant: 14), view.widthAnchor.constraint(equalToConstant: 14)]);
            view.imageScaling = .scaleProportionallyDown;
            if let avatarPublisher = senders[idx].avatar(for: item.conversation)?.avatarPublisher {
                let name = senders[idx].nickname;
                avatarPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { avatar in
                    view.set(name: name, avatar: avatar);
                }).store(in: &cancellables);
            } else {
                view.set(name: senders[idx].nickname, avatar: nil);
            }
            return view;
        });
        
        self.avatars.setViews(avatars, in: .leading);
        
        let prefix = senders.count > 3 ? "+\(senders.count - 3) " : "";
        
        switch type {
        case .displayed:
            self.label?.stringValue = prefix + " " + NSLocalizedString("Displayed", comment: "displayed in the chat log");
        case .received:
            self.label?.stringValue = prefix + " " + NSLocalizedString("Received", comment: "displayed in the chat log");
        }
        
        self.toolTip = prepareTooltip(type: type, senders: senders);
    }
    
    func prepareTooltip(type: ChatMarker.MarkerType, senders: [ConversationEntrySender]) -> String {
        return type.localizedLabel(by: senders.compactMap({ $0.nickname }).joined(separator: " "));
    }
    
}

extension ChatMarker.MarkerType {
        
    func localizedLabel(by senders: String) -> String {
        switch self {
        case .displayed:
            return String.localizedStringWithFormat(NSLocalizedString("Displayed by %@", comment: "displayed in the tooltip"), senders);
        case .received:
            return String.localizedStringWithFormat(NSLocalizedString("Received by %@", comment: "displayed in the tooltip"), senders);
        }
    }
}
