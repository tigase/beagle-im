//
// AdvancedController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class AdvancedSettingsController: NSViewController {
    
    @IBOutlet var formView: FormView!;

    fileprivate var alternateMessageColoringBasedOnDirection: NSButton!;
    fileprivate var messageGrouping: NSPopUpButton!;
    
    fileprivate var requestSubscriptionButton: NSButton!;
    fileprivate var allowSubscriptionButton: NSButton!;
    
    fileprivate var imagePreviewMaxSizeLabel: NSTextField!;
    fileprivate var imagePreviewMaxSize: NSSlider!;
    
    fileprivate var ignoreJingleSupportCheck: NSButton!;
    fileprivate var enableBookmarksSync: NSButton!;

    
    override func viewDidLoad() {
        messageGrouping = formView.addRow(label: "Message grouping:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        messageGrouping.target = self;
        messageGrouping.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: messageGrouping, to: messageGrouping);
        
        alternateMessageColoringBasedOnDirection = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Alternate colors for incoming/outgoing messages", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: alternateMessageColoringBasedOnDirection, to: alternateMessageColoringBasedOnDirection);
        
        requestSubscriptionButton = formView.addRow(label: "Adding user:", field: NSButton(checkboxWithTitle: "Request presence subscription", target: self, action: #selector(checkboxChanged)));
        allowSubscriptionButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Allow presence subscription", target: self, action: #selector(checkboxChanged)));
        formView.groupItems(from: requestSubscriptionButton, to: allowSubscriptionButton);
        
        imagePreviewMaxSize = formView.addRow(label: "Image preview size limit:", field: NSSlider(value: Double(Settings.imageDownloadSizeLimit.integer()), minValue: 0, maxValue: 50 * 1024 * 1024, target: self, action: #selector(sliderChanged)));
        imagePreviewMaxSizeLabel = formView.addRow(label: "", field: formView.createLabel(text: "0.0B"));
        imagePreviewMaxSizeLabel.alignment = .center;
        formView.groupItems(from:imagePreviewMaxSize, to: imagePreviewMaxSizeLabel);
        updateImagePreviewMaxSizeLabel();
        formView.cell(for: imagePreviewMaxSizeLabel)!.xPlacement = .center;
        
        ignoreJingleSupportCheck = formView.addRow(label: "Experimental", field: NSButton(checkboxWithTitle: "Ignore VoIP support check", target: self, action: #selector(checkboxChanged(_:))));
        
        enableBookmarksSync = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Enable groupchat bookmarks sync", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from:ignoreJingleSupportCheck, to: enableBookmarksSync);
        
        self.preferredContentSize = NSSize(width: self.view.frame.size.width, height: self.view.frame.size.height);
    }
    
    override func viewWillAppear() {
        messageGrouping.removeAllItems();
        messageGrouping.addItems(withTitles: ["None", "Smart", "Always"]);
        switch Settings.messageGrouping.string() {
        case "none":
            messageGrouping?.selectItem(at: 0);
        case "always":
            messageGrouping?.selectItem(at: 2);
        default:
            messageGrouping?.selectItem(at: 1);
        }
        alternateMessageColoringBasedOnDirection.state = Settings.alternateMessageColoringBasedOnDirection.bool() ? .on : .off;
        requestSubscriptionButton.state = Settings.requestPresenceSubscription.bool() ? .on : .off;
        allowSubscriptionButton.state = Settings.allowPresenceSubscription.bool() ? .on : .off;
        ignoreJingleSupportCheck.state = Settings.ignoreJingleSupportCheck.bool() ? .on : .off;
        enableBookmarksSync.state = Settings.enableBookmarksSync.bool() ? .on : .off;
    }
    
    @objc func checkboxChanged(_ sender: NSButton) {
        switch sender {
        case messageGrouping:
            switch messageGrouping.indexOfSelectedItem {
            case 0:
                Settings.messageGrouping.set(value: "none");
            case 1:
                Settings.messageGrouping.set(value: "smart");
            case 2:
                Settings.messageGrouping.set(value: "always");
            default:
                Settings.messageGrouping.set(value: "smart");
            }
        case alternateMessageColoringBasedOnDirection:
            Settings.alternateMessageColoringBasedOnDirection.set(value: sender.state == .on);
        case requestSubscriptionButton:
            Settings.requestPresenceSubscription.set(value: sender.state == .on);
        case allowSubscriptionButton:
            Settings.allowPresenceSubscription.set(value: sender.state == .on);
        case ignoreJingleSupportCheck:
            Settings.ignoreJingleSupportCheck.set(value: sender.state == .on);
        case enableBookmarksSync:
            Settings.enableBookmarksSync.set(value: sender.state == .on);
        default:
            break;
        }
    }
    
    @objc func sliderChanged(_ sender: NSSlider) {
        switch sender {
        case imagePreviewMaxSize:
            print("selected value:", sender.integerValue);
            Settings.imageDownloadSizeLimit.set(value: sender.integerValue);
            updateImagePreviewMaxSizeLabel();
            break;
        default:
            break;
        }
    }
    
    fileprivate func updateImagePreviewMaxSizeLabel() {
        self.imagePreviewMaxSizeLabel.stringValue = "\(string(filesize: Settings.imageDownloadSizeLimit.integer()))";
    }
    
    fileprivate func string(filesize: Int) -> String {
        var unit = "B";
        var val = Double(filesize) / 1024.0;
        if val > 0 {
            unit = "KB";
            if val > 1024 {
                val = val / 1024;
                unit = "MB";
            }
        } else {
            val = Double(filesize);
        }
        return String(format: "%.1f\(unit)", val);
    }
}
