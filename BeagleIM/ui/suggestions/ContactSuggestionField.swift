//
// ContactSuggestionField.swift
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
import Combine
import Martin

class ContactSuggestionField: NSSearchField, NSSearchFieldDelegate {
    
    private var suggestionsController: SuggestionsWindowController?;
    
    let selectionPublisher = PassthroughSubject<Item,Never>();
    
    var closedSuggestionsList: Bool = true;
    var suggestionsWindowBackground: NSColor?;
    
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
            suggestionsController = SuggestionsWindowController(viewProviders: [ChatsListSuggestionItemView.Provider()], edge: .bottom);
            if let color = suggestionsWindowBackground {
                suggestionsController?.backgroundColor = color;
            }
            suggestionsController?.target = self;
            suggestionsController?.action = #selector(self.suggestionItemSelected(sender:))
        }
//        suggestionsController?.beginFor(textField: self.searchField!);
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if self.stringValue.count < 2 {
            suggestionsController?.cancelSuggestions();
        } else {
            let query = self.stringValue.lowercased();
            
            let conversations: [DisplayableIdWithKeyProtocol] = DBChatStore.instance.conversations.filter({ $0.displayName.lowercased().contains(query) || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) });

            var keys = Set(conversations.map({ Contact.Key(account: $0.account, jid: $0.jid, type: .buddy) }));
            
            let contacts: [DisplayableIdWithKeyProtocol] = DBRosterStore.instance.items.filter({ $0.name?.lowercased().contains(query) ?? false || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) }).compactMap({ item -> Contact? in
                guard let account = item.context?.userBareJid, !keys.contains(.init(account: account, jid: item.jid.bareJid, type: .buddy)) else {
                    return nil;
                }
                return ContactManager.instance.contact(for: .init(account: account, jid: item.jid.bareJid, type: .buddy))
            });
            
            keys = Set(keys + contacts.map({ Contact.Key(account: $0.account, jid: $0.jid, type: .buddy) }));
            
            let bookmarks = XmppService.instance.clients.values.flatMap({ client in client.module(.pepBookmarks).currentBookmarks.items.compactMap({ $0 as? Bookmarks.Conference }).filter({ $0.name?.lowercased().contains(query) ?? false || $0.jid.localPart?.lowercased().contains(query) ?? false || $0.jid.domain.lowercased().contains(query) }).filter({ !keys.contains(.init(account: client.userBareJid, jid: $0.jid.bareJid, type: .buddy)) }).map({ Item(jid: $0.jid.bareJid, account: client.userBareJid, name: String.localizedStringWithFormat(NSLocalizedString("Join %@", comment: "action join bookmark item"), $0.name ?? $0.jid.description), displayableId: nil) }) });
            
            
            var items: [Item] = ((contacts + conversations).map({ Item(jid: $0.jid, account: $0.account, name: $0.displayName, displayableId: $0) }) + bookmarks).sorted(by: { c1, c2 -> Bool in c1.name < c2.name })
            
            if !closedSuggestionsList {
                items.append(Item(jid: BareJID(query), account: nil, name: query, displayableId: nil));
            }
            
            if !items.isEmpty {
                if !(suggestionsController?.window?.isVisible ?? false) {
                    suggestionsController?.beginFor(textField: self);
                }
            }
            
            suggestionsController?.update(suggestions: items);
        }
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
        guard let item = (sender as? SuggestionsWindowController)?.selected as? Item else {
            return;
        }
        
        self.stringValue = "";
        
        selectionPublisher.send(item);
    }
    
    struct Item {
        let jid: BareJID;
        let account: BareJID?;
        let name: String;
        let displayableId: DisplayableIdProtocol?;
    }

}
