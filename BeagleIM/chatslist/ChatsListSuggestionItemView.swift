//
// ChatsListSuggestionItemView.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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

import AppKit
import Combine

class ChatsListSuggestionItemView: SuggestionItemView<DisplayableIdWithKeyProtocol> {
    
    let avatar: AvatarView;
    let label: NSTextField;
    let stack: NSStackView;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override var item: DisplayableIdWithKeyProtocol? {
        didSet {
            cancellables.removeAll();
            item?.avatarPublisher.assign(to: \.avatar, on: self.avatar).store(in: &cancellables);
            item?.displayNamePublisher.assign(to: \.stringValue, on: self.label).store(in: &cancellables);
            item?.displayNamePublisher.map({ $0 as String? }).assign(to: \.name, on: self.avatar).store(in: &cancellables);
        }
    }
    
    override var itemHeight: Int {
        return 44;
    }
    
    required init() {
        avatar = AvatarView(frame: NSRect(origin: .zero, size: NSSize(width: 40, height: 40)));
        avatar.appearance = NSAppearance(named: .darkAqua);

        label = NSTextField(labelWithString: "");
        label.appearance = NSAppearance(named: .darkAqua);
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium);
        label.cell?.truncatesLastVisibleLine = true;
        label.cell?.lineBreakMode = .byTruncatingTail;
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack = NSStackView(views: [avatar, label]);
        stack.translatesAutoresizingMaskIntoConstraints = false;
        stack.spacing = 6;
        stack.alignment = .centerY;
        stack.orientation = .horizontal;
        stack.distribution = .fill;
//            stack.setHuggingPriority(.defaultHigh, for: .vertical);
        stack.setHuggingPriority(.defaultHigh, for: .horizontal);
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack.visibilityPriority(for: label);
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4);
        NSLayoutConstraint.activate([
            avatar.heightAnchor.constraint(equalToConstant: 36),
            avatar.widthAnchor.constraint(equalToConstant: 36),
            avatar.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 1.0, constant: -4 * 2),
            label.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -4)
        ])
        
        super.init();
        
        addSubview(stack);
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            self.topAnchor.constraint(equalTo: stack.topAnchor),
            self.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

