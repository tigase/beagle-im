//
//  GeneralSettingsController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 15.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class GeneralSettingsController: NSViewController {
    
    @IBOutlet var formView: FormView!;
    
    fileprivate var appearance: NSPopUpButton?;
    fileprivate var autoconnect: NSButton!;
    fileprivate var automaticStatus: NSButton!;
    fileprivate var rememberLastStatusButton: NSButton!;
    fileprivate var requestSubscriptionButton: NSButton!;
    fileprivate var allowSubscriptionButton: NSButton!;
    
    fileprivate var enableMessageCarbonsButton: NSButton!;
    fileprivate var messageCarbonsMarkAsReadButton: NSButton!;
    
    fileprivate var notificationsFromUnknownSenders: NSButton!;
    fileprivate var systemMenuIcon: NSButton!;
    
    fileprivate var markdownFormatting: NSButton!;
    fileprivate var spellchecking: NSButton!;
    
    override func viewDidLoad() {
        if #available(macOS 10.14, *) {
            appearance = formView.addRow(label: "Appearance:", field: NSPopUpButton(frame: .zero, pullsDown: false));
            appearance?.target = self;
            appearance?.action = #selector(checkboxChanged(_:));
        }
        autoconnect = formView.addRow(label: "Account status:", field: NSButton(checkboxWithTitle: "Connect after start", target: self, action: #selector(checkboxChanged)))
        automaticStatus = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Automatic status", target: self, action: #selector(checkboxChanged)));
        rememberLastStatusButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Remember last status", target: self, action: #selector(checkboxChanged)));

        requestSubscriptionButton = formView.addRow(label: "Adding user:", field: NSButton(checkboxWithTitle: "Request presence subscription", target: self, action: #selector(checkboxChanged)));
        allowSubscriptionButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Allow presence subscription", target: self, action: #selector(checkboxChanged)));
        
        enableMessageCarbonsButton = formView.addRow(label: "Message carbons:", field: NSButton(checkboxWithTitle: "Enable", target: self, action: #selector(checkboxChanged(_:))));
        messageCarbonsMarkAsReadButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Mark carbon messages as read", target: self, action: #selector(checkboxChanged(_:))));
        
        notificationsFromUnknownSenders = formView.addRow(label: "Notifications:", field: NSButton(checkboxWithTitle: "Show for messages from unknown senders", target: self, action: #selector(checkboxChanged(_:))));
        systemMenuIcon = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Show system menu icon", target: self, action: #selector(checkboxChanged(_:))));
        
        markdownFormatting = formView.addRow(label: "Message formatting:", field: NSButton(checkboxWithTitle: "Markdown", target: self, action: #selector(checkboxChanged(_:))));
        
        spellchecking = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Spellchecking", target: self, action: #selector(checkboxChanged(_:))));
        
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
        requestSubscriptionButton.state = Settings.requestPresenceSubscription.bool() ? .on : .off;
        allowSubscriptionButton.state = Settings.allowPresenceSubscription.bool() ? .on : .off;
        enableMessageCarbonsButton.state = Settings.enableMessageCarbons.bool() ? .on : .off;
        messageCarbonsMarkAsReadButton.state = Settings.markMessageCarbonsAsRead.bool() ? .on : .off;
        messageCarbonsMarkAsReadButton.isEnabled = Settings.enableMessageCarbons.bool();
        notificationsFromUnknownSenders.state = Settings.notificationsFromUnknownSenders.bool() ? .on : .off;
        markdownFormatting.state = Settings.enableMarkdownFormatting.bool() ? .on : .off;
        systemMenuIcon.state = Settings.systemMenuIcon.bool() ? .on : .off;
        spellchecking.state = Settings.spellchecking.bool() ? .on : .off;
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
        case requestSubscriptionButton:
            Settings.requestPresenceSubscription.set(value: sender.state == .on);
        case allowSubscriptionButton:
            Settings.allowPresenceSubscription.set(value: sender.state == .on);
        case enableMessageCarbonsButton:
            Settings.enableMessageCarbons.set(value: sender.state == .on);
            messageCarbonsMarkAsReadButton.isEnabled = sender.state == .on;
        case messageCarbonsMarkAsReadButton:
            Settings.markMessageCarbonsAsRead.set(value: sender.state == .on);
        case notificationsFromUnknownSenders:
            Settings.notificationsFromUnknownSenders.set(value: sender.state == .on);
        case systemMenuIcon:
            Settings.systemMenuIcon.set(value: sender.state == .on);
        case markdownFormatting:
            Settings.enableMarkdownFormatting.set(value: sender.state == .on);
        case spellchecking:
            Settings.spellchecking.set(value: sender.state == .on);
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
    
}
