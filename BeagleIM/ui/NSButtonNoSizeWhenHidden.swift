//
// NSButtonNoSizeWhenHidden.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit

class NSButtonNoSizeWhenHidden: NSButton {
    
    fileprivate var widthConstraint: NSLayoutConstraint?;
    fileprivate var heightConstraint: NSLayoutConstraint?;
    
    override var isHidden: Bool {
        get {
            return super.isHidden;
        }
        set {
            super.isHidden = newValue;
            widthConstraint?.isActive = isHidden;
            heightConstraint?.isActive = isHidden;
        }
    }
    
    override func awakeFromNib() {
        widthConstraint = self.widthAnchor.constraint(equalToConstant: 0);
        heightConstraint = self.widthAnchor.constraint(equalToConstant: 0);
        widthConstraint?.isActive = isHidden;
        heightConstraint?.isActive = isHidden;
    }
    
}
