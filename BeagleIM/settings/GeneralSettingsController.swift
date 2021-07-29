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
    
    fileprivate var enableLinkPreviews: NSButton!;
    fileprivate var commonChatsList: NSButton!;
    private var chatslistStyle: NSPopUpButton!;

    let appearanceOptions: [Appearance] = [.auto, .light, .dark];
    let chatslistStyleOptions: [ChatsListStyle] = [.minimal, .small, .large];
    let imageQualityOptions: [ImageQuality] = [.original,.highest,.high,.medium,.low];
    let videoQualityOptions: [VideoQuality] = [.original,.high,.medium,.low];

    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        appearance = formView.addRow(label: NSLocalizedString("Appearance", comment: "setting") + ":", field: NSPopUpButton(frame: .zero, pullsDown: false));
        appearance.target = self;
        appearance.action = #selector(checkboxChanged(_:));
        commonChatsList = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Show channels and chats in merged list", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: appearance!, to: commonChatsList!);
                
        chatslistStyle = formView.addRow(label: NSLocalizedString("Chats list style", comment: "setting") + ":", field: NSPopUpButton(frame: .zero, pullsDown: false));
        chatslistStyle.target = self;
        chatslistStyle.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: chatslistStyle!, to: chatslistStyle!);

        encryptionButton = formView.addRow(label: NSLocalizedString("Default encryption", comment: "setting") + ":", field: NSPopUpButton(frame: .zero, pullsDown: false));
        encryptionButton?.target = self;
        encryptionButton?.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: encryptionButton, to: encryptionButton);
        
        notificationsFromUnknownSenders = formView.addRow(label: NSLocalizedString("Notifications", comment: "setting") + ":", field: NSButton(checkboxWithTitle: NSLocalizedString("Show for messages from unknown senders", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))));
        systemMenuIcon = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Show system menu icon", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: notificationsFromUnknownSenders, to: systemMenuIcon);
        
        markdownFormatting = formView.addRow(label: NSLocalizedString("Message formatting", comment: "setting") + ":", field: NSButton(checkboxWithTitle: NSLocalizedString("Markdown", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))));
        showEmoticons = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Show emoticons", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))))
        Settings.$enableMarkdownFormatting.assign(to: \.isEnabled, on: showEmoticons).store(in: &cancellables)
        spellchecking = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Spellchecking", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))));
        enableLinkPreviews = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Enable link previews", comment: "setting"), target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from:markdownFormatting, to: enableLinkPreviews!);
        
        imageQuality = formView.addRow(label: NSLocalizedString("Sent images quality", comment: "setting") + ":", field: NSPopUpButton(frame: .zero, pullsDown: false));
        imageQuality.target = self;
        imageQuality.action = #selector(checkboxChanged(_:));
        videoQuality = formView.addRow(label: NSLocalizedString("Sent videos quality", comment: "setting") + ":", field: NSPopUpButton(frame: .zero, pullsDown: false));
        videoQuality.target = self;
        videoQuality.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: imageQuality, to: videoQuality);

        _ = formView.addRow(label: NSLocalizedString("XMPP URI", comment: "setting") + ":", field: NSButton(title: NSLocalizedString("Set as default app", comment: "setting"), target: self, action: #selector(showSetAsDefaultWindow)));
        
        self.preferredContentSize = NSSize(width: self.view.frame.size.width, height: self.view.frame.size.height);
    }
    
    override func viewWillAppear() {
        appearance.removeAllItems();
        appearance.addItems(withTitles: [NSLocalizedString("Automatic", comment: "setting"), NSLocalizedString("Light", comment: "setting"), NSLocalizedString("Dark", comment: "setting")]);
        switch Settings.appearance {
        case .auto:
            appearance.selectItem(at: 0);
        case .light:
            appearance.selectItem(at: 1);
        case .dark:
            appearance.selectItem(at: 2);
        }

        chatslistStyle.removeAllItems();
        chatslistStyle.addItems(withTitles: [NSLocalizedString("Minimal", comment: "setting"), NSLocalizedString("Small", comment: "setting"), NSLocalizedString("Large", comment: "setting")]);
        switch Settings.chatslistStyle {
        case .minimal:
            chatslistStyle.selectItem(at: 0);
        case .small:
            chatslistStyle.selectItem(at: 1);
        case .large:
            chatslistStyle.selectItem(at: 2);
        }
        
        notificationsFromUnknownSenders.state = Settings.notificationsFromUnknownSenders ? .on : .off;
        markdownFormatting.state = Settings.enableMarkdownFormatting ? .on : .off;
        showEmoticons.state = Settings.showEmoticons ? .on : .off;
        systemMenuIcon.state = Settings.systemMenuIcon ? .on : .off;
        spellchecking.state = Settings.spellchecking ? .on : .off;
        
        enableLinkPreviews.state = Settings.linkPreviews ? .on : .off;
        commonChatsList.state = Settings.commonChatsList ? .on : .off;

        encryptionButton.removeAllItems();
        encryptionButton.addItems(withTitles: [NSLocalizedString("None", comment: "setting"), NSLocalizedString("OMEMO", comment: "setting")]);
        encryptionButton.selectItem(at: Settings.messageEncryption == .omemo ? 1 : 0);
        
        imageQuality.removeAllItems();
        imageQuality.addItems(withTitles: imageQualityOptions.map({ $0.label }));
        imageQuality.selectItem(at: imageQualityOptions.firstIndex(of: ImageQuality.current) ?? 0);
        videoQuality.removeAllItems();
        videoQuality.addItems(withTitles: videoQualityOptions.map({ $0.label }));
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
        case commonChatsList:
            Settings.commonChatsList = sender.state == .on;
        case enableLinkPreviews:
            Settings.linkPreviews = sender.state == .on;
        case chatslistStyle:
            Settings.chatslistStyle = self.chatslistStyleOptions[chatslistStyle.indexOfSelectedItem];
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
