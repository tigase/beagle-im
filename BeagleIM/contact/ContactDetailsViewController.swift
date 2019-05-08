//
// ContactDetailsViewController.swift
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
import TigaseSwift
import TigaseSwiftOMEMO

open class ContactDetailsViewController: NSViewController, NSTableViewDelegate {

    @IBOutlet var identitiesTableView: OMEMOIdentitiesTableView!;

    var account: BareJID!;
    var jid: BareJID!;
    
    open override func viewDidLoad() {
        self.identitiesTableView.delegate = self;
    }
    
    open override func viewWillAppear() {
        refresh();
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identity = identitiesTableView.identities[row];
        
        switch tableView.column(withIdentifier: tableColumn!.identifier) {
        case 1:
            guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ContactViewOMEMOTrustCellView"), owner: nil) as? NSTableCellView else {
                return nil;
            }
            
            var idx = 0;
            switch identity.status.trust {
            case .undecided:
                idx = 0;
            case .trusted:
                idx = 1;
            case .verified:
                idx = 2;
            case .compromised:
                idx = 3;
            }
            if let button = cell.subviews.first as? NSPopUpButton {
                button.isEnabled = identity.status.isActive;
                button.tag = row;
                button.target = self;
                button.action = #selector(trustChanged);
                let color = identity.status.trust == .compromised ? NSColor.systemRed : (identity.status.isActive ? NSColor.labelColor : NSColor.secondaryLabelColor);
                button.contentTintColor = color;
                button.selectItem(at: idx);
                button.synchronizeTitleAndSelectedItem();
            }
            return cell;
        default:
            guard let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ContactViewOMEMOFingerprintCellView"), owner: nil) as? NSTableCellView else {
                return nil;
            }
            
            cell.textField?.textColor = identity.status.trust == .compromised ? NSColor.systemRed : (identity.status.isActive ? NSColor.labelColor : NSColor.secondaryLabelColor);
            cell.textField?.stringValue = identitiesTableView.prettify(fingerprint: String(identity.fingerprint.dropFirst(2)));
            
            return cell;
        }
    }
    
    func refresh() {
        identitiesTableView.identities = DBOMEMOStore.instance.identities(forAccount: account!, andName: jid!.stringValue);
    }
 
    @objc func trustChanged(_ sender: NSPopUpButton) {
        var trust = Trust.trusted;
        switch sender.selectedTag() {
        case 2:
            trust = .trusted;
        case 3:
            trust = .verified;
        case 4:
            trust = .compromised;
        default:
            trust = .undecided;
        }
        let identity = identitiesTableView.identities[sender.tag];
        DBOMEMOStore.instance.setStatus(identity.status.toTrust(trust), forIdentity: identity.address, andAccount: self.account);
        DispatchQueue.main.async {
            self.refresh();
        }
    }
    
}
