//
// AbstractChatViewControllerWithSharing.swift
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
import Martin
import Combine

class NSViewWithTextBackgroundAndDragHandler: NSViewWithTextBackground {
    
    weak var dragHandler: (NSDraggingDestination & PastingDelegate)? = nil;
    
    override func draggingEnded(_ sender: NSDraggingInfo) {
        guard let handler = self.dragHandler?.draggingEnded else {
            super.draggingEnded(sender);
            return;
        }
        handler(sender);
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let handler = self.dragHandler?.draggingEntered else {
            return super.draggingEntered(sender);
        }
        let res = handler(sender);
        if res == [] {
            return super.draggingEntered(sender);
        } else {
            return res;
        }
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let handler = self.dragHandler?.draggingUpdated else {
            return super.draggingUpdated(sender);
        }
        let res = handler(sender);
        if res == [] {
            return super.draggingUpdated(sender);
        } else {
            return res;
        }
    }
    
    override func draggingExited(_ sender: NSDraggingInfo?) {
        guard let handler = self.dragHandler?.draggingExited else {
            super.draggingExited(sender);
            return;
        }
        handler(sender);
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        return (dragHandler?.performDragOperation?(sender) ?? false) || super.performDragOperation(sender);
    }
}

class AbstractChatViewControllerWithSharing: AbstractChatViewController, URLSessionTaskDelegate, NSDraggingDestination, PastingDelegate {

    @IBOutlet var sharingProgressBar: NSProgressIndicator!;
    private(set) var sharingButton: NSButton!;
    private(set) var locationButton: NSButton!;
    private(set) var voiceMessageButton: NSButton!;
    private var voiceRecordingView: VoiceRecordingView?;
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();

        self.voiceMessageButton = NSButton(image: NSImage(named: "mic.circle")!, target: self, action: #selector(startRecordingVoiceMessage(_:)));
        self.voiceMessageButton.bezelStyle = .regularSquare;
        self.voiceMessageButton.isBordered = false;
        NSLayoutConstraint.activate([self.voiceMessageButton.widthAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2), self.voiceMessageButton.widthAnchor.constraint(equalTo: self.voiceMessageButton.heightAnchor)]);
        bottomView.addView(voiceMessageButton, in: .leading)
        self.voiceMessageButton.isEnabled = false;

        self.locationButton = NSButton(image: NSImage(named: "location.circle")!, target: self, action: #selector(attachLocation(_:)));
        self.locationButton.bezelStyle = .regularSquare;
        self.locationButton.isBordered = false;
        NSLayoutConstraint.activate([self.locationButton.widthAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2), self.locationButton.widthAnchor.constraint(equalTo: self.locationButton.heightAnchor)]);
        bottomView.addView(locationButton, in: .leading)
        self.locationButton.isEnabled = true;

        self.sharingButton = NSButton(image: NSImage(named: "plus.circle")!, target: self, action: #selector(attachFile(_:)));
        self.sharingButton.bezelStyle = .regularSquare;
        self.sharingButton.isBordered = false;
        NSLayoutConstraint.activate([self.sharingButton.widthAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2), self.sharingButton.widthAnchor.constraint(equalTo: self.sharingButton.heightAnchor)]);
        bottomView.addView(sharingButton, in: .leading)
        self.sharingButton.isEnabled = false;
        messageField.dragHandler = self;
        messageField.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) });
        self.sharingProgressBar.minValue = 0;
        self.sharingProgressBar.maxValue = 1;
        self.sharingProgressBar.isHidden = true;
        
        (self.view as! NSViewWithTextBackgroundAndDragHandler).dragHandler = self;
        self.view.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) });
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        conversation.featuresPublisher.receive(on: DispatchQueue.main).map({ $0.contains(.httpFileUpload) }).assign(to: \.isEnabled, on: self.sharingButton).store(in: &cancellables)
        conversation.featuresPublisher.combineLatest(CaptureDeviceManager.authorizationStatusPublisher(for: .audio), { features, media in
            return features.contains(.httpFileUpload) && (media == .authorized || media == .notDetermined);
        }).receive(on: DispatchQueue.main).assign(to: \.isEnabled, on: self.voiceMessageButton).store(in: &cancellables)
        (conversation as! ConversationBase).$fileUploadProgress.removeDuplicates().receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] progress in
            self?.updateSharing(progress: progress);
        }).store(in: &cancellables);
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear()
        self.cancellables.removeAll();
    }
        
    func updateSharing(progress value: Double) {
        self.sharingProgressBar.doubleValue = value;
        self.sharingProgressBar.isHidden = value == 1;
    }
    
    func paste(in textView: AutoresizingTextView, pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL], urls.allSatisfy({ $0.isFileURL }) else {
                return false;
            }

            let alert = NSAlert();
            alert.alertStyle = .informational;
            alert.icon = NSImage(named: NSImage.shareTemplateName);
            alert.messageText = NSLocalizedString("Sending files", comment: "Title of alert to confirm sending files");
            alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("You have pasted %d file(s). Do you wish to send them?", comment: "Alert confirm sending files message"), urls.count);
            alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Confirm sending files"));
            alert.addButton(withTitle: NSLocalizedString("No", comment: "Deny sending files"));
            alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                if response == .alertFirstButtonReturn {
                    Task {
                        do {
                            try await SharingTaskManager.instance.share(conversation: self.conversation, items: urls.map({ .url($0 as URL) }), quality: .default);
                        } catch {
                            SharingTaskManager.instance.show(error: error, window: self.view.window!);
                        }
                    }
                } else {
                    textView.pasteURLs(pasteboard);
                }
            })
            return true;
        }
        return false;
    }
    
    func draggingEnded(_ sender: NSDraggingInfo) {
        
    }
    
    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return sender.draggingSourceOperationMask.contains(.copy) && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self], options: nil) ? .copy : [];
    }
    
    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return sender.draggingSourceOperationMask.contains(.copy) && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self], options: nil) ? .copy : [];
    }
    
    func draggingExited(_ sender: NSDraggingInfo?) {
        
    }
    
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard sharingButton.isEnabled else {
            return false;
        }
        
        var items: [ShareItem] = [];
        sender.enumerateDraggingItems(options: [], for: nil, classes: [NSFilePromiseReceiver.self, NSURL.self], searchOptions: [.urlReadingFileURLsOnly: true]) { (item, _, _) in
            switch item.item {
            case let filePromiseReceived as NSFilePromiseReceiver:
                items.append(.promiseReceived(filePromiseReceived))
            case let fileUrl as URL:
                guard fileUrl.isFileURL else {
                    return;
                }
                items.append(.url(fileUrl))
            default:
                break;
            }
        }
        if !items.isEmpty {
            let askForQuality = NSEvent.modifierFlags.contains(.option);
            Task {
                do {
                    try await SharingTaskManager.instance.share(conversation: self.conversation, items: items, quality: askForQuality ? .ask : .default);
                } catch {
                    SharingTaskManager.instance.show(error: error, window: self.view.window!);
                }
            }
        }
        return true;
    }
    
    @objc func attachLocation(_ sender: NSButton) {
        let controller = NSStoryboard(name: "Location", bundle: nil).instantiateController(withIdentifier: "ShareLocationWindowController") as! NSWindowController;
        (controller.contentViewController as? ShareLocationController)?.conversation = conversation;
        controller.showWindow(self);
    }
    
    @IBAction func attachFile(_ sender: NSButton) {
        let askForQuality = NSEvent.modifierFlags.contains(.option);
        self.selectFile { (urls) in
            Task {
                do {
                    try await SharingTaskManager.instance.share(conversation: self.conversation, items: urls.map({ .url($0 as URL) }), quality: .default);
                } catch {
                    SharingTaskManager.instance.show(error: error, window: self.view.window!);
                }
            }
        }
    }
    
    func selectFile(completionHandler: @escaping ([URL])->Void) {
        let openFile = NSOpenPanel();
        openFile.worksWhenModal = true;
        openFile.prompt = NSLocalizedString("Select files to share", comment: "Select files to share");
        openFile.canChooseDirectories = false;
        openFile.canChooseFiles = true;
        openFile.canSelectHiddenExtension = true;
        openFile.canCreateDirectories = false;
        openFile.allowsMultipleSelection = true;
        openFile.resolvesAliases = true;

        openFile.begin { (response) in
            if response == .OK, !openFile.urls.isEmpty {
                completionHandler(openFile.urls);
            }
        }
    }
         
    @objc func startRecordingVoiceMessage(_ sender: NSButton) {
        CaptureDeviceManager.requestAccess(for: .audio, completionHandler: { value in
            guard value else {
                return;
            }
            DispatchQueue.main.async {
                self.startRecordingVoiceMessageInt();
            }
        })
    }
    
    private func startRecordingVoiceMessageInt() {
        if voiceRecordingView == nil {
            voiceRecordingView = VoiceRecordingView();
            voiceRecordingView?.wantsLayer = true;
        }
        if let voiceRecordingView = self.voiceRecordingView {
            voiceRecordingView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor;
            self.bottomView.addSubview(voiceRecordingView);
            NSLayoutConstraint.activate([
                self.bottomView.leadingAnchor.constraint(equalTo: voiceRecordingView.leadingAnchor),
                self.bottomView.trailingAnchor.constraint(equalTo: voiceRecordingView.trailingAnchor),
                self.bottomView.bottomAnchor.constraint(equalTo: voiceRecordingView.bottomAnchor),
                self.bottomView.topAnchor.constraint(equalTo: voiceRecordingView.topAnchor)
            ])
            voiceRecordingView.controller = self;
            voiceRecordingView.startRecording();
        }
    }
        
}
