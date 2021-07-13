//
// MultiContactSelectionView.swift
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

class MultiContactSelectionView: NSView, NSTableViewDelegate, NSTableViewDataSource {
    
    private let searchField = ContactSuggestionField();
    private let scrollView = NSScrollView();
    private let tableView = NSTableView();
    
    @Published
    private(set) var items: [ContactSuggestionField.Item] = [];
    private var cancellables: Set<AnyCancellable> = [];
    
    public var closedSuggestionsList: Bool {
        get {
            return searchField.closedSuggestionsList;
        }
        set {
            searchField.closedSuggestionsList = newValue;
        }
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();

        searchField.placeholderString = "Enter contact name or jid"
        searchField.translatesAutoresizingMaskIntoConstraints = false;
        scrollView.translatesAutoresizingMaskIntoConstraints = false;
        
        self.addSubview(searchField);
        self.addSubview(scrollView);
        
        NSLayoutConstraint.activate([
            scrollView.heightAnchor.constraint(equalToConstant: 200),
            
            searchField.topAnchor.constraint(equalTo: self.topAnchor),
            searchField.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            searchField.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            
            searchField.bottomAnchor.constraint(equalTo: scrollView.topAnchor, constant: -10),
            
            scrollView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: self.bottomAnchor),
        ])

        tableView.frame = scrollView.bounds;
        scrollView.backgroundColor = NSColor.clear;
        tableView.backgroundColor = NSColor.clear;
        
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(rawValue: "col"));
        column.minWidth = 150;
        tableView.addTableColumn(column);
        
        scrollView.documentView = tableView;
        scrollView.hasHorizontalScroller = false;
        scrollView.hasVerticalScroller = true;

        tableView.headerView = nil;
        
        tableView.usesAutomaticRowHeights = true;
        tableView.delegate = self;
        tableView.dataSource = self;
        
        searchField.selectionPublisher.sink(receiveValue: { [weak self] item in
            self?.items.append(item);
            self?.tableView.insertRows(at: IndexSet([self!.items.count - 1]), withAnimation: .effectFade);
        }).store(in: &cancellables);
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return items.count;
    }
    
    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = SelectedContactView();
        view.item = self.items[row];
        view.removeClicked = { [weak self] item in
            self?.remove(item: item);
        };
        return view;
    }
    
    private func remove(item: ContactSuggestionField.Item) {
        guard let idx = self.items.firstIndex(where: { $0.jid == item.jid && $0.account == item.account }) else {
            return;
        }
        self.items.remove(at: idx);
        self.tableView.removeRows(at: IndexSet([idx]), withAnimation: .effectFade);
    }
        
    class SelectedContactView: ChatsListSuggestionItemView {
        
        var closeButton: NSButton!;
        
        var removeClicked: ((ContactSuggestionField.Item)->Void)?;
        
        required init() {
            super.init();
            avatarSize = 24;
            closeButton = NSButton(image: NSImage(named: NSImage.stopProgressTemplateName)!, target: self, action: #selector(removeButtonClicked(_:)))
            closeButton.isBordered = false;
            closeButton.isTransparent = false;
            closeButton.bezelStyle = .shadowlessSquare;
            self.stack.addArrangedSubview(closeButton);
            NSLayoutConstraint.activate([
                closeButton.widthAnchor.constraint(equalTo: closeButton.heightAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 20)
            ])
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        @objc func removeButtonClicked(_ sender: Any) {
            guard let item = self.item else {
                return;
            }
            removeClicked?(item);
        }
    }
}
