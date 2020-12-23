//
// EditKeywordsController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class EditKeywordsController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    
    private var keywords: [String] = [];
    
    @IBOutlet var tableView: NSTableView!;
    @IBOutlet var addRemoveSegmentedControl: NSSegmentedControl!;
    
    override func viewDidLoad() {
        keywords = Settings.markKeywords;
        super.viewDidLoad();
        addRemoveSegmentedControl.setEnabled(tableView.selectedRow >= 0, forSegment: 1);
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return keywords.count;
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "KeywordTableViewCell"), owner: self);
        (cell?.subviews.first as? NSTextField)?.stringValue = keywords[row];
        return cell;
    }
    
    func tableViewSelectionDidChange(_ notification: Notification) {
        addRemoveSegmentedControl.setEnabled(tableView.selectedRow >= 0, forSegment: 1);
    }
    
    @IBAction func itemTextFieldUpdated(_ sender: NSTextField) {
        let row = self.tableView.selectedRow;
        guard row >= 0 else {
            return;
        }
        keywords[row] = sender.stringValue;
    }
    
    @IBAction func addedRemovedRow(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0:
            keywords.append("");
            tableView.reloadData();
        case 1:
            let row = self.tableView.selectedRow;
            guard row >= 0 else {
                return;
            }
            keywords.remove(at: row);
            tableView.reloadData();
        default:
            break;
        }
    }
    
    @IBAction func saveClicked(_ sender: NSButton) {
        self.view.window?.makeFirstResponder(self);
        DispatchQueue.main.async {
            let validKeywords = self.keywords.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty };
            Settings.markKeywords = validKeywords;
            self.close();
        }
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }
    
    func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
}
