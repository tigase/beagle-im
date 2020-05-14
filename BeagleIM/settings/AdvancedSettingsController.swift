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
    fileprivate var enableLinkPreviews: NSButton?;

    fileprivate var markKeywords: NSButton!;
    fileprivate var markKeywordsWithBold: NSButton!;
    fileprivate var editKeywords: NSButton!;
    
    fileprivate var commonChatsList: NSButton!;
    
    override func viewDidLoad() {
        messageGrouping = formView.addRow(label: "Message grouping:", field: NSPopUpButton(frame: .zero, pullsDown: false));
        messageGrouping.target = self;
        messageGrouping.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: messageGrouping, to: messageGrouping);
        
        alternateMessageColoringBasedOnDirection = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Alternate colors for incoming/outgoing messages", target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: alternateMessageColoringBasedOnDirection, to: alternateMessageColoringBasedOnDirection);
        
        markKeywords = formView.addRow(label: "Keywords", field: NSButton(checkboxWithTitle: "Enabled", target: self, action: #selector(checkboxChanged)));
        markKeywordsWithBold = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Make them bold", target: self, action: #selector(checkboxChanged)));
        editKeywords = formView.addRow(label: "", field: NSButton(title: "Edit keywords", target: self, action: #selector(editKeywordsClicked)));
        formView.groupItems(from: markKeywords, to: editKeywords);

        requestSubscriptionButton = formView.addRow(label: "Adding user:", field: NSButton(checkboxWithTitle: "Request presence subscription", target: self, action: #selector(checkboxChanged)));
        allowSubscriptionButton = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Allow presence subscription", target: self, action: #selector(checkboxChanged)));
        formView.groupItems(from: requestSubscriptionButton, to: allowSubscriptionButton);
        
        imagePreviewMaxSize = formView.addRow(label: "Automatic download size limit:", field: NSSlider(value: Double(Settings.fileDownloadSizeLimit.integer()), minValue: 0, maxValue: 50 * 1024 * 1024, target: self, action: #selector(sliderChanged)));
        imagePreviewMaxSizeLabel = formView.addRow(label: "", field: formView.createLabel(text: "0.0B"));
        imagePreviewMaxSizeLabel.alignment = .center;
        formView.groupItems(from:imagePreviewMaxSize, to: imagePreviewMaxSizeLabel);
        updateFileDownloadMaxSizeLabel();
        formView.cell(for: imagePreviewMaxSizeLabel)!.xPlacement = .center;
        
        ignoreJingleSupportCheck = formView.addRow(label: "Experimental", field: NSButton(checkboxWithTitle: "Ignore VoIP support check", target: self, action: #selector(checkboxChanged(_:))));
        
        enableBookmarksSync = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Enable groupchat bookmarks sync", target: self, action: #selector(checkboxChanged(_:))));
        if #available(macOS 10.15, *) {
            enableLinkPreviews = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Enable link previews", target: self, action: #selector(checkboxChanged(_:))));
        }
        commonChatsList = formView.addRow(label: "", field: NSButton(checkboxWithTitle: "Show channels and chats in merged list", target: self, action: #selector(checkboxChanged(_:))));
        
        let logsDir = formView.addRow(label: "", field: NSButton(title: "Open logs directory", target: self, action: #selector(openLogsDirectory)));
        formView.groupItems(from:ignoreJingleSupportCheck, to: logsDir);

        
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
        if #available(macOS 10.15, *) {
            enableLinkPreviews?.state = Settings.linkPreviews.bool() ? .on : .off;
        }
        let keywords = Settings.markKeywords.stringArrays();
        markKeywords.state = keywords != nil ? .on : .off;
        markKeywordsWithBold.state = Settings.boldKeywords.bool() ? .on : .off;
        markKeywordsWithBold.isEnabled = markKeywords.state == .on;
        editKeywords.isEnabled = markKeywords.state == .on;
        commonChatsList.state = Settings.commonChatsList.bool() ? .on : .off;
    }
    
    @objc func openLogsDirectory(_ sender: NSButton) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FileManager.default.temporaryDirectory.path);
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
        case markKeywords:
            Settings.markKeywords.set(values: (sender.state == .on ? [] : nil) as [String]?);
            markKeywordsWithBold.isEnabled = sender.state == .on;
            editKeywords.isEnabled = markKeywords.state == .on;
        case markKeywordsWithBold:
            Settings.boldKeywords.set(value: sender.state == .on);
        case commonChatsList:
            Settings.commonChatsList.set(value: sender.state == .on);
        default:
            if #available(macOS 10.15, *) {
                if let linkPreviews = enableLinkPreviews, sender == linkPreviews {
                    Settings.linkPreviews.set(value: sender.state == .on);
                }
            }
            break;
        }
    }
    
    @objc func editKeywordsClicked(_ sender: NSButton) {
        guard let editKeywordsController = NSStoryboard(name: "Settings", bundle: nil).instantiateController(withIdentifier: "EditKeywordsController") as? NSViewController else {
            return;
        }
        self.presentAsSheet(editKeywordsController);
    }
    
//    @objc func keywordsChanged(_ sender: NSTextField) {
//        let keywords = sender.stringValue.split(separator: ",").map({ x -> String in String(x).trimmingCharacters(in: .whitespacesAndNewlines)}).filter({ s -> Bool in !s.isEmpty});
//        Settings.markKeywords.set(values: keywords);
//    }
//
    @objc func sliderChanged(_ sender: NSSlider) {
        switch sender {
        case imagePreviewMaxSize:
            print("selected value:", sender.integerValue);
            Settings.fileDownloadSizeLimit.set(value: sender.integerValue);
            updateFileDownloadMaxSizeLabel();
            break;
        default:
            break;
        }
    }
    
    fileprivate func updateFileDownloadMaxSizeLabel() {
        self.imagePreviewMaxSizeLabel.stringValue = "\(string(filesize: Settings.fileDownloadSizeLimit.integer()))";
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
