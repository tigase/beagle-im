//
// ChannelSelectNewOwnerViewController.swift
//
// BeagleIM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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
import Combine
import Martin

class ChannelSelectNewOwnerViewController: NSViewController {
 
    @IBOutlet var newOwnerSelector: SingleParticipantSelectionView!;
    @IBOutlet var changeButton: NSButton!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    var participants: [MixParticipant] = [];
    var successHandler: ((BareJID)->Void)?;
    
    var selected: MixParticipant? {
        didSet {
            changeButton.isEnabled = selected != nil;
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        newOwnerSelector.selectionPublisher.sink(receiveValue: { [weak self] newAdmin in
            self?.selected = newAdmin;
        }).store(in: &cancellables);
        newOwnerSelector.participants = self.participants;
    }
    
    @IBAction func changeClicked(_ sender: NSButton) {
        guard let jid = selected?.jid else {
            return;
        }
        self.dismiss(self);
        successHandler?(jid);
    }
}

class SingleParticipantSelectionView: NSSearchField, NSSearchFieldDelegate {
    
    private var suggestionsController: SuggestionsWindowController?;

    let selectionPublisher = PassthroughSubject<MixParticipant?,Never>();

    var suggestionsWindowBackground: NSColor?;

    var participants: [MixParticipant] = [];
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        self.setup();
    }
    
    init() {
        super.init(frame: .zero);
        self.setup();
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();
        self.setup();
    }
    
    func setup() {
        self.delegate = self;
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        if suggestionsController == nil {
            suggestionsController = SuggestionsWindowController(viewProviders: [MixParticipantSuggestionItemView.Provider()], edge: .bottom);
            if let color = suggestionsWindowBackground {
                suggestionsController?.backgroundColor = color;
            }
            suggestionsController?.target = self;
            suggestionsController?.action = #selector(self.suggestionItemSelected(sender:))
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        self.selectionPublisher.send(nil);
        let query = self.stringValue.lowercased();
            
        var items = participants.filter({ $0.nickname?.lowercased().contains(query) ?? false || $0.jid?.description.lowercased().contains(query) ?? false }).sorted(by: { p1, p2 -> Bool in
            return (p1.nickname ?? p1.jid?.description ?? p1.id) < (p2.nickname ?? p2.jid?.description ?? p2.id);
        });
                        
        if !items.isEmpty {
            if items.count > 5 {
                items = Array(items.prefix(5));
            }
            if !(suggestionsController?.window?.isVisible ?? false) {
                suggestionsController?.beginFor(textField: self);
            }
        }
            
        suggestionsController?.update(suggestions: items);
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        suggestionsController?.cancelSuggestions();
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            suggestionsController?.moveUp(textView);
            return true
        case #selector(NSResponder.moveDown(_:)):
            suggestionsController?.moveDown(textView);
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if let controller = self.suggestionsController {
                suggestionItemSelected(sender: controller);
            }
        case #selector(NSResponder.complete(_:)):
            suggestionsController?.cancelSuggestions();
            return true;
        default:
            break;
        }
        return false;
    }
    
    @objc func suggestionItemSelected(sender: Any) {
        guard let item = (sender as? SuggestionsWindowController)?.selected as? MixParticipant else {
            return;
        }
     
        self.stringValue = item.nickname ?? item.jid?.description ?? item.id;
        selectionPublisher.send(item);
    }
    
}
