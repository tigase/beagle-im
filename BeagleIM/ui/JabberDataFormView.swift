//
// JabberDataFormView.swift
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
import TigaseSwift

class JabberDataFormView: FormView {
    
    fileprivate var namedFieldViews: [String: Any] = [:];
    var form: JabberDataElement? {
        didSet {
            update();
        }
    }
    
    func synchronize() {
        form?.visibleFieldNames.forEach { fieldName in
            synchronize(field: form!.getField(named: fieldName)!);
        }
    }
    
    func update() {
        let subviews = self.subviews;
        subviews.forEach { view in
            view.removeFromSuperview();
        }
        namedFieldViews.removeAll();
        
        guard form != nil else {
            return;
        }
        
        form?.visibleFieldNames.forEach { fieldName in
            let f = form!.getField(named: fieldName)!;
            register(field: f);
        }
    }
    
    fileprivate func synchronize(field formField: Field) {
        let formView = self.namedFieldViews[formField.name];
        switch formField {
        case let f as BooleanField:
            f.value = (formView as! NSButton).state == .on;
        case let f as TextSingleField:
            let v = (formView as! NSTextField).stringValue;
            f.value = v.isEmpty ? nil : v;
        case let f as TextPrivateField:
            let v = (formView as! NSSecureTextField).stringValue;
            f.value = v.isEmpty ? nil : v;
        case let f as TextMultiField:
            let v = (formView as! NSTextView).string;
            f.value = v.isEmpty ? [] : v.split(separator: "\n").map({s -> String in return String(s)});
        case let f as JidSingleField:
            let v = (formView as! NSTextField).stringValue;
            f.value = v.isEmpty ? nil : JID(v);
        case let f as JidMultiField:
            let v = (formView as! NSTextView).string;
            f.value = v.isEmpty ? [] : v.split(separator: "\n").filter { s -> Bool in
                return !s.isEmpty }.map{s -> String in
                    return String(s)}.map {s -> JID in
                        return JID(s)};
        case let f as ListSingleField:
            let v = (formView as! NSPopUpButton).indexOfSelectedItem;
            f.value = v == -1 ? nil : f.options[v-1].value;
        case let f as ListMultiField:
            let values = formView as! [String: NSButton];
            let v: [String] = values.filter { (k, v)  -> Bool in
                return v.state == .on;
                }.map { (k, v) -> String in
                    return k;
            };
            f.value = v;
        default:
            break
        }
    }
    
    fileprivate func register(field formField: Field) {
        guard let fieldView = create(field: formField) else {
            return;
        }
        namedFieldViews[formField.name] = fieldView;
    }
    
    fileprivate func create(field formField: Field) -> Any? {
        let label = formField.label ?? (formField.name.prefix(1).uppercased() + formField.name.dropFirst());
        switch formField {
        case let f as BooleanField:
            return addCheckbox(label: label, value: f.value);
        case let f as TextSingleField:
            return addTextField(label: label, value: f.value);
        case let f as TextPrivateField:
            return addTextPrivateField(label: label, value: f.value);
        case let f as TextMultiField:
            return addTextMultiField(label: label, value: f.value);
        case let f as JidSingleField:
            return addTextField(label: label, value: f.value?.stringValue);
        case let f as JidMultiField:
            return addTextMultiField(label: label, value: f.value.map({ j -> String in return j.stringValue}));
        case let f as ListSingleField:
            return addListSingleField(label: label, value: f.value, options: f.options);
        case let f as ListMultiField:
            return addListMultiField(label: label, value: f.value, options: f.options);
        default:
            return nil;
        }
    }
    
    fileprivate func addCheckbox(label: String, value: Bool) -> NSButton {
        let tooltip = String(label.drop(while: { (ch) -> Bool in
            ch != "(";
        }));
        let field = NSButton(checkboxWithTitle: String(label.dropLast(tooltip.count)), target: nil, action: nil);
        if !tooltip.isEmpty {
            field.toolTip = tooltip;
        }
        field.state = value ? .on : .off;
        return addRow(label: "", field: field);
    }
    
    fileprivate func addTextField(label: String, value: String?) -> NSTextField {
        let field = NSTextField(string: value ?? "");
        return addRow(label: label, field: field);
    }

    fileprivate func addTextPrivateField(label: String, value: String?) -> NSSecureTextField {
        let field = NSSecureTextField(string: value ?? "");
        return addRow(label: label, field: field);
    }

    fileprivate func addTextMultiField(label: String, value: [String]) -> NSTextView {
        let scroll = NSScrollView(frame: .zero);
        scroll.autoresizingMask = [.width, .height];
        scroll.hasHorizontalRuler = false;
        scroll.heightAnchor.constraint(equalToConstant: 100);
        
        let contentSize = scroll.contentSize;
        
        let field = NSTextView(frame: NSRect(x: 0, y:0, width: contentSize.width, height: contentSize.height));
        field.minSize = NSSize(width: 0.0, height: contentSize.height);
        field.maxSize = NSSize(width: Double.greatestFiniteMagnitude, height: Double.greatestFiniteMagnitude);
        field.isVerticallyResizable = true;
        field.isHorizontallyResizable = false;
        field.autoresizingMask = .width;
        field.textContainer?.containerSize = NSSize(width: contentSize.width, height: CGFloat(Float.greatestFiniteMagnitude));
        field.string = value.joined(separator: "\n");
        field.textContainer?.widthTracksTextView = true;
        scroll.documentView = field;
        
        _ = addRow(label: label, field: scroll);
        return field;
    }
    
    fileprivate func addListSingleField(label: String, value: String?, options: [ListFieldOption]) -> NSButton {
        let field = NSPopUpButton(frame: .zero, pullsDown: true);
        field.addItem(withTitle: "");
        field.action = #selector(listSelectionChanged);
        field.target = self;
        field.addItems(withTitles: options.map { option in option.label ?? option.value });
        if value != nil, let idx = options.firstIndex(where: { (option) -> Bool in
            return value! == option.value;
        }) {
            field.selectItem(at: idx + 1);
            field.title = field.titleOfSelectedItem ?? "";
        }
        _ = addRow(label: label, field: field);
        return field;
    }
    
    @objc fileprivate func listSelectionChanged(_ sender: NSPopUpButton) {
        sender.title = sender.titleOfSelectedItem ?? "";
    }
    
    fileprivate func addListMultiField(label: String, value: [String], options: [ListFieldOption]) -> Any {
        _ = self.addRow(label: "", field: NSTextField(labelWithString: ""));
        let stackView = NSStackView();
        stackView.alignment = .leading;
        stackView.orientation = .vertical;
        var optionFields: [String: NSButton] = [:];
        options.forEach { option in
            let field = NSButton(checkboxWithTitle: option.label ?? option.value, target: nil, action: nil);
            field.state = value.contains(option.value) ? .on : .off;
            optionFields[option.value] = field;
            stackView.addView(field, in: .bottom);
        }
        _ = self.addRow(label: label, field: stackView);
        _ = self.addRow(label: "", field: NSTextField(labelWithString: ""));
        return optionFields;
    }
        
}
