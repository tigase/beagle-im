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

class FormView: NSGridView, NSTextFieldDelegate {
    
    var moveToNextFieldOnEnter: Bool = true;
    
    override init(frame: NSRect) {
        super.init(frame: frame);
        self.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        self.setContentHuggingPriority(.defaultHigh, for: .vertical);
        self.column(at: 0).xPlacement = .trailing;
        self.rowAlignment = .firstBaseline;
    }
    
    required init?(coder decoder: NSCoder) {
        super.init(coder: decoder);
        self.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        self.setContentHuggingPriority(.defaultHigh, for: .vertical);
        self.column(at: 0).xPlacement = .trailing;
        self.rowAlignment = .firstBaseline;
    }
    
    func addRow<T: NSView>(label text: String, field: T) -> T {
        if moveToNextFieldOnEnter {
            (field as? NSTextField)?.delegate = self;
        }
        let label: NSView = text.isEmpty ? NSGridCell.emptyContentView : createLabel(text: text);
        self.addRow(with: [label, field]);
        (label as? NSTextField)?.alignment = .right;
        return field;
    }
    
    func groupItems(from: NSView, to: NSView) {
        self.cell(for: from)!.row!.topPadding = 5;
        self.cell(for: to)!.row!.bottomPadding = 5;
    }
    
    func addRow<T: NSView>(label: NSTextField, field: T) -> T {
        if moveToNextFieldOnEnter {
            (field as? NSTextField)?.delegate = self;
        }
        self.addRow(with: [label, field]);
        (label as? NSTextField)?.alignment = .right;
        self.column(at: 0).xPlacement = .trailing;
        return field;
    }
    
    func createLabel(text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text);
        label.isEditable = false;
        label.isBordered = false;
        label.setContentHuggingPriority(.defaultLow, for: .vertical);
        label.setContentHuggingPriority(.defaultLow, for: .horizontal);
        label.drawsBackground = false;
        return label;
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertTab(_:)) {
            control.resignFirstResponder();
            
            guard let row = self.cell(for: control)?.row else {
                return false;
            }
            var idx = self.index(of: row)
            
            var responder: NSResponder? = nil;
            repeat {
                idx = idx + 1;
                if idx >= self.numberOfRows {
                    idx = 0;
                }
                responder = self.cell(atColumnIndex: 1, rowIndex: idx).contentView as? NSResponder;
                if !(responder?.acceptsFirstResponder ?? false) {
                    responder = nil;
                }
            } while responder == nil;

            self.window?.makeFirstResponder(responder);

            return true;
        }
        return false;
    }
    
}
