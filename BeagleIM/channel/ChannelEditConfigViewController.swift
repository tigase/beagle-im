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
import Martin

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
        Task {
            do {
                let config = try await mixModule.config(for: channel.channelJid);
                await MainActor.run(body: {
                    self.submitButton.isEnabled = true;
                    self.formView.form = config.form;
                })
            } catch {
                await MainActor.run(body: {
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Could not retrieve config", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to retrieve channel configuration: %@", comment: "alert window message"), error.localizedDescription);
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                        self.dismiss(self);
                    })
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(self);
            })
        }
    }
    
    private func submitConfig() {
        guard let mixModule: MixModule = channel.context?.module(.mix), let config = self.formView.form else {
            return;
        }

        progressIndicator.startAnimation(self);
        Task {
            do {
                try await mixModule.config(.init(form: config), for: channel.channelJid);
                await MainActor.run(body: {
                    self.dismiss(self);
                })
            } catch {
                await MainActor.run(body: {
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Configuration change failed", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to change channel configuration: %@", comment: "alert window message"), error.localizedDescription);
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil)
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(self);
            })
        }
    }
}
