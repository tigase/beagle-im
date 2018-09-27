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
    
    fileprivate var autoconnect: NSButton!;
    fileprivate var rememberLastStatusButton: NSButton!;
    fileprivate var requestSubscriptionButton: NSButton!;
    fileprivate var allowSubscriptionButton: NSButton!;
    
    fileprivate var enableMessageCarbonsButton: NSButton!;
    fileprivate var messageCarbonsMarkAsReadButton: NSButton!;
    
    override func viewDidLoad() {
        autoconnect = formView.addRow(label: "Account status:", field: NSButton(checkboxWithTitle: "Connect after start", target: self, action: #selector(checkboxChanged)))
        rememberLastStatusButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Remember last status", target: self, action: #selector(checkboxChanged)));
        _ = formView.addRow(label: "", field: NSTextField(labelWithString: ""));
        requestSubscriptionButton = formView.addRow(label: "Adding user:", field: NSButton(checkboxWithTitle: "Request presence subscription", target: self, action: #selector(checkboxChanged)));
        allowSubscriptionButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Allow presence subscription", target: self, action: #selector(checkboxChanged)));
        
        _ = formView.addRow(label: "", field: NSTextField(labelWithString: ""));
        
        enableMessageCarbonsButton = formView.addRow(label: "Message carbons:", field: NSButton(checkboxWithTitle: "Enable", target: self, action: #selector(checkboxChanged(_:))));
        messageCarbonsMarkAsReadButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Mark carbon messages as read", target: self, action: #selector(checkboxChanged(_:))));
    }
    
    override func viewWillAppear() {
        autoconnect.state = Settings.automaticallyConnectAfterStart.bool() ? .on : .off;
        rememberLastStatusButton.state = Settings.rememberLastStatus.bool() ? .on : .off;
        requestSubscriptionButton.state = Settings.requestPresenceSubscription.bool() ? .on : .off;
        allowSubscriptionButton.state = Settings.allowPresenceSubscription.bool() ? .on : .off;
        enableMessageCarbonsButton.state = Settings.enableMessageCarbons.bool() ? .on : .off;
        messageCarbonsMarkAsReadButton.state = Settings.markMessageCarbonsAsRead.bool() ? .on : .off;
        messageCarbonsMarkAsReadButton.isEnabled = Settings.enableMessageCarbons.bool();
    }
    
    @objc func checkboxChanged(_ sender: NSButton) {
        switch sender {
        case autoconnect:
            Settings.automaticallyConnectAfterStart.set(value: sender.state == .on);
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
        default:
            break;
        }
    }
    
}
