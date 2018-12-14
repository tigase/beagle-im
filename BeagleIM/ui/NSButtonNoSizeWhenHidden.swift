//
//  NSButtonNoSizeWhenHidden.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 08/12/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
