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
import Combine

class AdvancedSettingsController: NSViewController {
    
    @IBOutlet var formView: FormView!;

    fileprivate var alternateMessageColoringBasedOnDirection: NSButton!;
    fileprivate var messageGrouping: NSPopUpButton!;
        
    fileprivate var imagePreviewMaxSizeLabel: NSTextField!;
    fileprivate var imagePreviewMaxSize: NSSlider!;
    
    fileprivate var confirmMessages: NSButton!;
    fileprivate var ignoreJingleSupportCheck: NSButton!;
    fileprivate var usePublicStunServers: NSButton!;
    fileprivate var enableBookmarksSync: NSButton!;

    fileprivate var markKeywords: NSButton!;
    fileprivate var markKeywordsWithBold: NSButton!;
    fileprivate var editKeywords: NSButton!;
    
    fileprivate var showAdvancedXmppFeatures: NSButton!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        messageGrouping = formView.addRow(label: NSLocalizedString("Message grouping", comment: "settings") + ":", field: NSPopUpButton(frame: .zero, pullsDown: false));
        messageGrouping.target = self;
        messageGrouping.action = #selector(checkboxChanged(_:));
        formView.groupItems(from: messageGrouping, to: messageGrouping);
        
        alternateMessageColoringBasedOnDirection = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Alternate colors for incoming/outgoing messages", comment: "settings"), target: self, action: #selector(checkboxChanged(_:))));
        formView.groupItems(from: alternateMessageColoringBasedOnDirection, to: alternateMessageColoringBasedOnDirection);
        
        markKeywords = formView.addRow(label: NSLocalizedString("Keywords", comment: "settings"), field: NSButton(checkboxWithTitle: NSLocalizedString("Enabled", comment: "settings"), target: self, action: #selector(checkboxChanged)));
        markKeywordsWithBold = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Make them bold", comment: "settings"), target: self, action: #selector(checkboxChanged)));
        editKeywords = formView.addRow(label: "", field: NSButton(title: NSLocalizedString("Edit keywords", comment: "settings"), target: self, action: #selector(editKeywordsClicked)));
        formView.groupItems(from: markKeywords, to: editKeywords);
        
        imagePreviewMaxSize = formView.addRow(label: NSLocalizedString("Automatic download size limit", comment: "settings"), field: NSSlider(value: Double(Settings.fileDownloadSizeLimit), minValue: 0, maxValue: 50 * 1024 * 1024, target: self, action: #selector(sliderChanged)));
        imagePreviewMaxSizeLabel = formView.addRow(label: "", field: formView.createLabel(text: "0.0B"));
        imagePreviewMaxSizeLabel.alignment = .center;
        formView.groupItems(from:imagePreviewMaxSize, to: imagePreviewMaxSizeLabel);
        formView.cell(for: imagePreviewMaxSizeLabel)!.xPlacement = .center;
        
        confirmMessages = formView.addRow(label: NSLocalizedString("Experimental", comment: "settings"), field: NSButton(checkboxWithTitle: NSLocalizedString("Confirm messages", comment: "settings"), target: self, action: #selector(checkboxChanged(_:))));
        confirmMessages.toolTip = NSLocalizedString("Let your contacts know when you have received and read their messages. Disabling will disable syncing information about read messages between your devices!", comment: "settings");
        ignoreJingleSupportCheck = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Ignore VoIP support check", comment: "settings"), target: self, action: #selector(checkboxChanged(_:))));
        usePublicStunServers = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Use public STUN servers", comment: "settings"), target: self, action: #selector(checkboxChanged(_:))));
        enableBookmarksSync = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Enable groupchat bookmarks sync", comment: "settings"), target: self, action: #selector(checkboxChanged(_:))));
        showAdvancedXmppFeatures = formView.addRow(label: "", field: NSButton(checkboxWithTitle: NSLocalizedString("Show advanced XMPP features", comment: "settings"), target: self, action: #selector(checkboxChanged(_:))));
        
        let logsDir = formView.addRow(label: "", field: NSButton(title: NSLocalizedString("Open logs directory", comment: "settings"), target: self, action: #selector(openLogsDirectory)));
        formView.groupItems(from:confirmMessages, to: logsDir);

        Settings.$fileDownloadSizeLimit.sink(receiveValue: { [weak self] value in
            guard let that = self else {
                return;
            }
            self?.imagePreviewMaxSizeLabel.stringValue = "\(that.string(filesize: value))"
        }).store(in: &cancellables);
        
        self.preferredContentSize = NSSize(width: self.view.frame.size.width, height: self.view.frame.size.height);
    }
    
    override func viewWillAppear() {
        messageGrouping.removeAllItems();
        messageGrouping.addItems(withTitles: [NSLocalizedString("Never", comment: "settings"), NSLocalizedString("Smart", comment: "settings"), NSLocalizedString("Always", comment: "settings")]);
        switch Settings.messageGrouping {
        case .none:
            messageGrouping?.selectItem(at: 0);
        case .always:
            messageGrouping?.selectItem(at: 2);
        case .smart:
            messageGrouping?.selectItem(at: 1);
        }
        alternateMessageColoringBasedOnDirection.state = Settings.alternateMessageColoringBasedOnDirection ? .on : .off;
        Settings.$confirmMessages.receive(on: DispatchQueue.main).map({ $0 ? .on : .off }).assign(to: \.state, on: confirmMessages).store(in: &cancellables);
        confirmMessages.state = Settings.confirmMessages ? .on : .off;
        ignoreJingleSupportCheck.state = Settings.ignoreJingleSupportCheck ? .on : .off;
        usePublicStunServers.state = Settings.usePublicStunServers ? .on : .off;
        enableBookmarksSync.state = Settings.enableBookmarksSync ? .on : .off;
        let keywords = Settings.markKeywords;
        markKeywords.state = !keywords.isEmpty ? .on : .off;
        markKeywordsWithBold.state = Settings.boldKeywords ? .on : .off;
        markKeywordsWithBold.isEnabled = markKeywords.state == .on;
        editKeywords.isEnabled = markKeywords.state == .on;
        showAdvancedXmppFeatures.state = Settings.showAdvancedXmppFeatures ? .on : .off;
    }
    
    @objc func openLogsDirectory(_ sender: NSButton) {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FileManager.default.temporaryDirectory.path);
    }
    
    @objc func checkboxChanged(_ sender: NSButton) {
        switch sender {
        case messageGrouping:
            switch messageGrouping.indexOfSelectedItem {
            case 0:
                Settings.messageGrouping = .none
            case 1:
                Settings.messageGrouping = .smart
            case 2:
                Settings.messageGrouping = .always;
            default:
                Settings.messageGrouping = .smart;
            }
        case alternateMessageColoringBasedOnDirection:
            Settings.alternateMessageColoringBasedOnDirection = sender.state == .on;
        case confirmMessages:
            Settings.confirmMessages = sender.state == .on;
        case ignoreJingleSupportCheck:
            Settings.ignoreJingleSupportCheck = sender.state == .on;
        case usePublicStunServers:
            Settings.usePublicStunServers = sender.state == .on;
        case enableBookmarksSync:
            Settings.enableBookmarksSync = sender.state == .on;
        case markKeywords:
            markKeywordsWithBold.isEnabled = sender.state == .on;
            editKeywords.isEnabled = markKeywords.state == .on;
        case markKeywordsWithBold:
            Settings.boldKeywords = sender.state == .on;
        case showAdvancedXmppFeatures:
            Settings.showAdvancedXmppFeatures = sender.state == .on;
        default:
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
            Settings.fileDownloadSizeLimit = sender.integerValue;
            break;
        default:
            break;
        }
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
