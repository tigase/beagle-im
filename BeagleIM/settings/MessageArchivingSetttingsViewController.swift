//
// MessageArchivingSetttingsViewController.swift
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
import TigaseSwift

class MessageArchivingSettingsViewController: NSViewController, AccountAware {
    
    var account: BareJID? {
        didSet {
            refresh()
        }
    }
    
    @IBOutlet var archivingEnabled: NSButton!;
    @IBOutlet var automaticSynchronization: NSButton!;
    @IBOutlet var synchronizationPeriod: NSPopUpButton!;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        refresh();
    }
    
    func refresh() {
        guard automaticSynchronization != nil else {
            return;
        }
        guard let account = self.account else {
            self.disable();
            return;
        }
        
        let syncEnabled = AccountSettings.messageSyncAuto(account).bool();
        automaticSynchronization.state = syncEnabled ? .on : .off;
        
        var syncPeriod = Int(AccountSettings.messageSyncPeriod(account).double());
        if syncPeriod == 0 {
            syncPeriod = 72;
            AccountSettings.messageSyncPeriod(account).set(value: Double(syncPeriod));
        }
        let idx = synchronizationPeriod.itemArray.lastIndex { (item) -> Bool in
            return item.tag <= syncPeriod
            } ?? 0;
        synchronizationPeriod.selectItem(at: idx == 0 ? 1 : idx);
        synchronizationPeriod.title = synchronizationPeriod.titleOfSelectedItem ?? "";
        
        guard let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MessageArchiveManagementModule.ID), mamModule.isAvailable else {
            self.disable();
            return;
        }
        mamModule.retrieveSettings(onSuccess: { (defaultValue, _, _) in
            DispatchQueue.main.async {
                let isOn = defaultValue == .always
                self.archivingEnabled.state = isOn ? .on : .off;
                self.archivingEnabled.isEnabled = true;
                self.automaticSynchronization.isEnabled = isOn;
                self.synchronizationPeriod.isEnabled = syncEnabled;
            }
        }) { (errorCondition, stanza) in
            print("got an error from the server:", errorCondition as Any, ", ignoring...");
        }
    }
    
    func disable() {
        archivingEnabled.isEnabled = false;
        automaticSynchronization.isEnabled = false;
        synchronizationPeriod.isEnabled = false;
    }
    
    @IBAction func archivingStateChanged(_ sender: NSButton) {
        let isOn = sender.state == .on;
        
        guard let mamModule: MessageArchiveManagementModule = XmppService.instance.getClient(for: account!)?.modulesManager.getModule(MessageArchiveManagementModule.ID), mamModule.isAvailable else {
            self.updateArchivingState(!isOn);
            return;
        }
        
        mamModule.retrieveSettings(onSuccess: { (defaultValue, always, never) in
            mamModule.updateSettings(defaultValue: isOn ? .always : .never, always: always, never: never, onSuccess: { (newValue, always, never) in
                self.updateArchivingState(newValue == .always);
            }, onError: { (errorCondition, stanza) in
                self.updateArchivingState(defaultValue == .always);
            });
        }, onError: { (errorCondition, stanza) in
            self.updateArchivingState(!isOn);
        });
    }
    
    func updateArchivingState(_ value: Bool) {
        DispatchQueue.main.async {
            self.archivingEnabled.state = value ? .on : .off;
            self.automaticSynchronization.isEnabled = value;
            self.synchronizationPeriod.isEnabled = value && (self.automaticSynchronization.state == .on);
        }
    }
    
    func updateAutomaticSyncState(_ value: Bool) {
        AccountSettings.messageSyncAuto(account!).set(value: value);
        DispatchQueue.main.async {
            self.automaticSynchronization.state = value ? .on : .off;
            self.synchronizationPeriod.isEnabled = value;
        }
    }
    
    @IBAction func automaticSynchronizationChanged(_ sender: NSButton) {
        let isOn = sender.state == .on;
        updateAutomaticSyncState(isOn);
    }
    
    @IBAction func synchronizationPeriodChanged(_ sender: NSPopUpButton) {
        let value = Double(sender.selectedItem?.tag ?? 72)
        AccountSettings.messageSyncPeriod(account!).set(value: value);
    }
}
