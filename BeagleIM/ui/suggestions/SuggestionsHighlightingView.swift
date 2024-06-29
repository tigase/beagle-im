//
// SuggestionsHighlightingView.swift
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

class SuggestionsHighlightingView: NSView {
    
    var isHighlighted: Bool = false {
        didSet {
            let appearance = self.subviewAppearance();
            for subview in subviews {
                subview.appearance = appearance;
            }
            needsDisplay = true;
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.alternateSelectedControlColor.set()
            __NSRectFillUsingOperation(bounds, .sourceOver)
        } else {
            NSColor.clear.set()
            __NSRectFillUsingOperation(bounds, .sourceOver)
        }
     //   super.draw(dirtyRect);
    }
    
    func subviewAppearance() -> NSAppearance {
        let appearance = super.effectiveAppearance;
        guard isHighlighted else {
            return appearance;
        }
        if appearance.name == .darkAqua {
            return NSAppearance(named: .aqua)!;
        } else {
            return NSAppearance(named: .darkAqua)!;
        }
    }
    
}
