//
// OMEMOController.swift
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

open class OMEMOContoller: NSViewController, AccountAware, NSTableViewDataSource, NSTableViewDelegate {

    var account: BareJID? {
        didSet {
            refresh()
        }
    }

    @IBOutlet var deviceId: NSTextField!;
    @IBOutlet var localFingerprint: NSTextField!
    @IBOutlet var remoteIdentitiesTableView: OMEMOIdentitiesTableView!
    @IBOutlet var remoteIdentitiesActionButton: NSPopUpButton!;
    
    open override func viewDidLoad() {
        super.viewDidLoad();
        self.remoteIdentitiesTableView.delegate = self;
        NotificationCenter.default.addObserver(self, selector: #selector(omemoAvailabilityChanged), name: MessageEventHandler.OMEMO_AVAILABILITY_CHANGED, object: nil);
    }
    
    open override func viewWillAppear() {
        super.viewWillAppear();
        refresh();
    }
    
    @objc func omemoAvailabilityChanged(_ notification: Notification) {
        guard let event = notification.object as? OMEMOModule.AvailabilityChangedEvent else {
            return;
        }
        DispatchQueue.main.async {
            guard self.account == event.account && self.account == event.jid else {
                return;
            }
            self.refresh();
        }
    }
    
    func refresh() {
        self.remoteIdentitiesActionButton?.isEnabled = false;
        guard let localFingerprint = self.localFingerprint, let account = self.account else {
            return;
        }
        guard let keyPair = DBOMEMOStore.instance.keyPair(forAccount: account) else {
            return;
        }
        let omemoModule: OMEMOModule? = XmppService.instance.getClient(for: account)?.module(.omemo);
        var fingerprint = keyPair.publicKey?.map { (byte) -> String in
            return String(format: "%02x", byte)
            }.dropFirst(1).joined();

        if fingerprint != nil {
            fingerprint = self.remoteIdentitiesTableView.prettify(fingerprint: fingerprint!);
        }
        
        deviceId.stringValue = "\(NSLocalizedString("Device", comment: "device")): \(AccountSettings.omemoRegistrationId(account).uint32() ?? 0)";
        
        localFingerprint.stringValue = fingerprint ?? NSLocalizedString("Key not generated!", comment: "OMEMO settings");
        localFingerprint.textColor = (omemoModule?.isReady ?? false) ?  NSColor.labelColor : NSColor.secondaryLabelColor;
        
        if let tmp = AccountSettings.omemoRegistrationId(account).uint32() {
            let jid = self.account!.stringValue;
            let localDeviceId = Int32(bitPattern: tmp);
            self.remoteIdentitiesTableView.identities = DBOMEMOStore.instance.identities(forAccount: self.account!, andName: jid).filter({ (identity) -> Bool in
                return identity.address.deviceId != localDeviceId;
            })
        } else {
            self.remoteIdentitiesTableView.identities = [];
        }
    }
    
    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "OMEMOIdentityTableCellView"), owner: nil) as? NSTableCellView else {
            return nil;
        }
        
        let identity = self.remoteIdentitiesTableView.identities[row];
        var fingerprint = self.remoteIdentitiesTableView.prettify(fingerprint: String(identity.fingerprint.dropFirst(2)));
        
        let parts = fingerprint.split(separator: " ");
        fingerprint = parts[0..<4].joined(separator: " ") + "\n" + parts[4..<parts.count].joined(separator: " ");
        
        let textColor = identity.status.trust == .compromised ? NSColor.systemRed : (identity.status.isActive ? NSColor.labelColor : NSColor.secondaryLabelColor);
        let value = NSMutableAttributedString(string: "\(NSLocalizedString("Device", comment: "device")): \(identity.address.deviceId)" + "\n", attributes: [.font:NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]);
        value.append(NSAttributedString(string: fingerprint, attributes: [.foregroundColor: textColor]));
        view.textField?.attributedStringValue = value;
        
        return view;
    }
    
    public func tableViewSelectionDidChange(_ notification: Notification) {
        self.remoteIdentitiesActionButton.isEnabled = !self.remoteIdentitiesTableView.selectedRowIndexes.isEmpty;
    }
    
    @IBAction func markCompromised(_ sender: Any) {
        let selected = self.remoteIdentitiesTableView.selectedIdentities;

        let alert = NSAlert();
        alert.messageText = NSLocalizedString("Do you want to mark selected identities as compromised?", comment: "OMEMO settings");
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("No", comment: "Button"))
        alert.beginSheetModal(for: self.view.window!) { (response) in
            switch response {
            case NSApplication.ModalResponse.alertFirstButtonReturn:
                self.setIdentities(trust: .compromised, active: false, forIdentities: selected);
                guard let omemoModule = XmppService.instance.getClient(for: self.account!)?.module(.omemo) else {
                    return;
                }
                
                omemoModule.removeDevices(withIds: selected.map({ (identity) -> Int32 in
                    return identity.address.deviceId;
                }));
            default:
                return;
            }
        }
    }

    @IBAction func markTrusted(_ sender: Any) {
        let alert = NSAlert();
        let selected = self.remoteIdentitiesTableView.selectedIdentities;
        alert.messageText = NSLocalizedString("Do you want to mark selected identities as trusted?", comment: "OMEMO settings");
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("No", comment: "Button"))
        alert.beginSheetModal(for: self.view.window!) { (response) in
            switch response {
            case NSApplication.ModalResponse.alertFirstButtonReturn:
                self.setIdentities(trust: .trusted, active: true, forIdentities:  selected);
            default:
                return;
            }
        }
    }

    fileprivate func setIdentities(trust: Trust, active: Bool, forIdentities selected: [Identity]) {
        guard let account = self.account else {
            return;
        }

        selected.forEach { (identity) in
            _ = DBOMEMOStore.instance.setStatus(identity.status.make(active: active, trust: trust), forIdentity: identity.address, andAccount: account);
        }
        self.refresh();
    }
    
    @IBAction func deleteIdentity(_ sender: Any) {
        let alert = NSAlert();
        let selected = self.remoteIdentitiesTableView.selectedIdentities;
        alert.messageText = NSLocalizedString("Do you want to deactivate and remove selected identities?", comment: "OMEMO settings");
        alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Button"))
        alert.addButton(withTitle: NSLocalizedString("No", comment: "Button"))
        alert.beginSheetModal(for: self.view.window!) { (response) in
            switch response {
            case NSApplication.ModalResponse.alertFirstButtonReturn:
                guard let omemoModule: OMEMOModule = XmppService.instance.getClient(for: self.account!)?.module(.omemo) else {
                    return;
                }
                
                omemoModule.removeDevices(withIds: selected.map({ (identity) -> Int32 in
                    return identity.address.deviceId;
                }));
                self.refresh();
            default:
                return;
            }
        }
    }
    
    @IBAction func closeClicked(_ sender: NSButton) {
        self.dismiss(self);
    }
}
