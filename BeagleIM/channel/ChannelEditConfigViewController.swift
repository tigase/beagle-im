//
// ChannelEditConfigViewController.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

class ChannelEditConfigViewControlller: NSViewController, ChannelAwareProtocol {

    @IBOutlet var formView: JabberDataFormView!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var submitButton: NSButton!;
    
    var channel: Channel!;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        retrieveConfig();
    }
    
    @IBAction func submitClicked(_ sender: NSButton) {
        submitConfig();
    }
    
    private func retrieveConfig() {
        guard let mixModule: MixModule = channel.context?.module(.mix) else {
            return;
        }
        
        progressIndicator.startAnimation(self);
        mixModule.retrieveConfig(for: channel.channelJid, completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(self);
                switch result {
                case .success(let config):
                    self?.submitButton.isEnabled = true;
                    self?.formView.form = config;
                case .failure(let errorCondition):
                    guard let that = self else {
                        return;
                    }
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Could not retrieve config", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to retrieve channel configuration: %@", comment: "alert window message"), errorCondition.description);
                    alert.beginSheetModal(for: that.view.window!, completionHandler: { response in
                        that.dismiss(that);
                    })
                }
            }
        })
    }
    
    private func submitConfig() {
        guard let mixModule: MixModule = channel.context?.module(.mix), let config = self.formView.form else {
            return;
        }

        progressIndicator.startAnimation(self);
        mixModule.updateConfig(for: channel.channelJid, config: config, completionHandler: { [weak self] result in
            DispatchQueue.main.async {
                self?.progressIndicator.stopAnimation(self);
                switch result {
                case .success(_):
                    guard let that = self else {
                        return;
                    }
                    that.dismiss(that);
                    break;
                case .failure(let errorCondition):
                    guard let that = self else {
                        return;
                    }
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Configuration change failed", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to change channel configuration: %@", comment: "alert window message"), errorCondition.description);
                    alert.beginSheetModal(for: that.view.window!, completionHandler: nil)
                }
            }
        })
    }
}
