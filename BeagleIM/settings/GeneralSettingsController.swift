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
import Combine

class GeneralSettingsController: NSViewController {
    
    @IBOutlet var formView: FormView!;
    
    fileprivate var appearance: NSPopUpButton!;
    
    fileprivate var notificationsFromUnknownSenders: NSButton!;
    fileprivate var systemMenuIcon: NSButton!;
    
    fileprivate var markdownFormatting: NSButton!;
    fileprivate var showEmoticons: NSButton!;
    fileprivate var spellchecking: NSButton!;
    
    fileprivate var encryptionButton: NSPopUpButton!;
    
    private var imageQuality: NSPopUpButton!;
    private var videoQuality: NSPopUpButton!;
    
    let appearanceOptions: [Appearance] = [.auto, .light, .dark];
    let imageQualityOptions: [ImageQuality] = [.original,.highest,.high,.medium,.low];
    let videoQualityOptions: [VideoQuality] = [.original,.high,.medium,.low];

    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        appearance = formView.addRow(label: "Appearance:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        appearance.target = self;
        appearance.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: appearance!, to: appearance!);
                
        encryptionButton = formView.addRow(label: "Default encryption:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        encryptionButton?.target = self;
        encryptionButton?.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: encryptionButton, to: encryptionButton);
        
        notificationsFromUnknownSenders = formView.addRow(label: "Notifications:", field: NSButton(checkboxWithTitle: "Show for messages from unknown senders", target: self, action: #selector(checkboxChanged(_:))));
        systemMenuIcon = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Show system menu icon", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: notificationsFromUnknownSenders, to: systemMenuIcon);
        
        markdownFormatting = formView.addRow(label: "Message formatting:", field: NSButton(checkboxWithTitle: "Markdown", target: self, action: #selector(checkboxChanged(_:))));
        showEmoticons = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Show emoticons", target: self, action: #selector(checkboxChanged(_:))))
        Settings.$enableMarkdownFormatting.assign(to: \.isEnabled, on: showEmoticons).store(in: &cancellables)
        spellchecking = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Spellchecking", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from:markdownFormatting, to: spellchecking);
        
        imageQuality = formView.addRow(label: "Sent images quality:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        imageQuality.target = self;
        imageQuality.action = #selector(checkboxChanged(_:));
        videoQuality = formView.addRow(label: "Sent videos quality:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        videoQuality.target = self;
        videoQuality.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: imageQuality, to: videoQuality);

        _ = formView.addRow(label: "XMPP URI", field: NSButton(title: "Set as default app", target: self, action: #selector(showSetAsDefaultWindow)));
        
        self.preferredContentSize = NSSize(width: self.view.frame.size.width, height: self.view.frame.size.height);
    }
    
    override func viewWillAppear() {
        appearance.removeAllItems();
        appearance.addItems(withTitles: ["Automatic", "Light", "Dark"]);
        switch Settings.appearance {
        case .auto:
            appearance.selectItem(at: 0);
        case .light:
            appearance.selectItem(at: 1);
        case .dark:
            appearance.selectItem(at: 2);
        }

        notificationsFromUnknownSenders.state = Settings.notificationsFromUnknownSenders ? .on : .off;
        markdownFormatting.state = Settings.enableMarkdownFormatting ? .on : .off;
        showEmoticons.state = Settings.showEmoticons ? .on : .off;
        systemMenuIcon.state = Settings.systemMenuIcon ? .on : .off;
        spellchecking.state = Settings.spellchecking ? .on : .off;
        
        encryptionButton.removeAllItems();
        encryptionButton.addItems(withTitles: ["None", "OMEMO"]);
        encryptionButton.selectItem(at: Settings.messageEncryption == .omemo ? 1 : 0);
        
        imageQuality.removeAllItems();
        imageQuality.addItems(withTitles: imageQualityOptions.map({ $0.rawValue.capitalized }));
        imageQuality.selectItem(at: imageQualityOptions.firstIndex(of: ImageQuality.current) ?? 0);
        videoQuality.removeAllItems();
        videoQuality.addItems(withTitles: videoQualityOptions.map({ $0.rawValue.capitalized }));
        videoQuality.selectItem(at: videoQualityOptions.firstIndex(of: VideoQuality.current) ?? 0);
    }
    
    @objc func checkboxChanged(_ sender: NSButton) {
        switch sender {
        case notificationsFromUnknownSenders:
            Settings.notificationsFromUnknownSenders = sender.state == .on;
        case systemMenuIcon:
            Settings.systemMenuIcon = sender.state == .on;
        case markdownFormatting:
            Settings.enableMarkdownFormatting = sender.state == .on;
            showEmoticons.isEnabled = sender.state == .on;
        case spellchecking:
            Settings.spellchecking = sender.state == .on;
        case showEmoticons:
            Settings.showEmoticons = sender.state == .on;
        case encryptionButton:
            let encryption: ChatEncryption = encryptionButton.indexOfSelectedItem == 1 ? .omemo : .none;
            Settings.messageEncryption = encryption;
        case imageQuality:
            Settings.imageQuality = imageQualityOptions[imageQuality.indexOfSelectedItem];
        case videoQuality:
            Settings.videoQuality = videoQualityOptions[videoQuality.indexOfSelectedItem];
        case appearance:
            Settings.appearance = self.appearanceOptions[appearance.indexOfSelectedItem];
        default:
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
