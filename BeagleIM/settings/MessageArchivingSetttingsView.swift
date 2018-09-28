//
//  MessageArchivingSetttingsView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 28/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class MessageArchivingSettingsView: NSView, AccountAwareView {
    
    var account: BareJID? {
        didSet {
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
    }
    
    @IBOutlet var archivingEnabled: NSButton!;
    @IBOutlet var automaticSynchronization: NSButton!;
    @IBOutlet var synchronizationPeriod: NSPopUpButton!;
    
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
