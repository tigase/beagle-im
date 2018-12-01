//
// FormView.swift
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
        return addRow(label: label, field: field);
    }
    
    func addRow<T: NSView>(label: NSTextField, field: T) -> T {
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
