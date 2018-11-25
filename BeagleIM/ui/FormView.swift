//
//  FormView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 15.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class FormView: NSStackView {
    
    override init(frame: NSRect) {
        super.init(frame: frame);
        self.alignment = .centerX;
    }
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder);
        self.alignment = .centerX;
    }
    
    func addRow<T: NSView>(label text: String, field: T) -> T {
        let label = createLabel(text: text);
        let row = RowView(views: [label, field]);
        self.addView(row, in: .bottom);
        label.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.32).isActive = true;
        label.widthAnchor.constraint(lessThanOrEqualToConstant: 250).isActive = true;
        row.widthAnchor.constraint(equalTo: self.widthAnchor, multiplier: 1.0).isActive = true;
        field.trailingAnchor.constraint(equalTo: row.trailingAnchor).isActive = true;
        return field;
    }
    
    func createLabel(text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text);
        label.isEditable = false;
        label.isBordered = false;
        label.drawsBackground = false;
        label.alignment = .right;
        return label;
    }
    
    class RowView: NSStackView {
    }
}
