//
// NSPopupButtonNoSizeWhenHidden.swift
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

import AppKit

class NSPopupButtonNoSizeWhenHidden: NSPopUpButton {
    
    fileprivate var widthOriginalConstraint: NSLayoutConstraint?;
    fileprivate var heightOriginalConstraint: NSLayoutConstraint?;
    fileprivate var widthConstraint: NSLayoutConstraint?;
    fileprivate var heightConstraint: NSLayoutConstraint?;
    
    override var isHidden: Bool {
        get {
            return super.isHidden;
        }
        set {
            super.isHidden = newValue;
            if newValue {
                self.widthOriginalConstraint?.isActive = !isHidden;
                self.heightOriginalConstraint?.isActive = !isHidden;
                widthConstraint?.isActive = isHidden;
                heightConstraint?.isActive = isHidden;
            } else {
                widthConstraint?.isActive = isHidden;
                heightConstraint?.isActive = isHidden;
                self.widthOriginalConstraint?.isActive = !isHidden;
                self.heightOriginalConstraint?.isActive = !isHidden;
            }
        }
    }
    
    override func awakeFromNib() {
        self.heightOriginalConstraint = self.constraints.first(where: { (constraint) -> Bool in
            return constraint.relation == .equal && constraint.firstAnchor == self.heightAnchor;
        });
        self.widthOriginalConstraint = self.constraints.first(where: { (constraint) -> Bool in
            return constraint.relation == .equal && constraint.firstAnchor == self.widthAnchor;
        });

        widthConstraint = self.widthAnchor.constraint(equalToConstant: 0);
        heightConstraint = self.heightAnchor.constraint(equalToConstant: 0);
//        widthConstraint?.isActive = isHidden;
//        heightConstraint?.isActive = isHidden;
    }
    
}
