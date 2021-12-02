//
// SuggestionItemView.swift
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

protocol SuggestionItemViewProvider {
    func view(for: Any) -> SuggestionItemView?;
}

protocol SuggestionItemView: AnyObject {
    
    var appearance: NSAppearance? { get set };
    
    var suggestion: Any? { get set }

    var isHighlighted: Bool { get set }
    
    var itemHeight: Int { get }
    
}

extension SuggestionItemView {
    
    var view: NSView {
        return self as! NSView;
    }
    
}

class SuggestionItemViewBase<Item>: SuggestionsHighlightingView, SuggestionItemView {
    
    var suggestion: Any? {
        get {
            return item;
        }
        set {
            item = newValue as? Item;
        }
    }
    
    var item: Item?;
    
    var itemHeight: Int {
        return 0;
    }
    
    required init() {
        super.init(frame: .zero);
        isHidden = false;
//        setContentHuggingPriority(.defaultLow, for: .horizontal);
//        setContentHuggingPriority(.defaultHigh, for: .vertical);
        setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
    }
    
}
