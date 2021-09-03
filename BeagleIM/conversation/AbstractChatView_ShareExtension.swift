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
import TigaseSwift
import Combine

class AbstractChatViewControllerWithSharing: AbstractChatViewController, URLSessionTaskDelegate, NSDraggingDestination, PastingDelegate {

    @IBOutlet var sharingProgressBar: NSProgressIndicator!;
    private(set) var sharingButton: NSButton!;
    private(set) var voiceMessageButton: NSButton!;
    private var voiceRecordingView: VoiceRecordingView?;
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        print("AbstractChatViewControllerWithSharing::viewDidLoad() - begin")
        super.viewDidLoad();

        self.voiceMessageButton = NSButton(image: NSImage(named: "mic.circle")!, target: self, action: #selector(startRecordingVoiceMessage(_:)));
        self.voiceMessageButton.bezelStyle = .regularSquare;
        self.voiceMessageButton.isBordered = false;
        NSLayoutConstraint.activate([self.voiceMessageButton.widthAnchor.constraint(equalToConstant: NSFont.systemFontSize * 2), self.voiceMessageButton.widthAnchor.constraint(equalTo: self.voiceMessageButton.heightAnchor)]);
        bottomView.addView(voiceMessageButton, in: .leading)
        self.voiceMessageButton.isEnabled = false;

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
        print("AbstractChatViewControllerWithSharing::viewDidLoad() - end")
    }
    
    override func viewWillAppear() {
        print("AbstractChatViewControllerWithSharing::viewWillAppear() - begin")
        super.viewWillAppear();
        createSharingAvailablePublisher()?.receive(on: DispatchQueue.main).assign(to: \.isEnabled, on: self.sharingButton).store(in: &cancellables)
        createSharingAvailablePublisher()?.combineLatest(CaptureDeviceManager.authorizationStatusPublisher(for: .audio), { sharing, media in
            return sharing && (media == .authorized || media == .notDetermined);
        }).receive(on: DispatchQueue.main).assign(to: \.isEnabled, on: self.voiceMessageButton).store(in: &cancellables)
        NotificationCenter.default.addObserver(self, selector: #selector(sharingProgressChanged(_:)), name: SharingTaskManager.PROGRESS_CHANGED, object: conversation);
        self.updateSharingProgress();
        print("AbstractChatViewControllerWithSharing::viewWillAppear() - end")
    }
    
    override func viewDidDisappear() {
        print("AbstractChatViewControllerWithSharing::viewDidDisappear() - begin")
        super.viewDidDisappear()
        self.cancellables.removeAll();
        print("AbstractChatViewControllerWithSharing::viewDidDisappear() - end")
    }
    
    @objc func sharingProgressChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateSharingProgress();
        }
    }
    
    func createSharingAvailablePublisher() -> AnyPublisher<Bool,Never>? {
        return (self.conversation?.context?.module(.httpFileUpload) as? HttpFileUploadModule)?.isAvailablePublisher;
    }
    
    func updateSharingProgress() {
        let progress = SharingTaskManager.instance.progress(for: conversation);
        sharingProgressBar.isIndeterminate = progress != nil;
        print("setting progress to: \(String(describing: progress))");
        if let value = progress {
            self.sharingProgressBar.doubleValue = value;
            self.sharingProgressBar.isHidden = value == 1;
        } else {
            self.sharingProgressBar.isHidden = false;
        }
    }
    
    func paste(in textView: AutoresizingTextView, pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) {
            guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL], urls.allSatisfy({ $0.isFileURL }) else {
                return false;
            }
            print("pasted file urls: \(urls)");
            let alert = NSAlert();
            alert.alertStyle = .informational;
            alert.icon = NSImage(named: NSImage.shareTemplateName);
            alert.messageText = NSLocalizedString("Sending files", comment: "Title of alert to confirm sending files");
            alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("You have pasted %d file(s). Do you wish to send them?", comment: "Alert confirm sending files message"), urls.count);
            alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Confirm sending files"));
            alert.addButton(withTitle: NSLocalizedString("No", comment: "Deny sending files"));
            alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                if response == .alertFirstButtonReturn {
                    let tasks = urls.map({ FileURLSharingTaskItem(chat: self.conversation, url: $0 as URL)});
                    SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: self, items: tasks, askForQuality: false));
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
        return sender.draggingSourceOperationMask.contains(.copy) && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self], options: nil) ? .copy : .generic;
    }
    
    func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return sender.draggingSourceOperationMask.contains(.copy) && sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self, NSFilePromiseReceiver.self], options: nil) ? .copy : .generic;
    }
    
    func draggingExited(_ sender: NSDraggingInfo?) {
        
    }
    
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard sharingButton.isEnabled else {
            return false;
        }
        
        var tasks: [AbstractSharingTaskItem] = [];
        sender.enumerateDraggingItems(options: [], for: nil, classes: [NSFilePromiseReceiver.self, NSURL.self], searchOptions: [.urlReadingFileURLsOnly: true]) { (item, _, _) in
            switch item.item {
            case let filePromiseReceived as NSFilePromiseReceiver:
                tasks.append(FilePromiseReceiverTaskItem(chat: self.conversation, filePromiseReceiver: filePromiseReceived));
            case let fileUrl as URL:
                guard fileUrl.isFileURL else {
                    return;
                }
                tasks.append(FileURLSharingTaskItem(chat: self.conversation, url: fileUrl));
            default:
                break;
            }
        }
        if !tasks.isEmpty {
            let askForQuality = NSEvent.modifierFlags.contains(.option);
            SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: self, items: tasks, askForQuality: askForQuality));
        }
        return true;
    }
    
    @IBAction func attachFile(_ sender: NSButton) {
        let askForQuality = NSEvent.modifierFlags.contains(.option);
        self.selectFile { (urls) in
            let tasks = urls.map({ FileURLSharingTaskItem(chat: self.conversation, url: $0)});
            SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: self, items: tasks, askForQuality: askForQuality));
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
            print("got response", response.rawValue);
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
