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

    @IBOutlet var name: NSTextField!;
    @IBOutlet var roleAndCompany: NSTextField!;
    @IBOutlet var addressesLabel: NSTextField!;
    @IBOutlet var addresses: NSGridView!;
    @IBOutlet var identitiesTableView: OMEMOIdentitiesTableView!;

    @IBOutlet var roleAndCompanyTopSpacing: NSLayoutConstraint!;
    var roleAndCompanyHeight: NSLayoutConstraint?;
    var addressesLabelHeight: NSLayoutConstraint?;
    
    var account: BareJID!;
    var jid: BareJID!;
    
    open override func viewDidLoad() {
//        self.addresses.removeRow(at: 0);
        self.identitiesTableView.delegate = self;
        self.roleAndCompanyHeight = roleAndCompany.heightAnchor.constraint(equalToConstant: 0);
        self.addressesLabelHeight = addressesLabel.heightAnchor.constraint(equalToConstant: 0);
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
        DBVCardStore.instance.vcard(for: jid) { (vcard) in
            DispatchQueue.main.async {
                var fn: String = "";
                if let fn1 = vcard?.fn, !fn1.isEmpty {
                    fn = fn1;
                } else {
                    if let given = vcard?.givenName, !given.isEmpty {
                        fn = given;
                    }
                    if let surname = vcard?.surname, !surname.isEmpty {
                        fn = fn.isEmpty ? surname : "\(fn) \(surname)"
                    }
                    if fn.isEmpty {
                        fn = XmppService.instance.getClient(for: self.account)?.rosterStore?.get(for: JID(self.jid))?.name ?? self.jid.stringValue;
                    }
                }
                self.name.stringValue = fn;
                
//                let details = NSMutableAttributedString(string: fn);
//                details.addAttribute(.font, value: NSFont(descriptor: self.name.font!.fontDescriptor, size: NSFont.labelFontSize + 2.0)!, range: NSRange(location: 0, length: details.length));
//                details.applyFontTraits(.boldFontMask, range: NSRange(location: 0, length: details.length));
                
                var line = vcard?.role;
                if let org = vcard?.organizations.first?.name, !org.isEmpty {
                    line = (line?.isEmpty ?? true) ? org : "\(line!) at \(org)"
                }
//                if !(line?.isEmpty ?? true) {
//                    details.append(NSAttributedString(string: "\n"));
//                    details.append(NSAttributedString(string: line!));
//                }

                self.roleAndCompany.stringValue = line ?? "";
                self.roleAndCompanyHeight?.isActive = line?.isEmpty ?? true;
                self.roleAndCompanyTopSpacing.constant = (line?.isEmpty ?? true) ? 0.0 : 4.0;
                
                self.addressesLabelHeight?.isActive = vcard?.addresses.filter({ (a) -> Bool in
                    return !a.isEmpty
                }).isEmpty ?? true;
                
                if vcard != nil {
                    if self.addresses.numberOfRows > 1 {
                        for _ in 0..<(self.addresses!.numberOfRows-1) {
                            self.addresses.removeRow(at: 0);
                        }
                    }
                    for addr in vcard!.addresses.filter({ (a) -> Bool in
                        return !a.isEmpty;
                    }) {
                        self.add(address: addr);
//                        self.add(address: addr);
                    }
//                    if self.addresses.numberOfRows == 0 {
//                        self.addresses.addRow(with: [NSGridCell.emptyContentView]);
//                    }
                    self.addresses.needsLayout = true;
                    self.addresses.layout();
                }
//                self.name.attributedStringValue = details;
            }
        }
    }
    
    fileprivate func add(address addr: VCard.Address) {
        let label = NSTextField(labelWithString: (addr.types.first ?? .home) == .home ? "Home" : "Work");
        label.setContentHuggingPriority(.defaultLow, for: .vertical);
        label.setContentHuggingPriority(.defaultLow, for: .horizontal);
        label.font = NSFont(descriptor: self.roleAndCompany.font!.fontDescriptor.withSymbolicTraits(.bold), size: NSFont.systemFontSize - 2.0)
        
        var str = "";
        if let street = addr.street, !street.isEmpty {
            str = street;
        }
        let locality = addr.locality;
        let postalCode = addr.postalCode;
        if locality != nil || postalCode != nil {
            if locality != nil && postalCode != nil {
                str = str.isEmpty ? (locality!) : "\(str), \(postalCode!) \(locality!)"
            } else {
                if locality != nil {
                    str = str.isEmpty ? (locality!) : "\(str), \(locality!)"
                }
            }
        }
        if let region = addr.region, !region.isEmpty {
            str = str.isEmpty ? region : "\(str), \(region)";
        }
        if let country = addr.country, !country.isEmpty {
            str = str.isEmpty ? country : "\(str), \(country)"
        }
        
        var parts = URLComponents();
        parts.scheme = "http";
        parts.host = "maps.apple.com";
        parts.queryItems = [ URLQueryItem(name: "q", value: str.replacingOccurrences(of: ", ", with: ",")) ];
        let value = NSTextField(wrappingLabelWithString: str);
        value.font = NSFont(descriptor: self.roleAndCompany.font!.fontDescriptor, size: NSFont.systemFontSize - 2.0)
        value.setContentHuggingPriority(.defaultLow, for: .vertical);
        value.setContentHuggingPriority(.defaultLow, for: .horizontal);
        value.isEditable = false;
        value.isEnabled = true;
        value.isSelectable = true;
        value.allowsEditingTextAttributes = true;
//        if let url = URL(string: "http:://maps.apple.com/?q=\(str.replacingOccurrences(of: "\n", with: "\n"))") {
        if let url = parts.url {
            value.attributedStringValue = NSAttributedString(string: str, attributes: [.link : url]);
        }
        self.addresses.insertRow(at: self.addresses.numberOfRows-1, with: [ label, value ])
    }
    
    @IBAction func refreshVCard(_ sender: NSButton) {
        VCardManager.instance.refreshVCard(for: jid, on: account) { (vcard) in
            if vcard != nil {
                DispatchQueue.main.async {
                    self.refresh();
                }
            }
        }
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
