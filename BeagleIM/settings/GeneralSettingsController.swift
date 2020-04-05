//
// GeneralSettingsController.swift
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

class GeneralSettingsController: NSViewController {
    
    @IBOutlet var formView: FormView!;
    
    fileprivate var appearance: NSPopUpButton?;
    fileprivate var autoconnect: NSButton!;
    fileprivate var automaticStatus: NSButton!;
    fileprivate var rememberLastStatusButton: NSButton!;
    
    fileprivate var enableMessageCarbonsButton: NSButton!;
    fileprivate var messageCarbonsMarkAsReadButton: NSButton!;
    fileprivate var messageCarbonsMarkDeliveredToOtherResourceAsRead: NSButton!;

    fileprivate var notificationsFromUnknownSenders: NSButton!;
    fileprivate var systemMenuIcon: NSButton!;
    
    fileprivate var markdownFormatting: NSButton!;
    fileprivate var showEmoticons: NSButton!;
    fileprivate var spellchecking: NSButton!;
    
    fileprivate var encryptionButton: NSPopUpButton!;
    
    override func viewDidLoad() {
        if #available(macOS 10.14, *) {
            appearance = formView.addRow(label: "Appearance:", field: NSPopUpButton(frame: .zero, pullsDown: false));
            appearance?.target = self;
            appearance?.action = #selector(checkboxChanged(_:));
            formView.groupItems(from: appearance!, to: appearance!);
        }
        autoconnect = formView.addRow(label: "Account status:", field: NSButton(checkboxWithTitle: "Connect after start", target: self, action: #selector(checkboxChanged)))
        automaticStatus = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Automatic status", target: self, action: #selector(checkboxChanged)));
        rememberLastStatusButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Remember last status", target: self, action: #selector(checkboxChanged)));
        formView.groupItems(from: autoconnect, to: rememberLastStatusButton);
        
        enableMessageCarbonsButton = formView.addRow(label: "Message carbons:", field: NSButton(checkboxWithTitle: "Enable", target: self, action: #selector(checkboxChanged(_:))));
        messageCarbonsMarkAsReadButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Mark carbon messages as read", target: self, action: #selector(checkboxChanged(_:))));
        messageCarbonsMarkDeliveredToOtherResourceAsRead = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Mark messages confirmed as delivered to another client as read", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: enableMessageCarbonsButton, to: messageCarbonsMarkDeliveredToOtherResourceAsRead);
        
        encryptionButton = formView.addRow(label: "Default encryption:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        encryptionButton?.target = self;
        encryptionButton?.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: encryptionButton, to: encryptionButton);
        
        notificationsFromUnknownSenders = formView.addRow(label: "Notifications:", field: NSButton(checkboxWithTitle: "Show for messages from unknown senders", target: self, action: #selector(checkboxChanged(_:))));
        systemMenuIcon = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Show system menu icon", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: notificationsFromUnknownSenders, to: systemMenuIcon);
        
        markdownFormatting = formView.addRow(label: "Message formatting:", field: NSButton(checkboxWithTitle: "Markdown", target: self, action: #selector(checkboxChanged(_:))));
        showEmoticons = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Show emoticons", target: self, action: #selector(checkboxChanged(_:))))
        spellchecking = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Spellchecking", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from:markdownFormatting, to: spellchecking);
        
        _ = formView.addRow(label: "XMPP URI", field: NSButton(title: "Set as default app", target: self, action: #selector(showSetAsDefaultWindow)));
        
        self.preferredContentSize = NSSize(width: self.view.frame.size.width, height: self.view.frame.size.height);
    }
    
    override func viewWillAppear() {
        if #available(macOS 10.14, *) {
            appearance?.removeAllItems();
            appearance?.addItems(withTitles: ["Automatic", "Light", "Dark"]);
            switch Appearance(rawValue: Settings.appearance.string() ?? "auto")! {
            case .auto:
                appearance?.selectItem(at: 0);
            case .light:
                appearance?.selectItem(at: 1);
            case .dark:
                appearance?.selectItem(at: 2);
            }
        }

        autoconnect.state = Settings.automaticallyConnectAfterStart.bool() ? .on : .off;
        automaticStatus.state = Settings.enableAutomaticStatus.bool() ? .on : .off;
        rememberLastStatusButton.state = Settings.rememberLastStatus.bool() ? .on : .off;
        enableMessageCarbonsButton.state = Settings.enableMessageCarbons.bool() ? .on : .off;
        messageCarbonsMarkAsReadButton.state = Settings.markMessageCarbonsAsRead.bool() ? .on : .off;
        messageCarbonsMarkAsReadButton.isEnabled = Settings.enableMessageCarbons.bool();
        messageCarbonsMarkDeliveredToOtherResourceAsRead.state = Settings.markMessageDeliveredToOtherResourceAsRead.bool() ? .on : .off;
        messageCarbonsMarkDeliveredToOtherResourceAsRead.isEnabled = Settings.enableMessageCarbons.bool();
        notificationsFromUnknownSenders.state = Settings.notificationsFromUnknownSenders.bool() ? .on : .off;
        markdownFormatting.state = Settings.enableMarkdownFormatting.bool() ? .on : .off;
        showEmoticons.state = Settings.showEmoticons.bool() ? .on : .off;
        showEmoticons.isEnabled = Settings.enableMarkdownFormatting.bool()
        systemMenuIcon.state = Settings.systemMenuIcon.bool() ? .on : .off;
        spellchecking.state = Settings.spellchecking.bool() ? .on : .off;
        
        encryptionButton.removeAllItems();
        encryptionButton.addItems(withTitles: ["None", "OMEMO"]);
        encryptionButton.selectItem(at: ChatEncryption(rawValue: Settings.messageEncryption.string() ?? "none") == ChatEncryption.omemo ? 1 : 0);
    }
    
    @objc func checkboxChanged(_ sender: NSButton) {
        switch sender {
        case autoconnect:
            Settings.automaticallyConnectAfterStart.set(value: sender.state == .on);
        case automaticStatus:
            Settings.enableAutomaticStatus.set(value: sender.state == .on);
        case rememberLastStatusButton:
            Settings.rememberLastStatus.set(value: sender.state == .on);
            if Settings.rememberLastStatus.bool() {
                Settings.currentStatus.set(value: XmppService.instance.status);
            } else {
                Settings.currentStatus.set(value: nil);
            }
        case enableMessageCarbonsButton:
            Settings.enableMessageCarbons.set(value: sender.state == .on);
            messageCarbonsMarkAsReadButton.isEnabled = sender.state == .on;
            messageCarbonsMarkDeliveredToOtherResourceAsRead.isEnabled = sender.state == .on;
        case messageCarbonsMarkAsReadButton:
            Settings.markMessageCarbonsAsRead.set(value: sender.state == .on);
        case messageCarbonsMarkDeliveredToOtherResourceAsRead:
            Settings.markMessageDeliveredToOtherResourceAsRead.set(value: sender.state == .on);
        case notificationsFromUnknownSenders:
            Settings.notificationsFromUnknownSenders.set(value: sender.state == .on);
        case systemMenuIcon:
            Settings.systemMenuIcon.set(value: sender.state == .on);
        case markdownFormatting:
            Settings.enableMarkdownFormatting.set(value: sender.state == .on);
            showEmoticons.isEnabled = sender.state == .on;
        case spellchecking:
            Settings.spellchecking.set(value: sender.state == .on);
        case showEmoticons:
            Settings.showEmoticons.set(value: sender.state == .on);
        case encryptionButton:
            let encryption: ChatEncryption = encryptionButton.indexOfSelectedItem == 1 ? .omemo : .none;
            Settings.messageEncryption.set(value: encryption.rawValue);
        default:
            if #available(macOS 10.14, *) {
                if let appearance = self.appearance, appearance == sender {
                    let idx = appearance.indexOfSelectedItem;
                    let app: Appearance = idx == 1 ? .light : (idx == 2 ? .dark : .auto);
                    Settings.appearance.set(value: app.rawValue);
                }
            }
            break;
        }
    }
    
    @objc func sliderChanged(_ sender: NSSlider) {
        switch sender {
        default:
            break;
        }
    }
    
    @objc func showSetAsDefaultWindow(_ sender: Any) {
        NSWorkspace.shared.open(URL(string: "https://github.com/tigase/beagle-im/wiki/Default-application")!);
    }
}
