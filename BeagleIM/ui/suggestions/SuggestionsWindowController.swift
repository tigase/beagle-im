//
// SuggestionsWindowController.swift
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

class SuggestionsWindowController<Item>: NSWindowController {
    
    var action: Selector?;
    weak var target: AnyObject?;
    
    private var lostFocusObserver: Any?;
    private var localMouseDownEventMonitor: Any?;
    private var textField: NSTextField?;
    
    private var trackingAreas: [NSTrackingArea] = [];
    private var selectedView: SuggestionItemView<Item>? {
        didSet {
            if selectedView != oldValue {
                selectedView?.isHighlighted = true;
            }
            oldValue?.isHighlighted = false;
        }
    }
    
    private let viewProvider: SuggestionItemView<Item>.Type;
    private var views: [SuggestionItemView<Item>] = [];
    
    private var suggestions: [Item] = [];
    
    public var selected: Item? {
        return selectedView?.item;
    }
    
    init(viewProvider: SuggestionItemView<Item>.Type) {
        self.viewProvider = viewProvider;
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 20, height: 20), styleMask: [.borderless], backing: .buffered, defer: true);
    
        window.backgroundColor = NSColor.clear;
        window.hasShadow = true;
        window.isOpaque = false;
        
        super.init(window: window);
        
        window.contentView = SuggestionsContentView();
        window.contentView?.autoresizesSubviews = false;
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func beginFor(textField: NSTextField) {
        guard let window = self.window, let parentWindow = textField.window else {
            return;
        }
        
        guard var location = textField.superview?.convert(textField.frame.origin, to: nil) else {
            return;
        }
        location = parentWindow.convertPoint(toScreen: location);
        location.y = location.y - 2;
        
        let frame = NSRect(origin: window.frame.origin, size: .init(width: textField.frame.width, height: window.frame.height));
        window.setFrame(frame, display: false);
        window.setFrameTopLeftPoint(location);
        
        parentWindow.addChildWindow(window, ordered: .above);
        
        self.textField = textField;
        
        localMouseDownEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown], handler: { event in
            if event.window != window {
                if event.window == parentWindow {
                    print("we have clicked something!");
                    let contentView = parentWindow.contentView
                    let locationTest = contentView?.convert(event.locationInWindow, from: nil)
                    let hitView = contentView?.hitTest(locationTest ?? NSPoint.zero)
                    let fieldEditor = textField.currentEditor()
                    if hitView != textField && ((fieldEditor != nil) && hitView != fieldEditor) {
                        self.cancelSuggestions()
                        return nil;
                    }
                } else {
                    self.cancelSuggestions();
                }
            }
            return event;
        })
        
        lostFocusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: parentWindow, queue: nil, using: { _ in
            self.cancelSuggestions();
        })
    }
    
    func trackingArea(for view: NSView) -> NSTrackingArea? {
        let rect = window!.contentView!.subviews.first!.convert(view.bounds, from: view);
        let options: NSTrackingArea.Options = [.enabledDuringMouseDrag, .mouseEnteredAndExited, .activeInActiveApp];
        let area = NSTrackingArea(rect: rect, options: options, owner: self, userInfo: ["view": view]);
        return area;
    }
        
    func update(suggestions: [Item]) {
        self.suggestions = suggestions;
        layoutSuggestions();
    }
    
    func layoutSuggestions() {
        for area in trackingAreas {
            window?.contentView?.removeTrackingArea(area);
        }
        trackingAreas.removeAll()
        
        let entries = suggestions.map({ contact -> SuggestionItemView<Item> in
            let view = viewProvider.init();
            view.item = contact;
            return view;
        });
        
        for subview in self.window!.contentView!.subviews {
            subview.removeFromSuperview();
        }
        
        let list = NSStackView(views: entries);
        list.orientation = .vertical;
        list.alignment = .leading;
        list.distribution = .fillEqually;
        list.spacing = 0;
        
        
        self.window!.contentView!.addSubview(list);
        NSLayoutConstraint.activate(entries.map({ list.widthAnchor.constraint(equalTo: $0.widthAnchor, multiplier: 1.0) }) + [self.window!.contentView!.widthAnchor.constraint(equalTo: list.widthAnchor)]);

        let height = CGFloat(44 * entries.count);
        let y = NSMaxY(window!.frame) - height;
        
        let frame = NSRect(origin: NSPoint(x: self.window!.frame.origin.x, y: y), size: NSSize(width: self.window!.frame.width, height: height));
        
        self.window!.setFrame(frame, display: true)
        self.views = entries;
        
        list.layoutSubtreeIfNeeded();
        
        for view in entries {
            if let area = trackingArea(for: view) {
                trackingAreas.append(area);
                window?.contentView?.addTrackingArea(area);
            }
        }
    }
    
    func cancelSuggestions() {
        guard let window = self.window else {
            return;
        }
        
        if window.isVisible {
            window.parent?.removeChildWindow(window);
            window.orderOut(nil);
        }
        
        for area in trackingAreas {
            window.contentView?.removeTrackingArea(area);
        }
        trackingAreas.removeAll()

        for subview in self.window!.contentView!.subviews {
            subview.removeFromSuperview();
        }
        
        selectedView = nil;

        if let observer = self.lostFocusObserver {
            self.lostFocusObserver = nil;
            NotificationCenter.default.removeObserver(observer);
        }

        if let eventMonitor = self.localMouseDownEventMonitor {
            self.localMouseDownEventMonitor = nil;
            NSEvent.removeMonitor(eventMonitor);
        }
    }
    
    override func mouseEntered(with event: NSEvent) {
        if let view = event.trackingArea?.userInfo?["view"] as? SuggestionItemView<Item> {
            self.selectedView = view;
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        self.selectedView = nil;
    }
    
    override func mouseUp(with event: NSEvent) {
        textField?.validateEditing()
        textField?.abortEditing();
        if let action = self.action {
            NSApp.sendAction(action, to: target, from: self);
        }
        cancelSuggestions();
    }
    
    override func moveUp(_ sender: Any?) {
        let selectedView = self.selectedView
        var previousView: SuggestionItemView<Item>? = nil
        for view in views {
            if view == selectedView {
                break;
            }
            previousView = view;
        }

        if previousView != nil {
            self.selectedView = previousView;
        }
    }
    
    override func moveDown(_ sender: Any?) {
        let selectedView = self.selectedView
        var previousView: SuggestionItemView<Item>? = nil
        for view in views.reversed() {
            if view == selectedView {
                break;
            }
            previousView = view;
        }

        if previousView != nil {
            self.selectedView = previousView;
        }
    }
}

