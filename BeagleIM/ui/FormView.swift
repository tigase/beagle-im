//
// FormView.swift
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

import AppKit

class FormView: NSStackView, NSTextFieldDelegate {
    
    var moveToNextFieldOnEnter: Bool = true;
    
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
        if moveToNextFieldOnEnter {
            (field as? NSTextField)?.delegate = self;
        }
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
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertTab(_:)) {
            control.resignFirstResponder();
            
            guard var idx = self.views.firstIndex(where: { (view) -> Bool in
                view.subviews[1] == control;
            }) else {
                return false;
            }
            
            var responder: NSResponder? = nil;
            repeat {
                idx = idx + 1;
                if idx >= views.count {
                    idx = 0;
                }
                responder = views[idx].subviews[1];
                if !(responder?.acceptsFirstResponder ?? false) {
                    responder = nil;
                }
            } while responder == nil;
            
            self.window?.makeFirstResponder(responder);

            return true;
        }
        return false;
    }
    
    class RowView: NSStackView {
    }
}
