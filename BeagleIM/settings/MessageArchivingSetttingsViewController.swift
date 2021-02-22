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
    
    var account: BareJID?;
    
    @IBOutlet var archivingEnabled: NSButton!;
    @IBOutlet var automaticSynchronization: NSButton!;
    @IBOutlet var synchronizationPeriod: NSPopUpButton!;
    
    @IBOutlet var saveButton: NSButton!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var isEnabled: Bool = true {
        didSet {
            saveButton.isEnabled = isEnabled;
            archivingEnabled.isEnabled = isEnabled;
            archivingStateChanged();
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        refresh();
    }
    
    func refresh() {
        self.isEnabled = false;
        guard let account = self.account else {
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
        
        progressIndicator.startAnimation(self);
        
        guard let mamModule = XmppService.instance.getClient(for: account)?.module(.mam), mamModule.isAvailable else {
            self.progressIndicator.stopAnimation(self);
            return;
        }
        mamModule.retrieveSettings(completionHandler: { result in
            switch result {
            case .success(let settings):
                DispatchQueue.main.async {
                    self.progressIndicator.stopAnimation(self);
                    let isOn = settings.defaultValue == .always
                    self.archivingEnabled.state = isOn ? .on : .off;
                    self.isEnabled = true;
                }
            case .failure(let error):
                self.progressIndicator.stopAnimation(self);
                self.isEnabled = false;
                print("got an error from the server: \(error), ignoring...");
            }
        });
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.dismiss(self);
    }
        
    @IBAction func submitClicked(_ sender: NSButton) {
        self.isEnabled = false;
        let enable = sender.state == .on;
        guard let mamModule = XmppService.instance.getClient(for: account!)?.module(.mam), mamModule.isAvailable else {
            return;
        }
        self.progressIndicator.startAnimation(self);
        
        mamModule.retrieveSettings(completionHandler: { result in
            switch result {
            case .success(let settings):
                mamModule.updateSettings(settings: MessageArchiveManagementModule.Settings(defaultValue: enable ? .always : .never, always: settings.always, never: settings.never), completionHandler: { (result) in
                    DispatchQueue.main.async {
                        self.isEnabled = true;
                        switch result {
                        case .success(_):
                            AccountSettings.messageSyncAuto(self.account!).set(value: self.automaticSynchronization.state == .on && self.automaticSynchronization.isEnabled);
                            let value = Double(self.synchronizationPeriod.selectedItem?.tag ?? 72)
                            AccountSettings.messageSyncPeriod(self.account!).set(value: value);
                            self.progressIndicator.stopAnimation(self);
                            self.dismiss(self);
                        case .failure(_):
                            self.progressIndicator.stopAnimation(self);
                        }
                    }
                });
            case .failure(_):
                DispatchQueue.main.async {
                    self.isEnabled = true;
                    self.progressIndicator.stopAnimation(self);
                }
            }
        });
    }
        
    @IBAction func archivingStateChanged(_ sender: NSButton) {
        let isOn = sender.state == .on;

        updateArchivingState(isOn);
    }
    
    func updateArchivingState(_ value: Bool) {
        self.archivingEnabled.state = value ? .on : .off;
        archivingStateChanged();
    }
    
    func updateAutomaticSyncState(_ value: Bool) {
        self.automaticSynchronization.state = value ? .on : .off;
        archivingAutoSyncStateChanged();
    }
    
    @IBAction func automaticSynchronizationChanged(_ sender: NSButton) {
        let isOn = sender.state == .on;
        updateAutomaticSyncState(isOn);
    }
    
    private func archivingStateChanged() {
        self.automaticSynchronization.isEnabled = self.archivingEnabled.state == .on && self.archivingEnabled.isEnabled;
        archivingAutoSyncStateChanged();
    }
    
    private func archivingAutoSyncStateChanged() {
        self.synchronizationPeriod.isEnabled = self.automaticSynchronization.state == .on && self.automaticSynchronization.isEnabled;
    }
}
