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

class AbstractChatViewControllerWithSharing: AbstractChatViewController, URLSessionTaskDelegate, NSDraggingDestination, PastingDelegate {

    @IBOutlet var sharingProgressBar: NSProgressIndicator!;
    @IBOutlet var sharingButton: NSButton!;

    var attachmentSender: AttachmentSender!;

    var isSharingAvailable: Bool {
        guard let uploadModule: HttpFileUploadModule = XmppService.instance.getClient(for: account!)?.modulesManager.getModule(HttpFileUploadModule.ID) else {
            return false;
        }
        return uploadModule.isAvailable;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(sharingSupportChanged), name: HttpFileUploadEventHandler.UPLOAD_SUPPORT_CHANGED, object: nil);
        messageField.dragHandler = self;
        messageField.registerForDraggedTypes([.fileURL] + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) });
        self.sharingProgressBar.minValue = 0;
        self.sharingProgressBar.maxValue = 1;
        self.sharingProgressBar.isHidden = true;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.sharingButton.isEnabled = self.isSharingAvailable;
        NotificationCenter.default.addObserver(self, selector: #selector(sharingProgressChanged(_:)), name: SharingTaskManager.PROGRESS_CHANGED, object: chat);
        self.updateSharingProgress();
    }
    
    @objc func sharingProgressChanged(_ notification: Notification) {
        DispatchQueue.main.async {
            self.updateSharingProgress();
        }
    }
    
    func updateSharingProgress() {
        let progress = SharingTaskManager.instance.progress(for: chat);
        sharingProgressBar.isIndeterminate = progress != nil;
        print("setting progress to:", progress);
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
            alert.messageText = "Sending files";
            alert.informativeText = "You have pasted \(urls.count) file(s). Do you wish to send them?";
            alert.addButton(withTitle: "Yes");
            alert.addButton(withTitle: "No");
            alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                if response == .alertFirstButtonReturn {
                    let tasks = urls.map({ FileURLSharingTaskItem(chat: self.chat, sender: self.attachmentSender, url: $0 as URL)});
                    SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: self, items: tasks));
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
                tasks.append(FilePromiseReceiverTaskItem(chat: self.chat, sender: self.attachmentSender, filePromiseReceiver: filePromiseReceived));
            case let fileUrl as URL:
                guard fileUrl.isFileURL else {
                    return;
                }
                tasks.append(FileURLSharingTaskItem(chat: self.chat, sender: self.attachmentSender, url: fileUrl));
            default:
                break;
            }
        }
        if !tasks.isEmpty {
            SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: self, items: tasks));
        }
        return true;
    }
    
    @objc func sharingSupportChanged(_ notification: Notification) {
        guard let account = notification.object as? BareJID else {
            return;
        }
        guard self.account != nil && self.account! == account else {
            return;
        }
        DispatchQueue.main.async {
            self.sharingButton.isEnabled = self.isSharingAvailable;
        }
    }
    
    @IBAction func attachFile(_ sender: NSButton) {
        self.selectFile { (urls) in
            let tasks = urls.map({ FileURLSharingTaskItem(chat: self.chat, sender: self.attachmentSender, url: $0)});
            SharingTaskManager.instance.share(task: SharingTaskManager.SharingTask(controller: self, items: tasks));
        }
    }
    
    func selectFile(completionHandler: @escaping ([URL])->Void) {
        let openFile = NSOpenPanel();
        openFile.worksWhenModal = true;
        openFile.prompt = "Select files to share";
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
        
//    func uploadFileToHttpServerWithErrorHandling(data: Data, filename: String, mimeType: String?, onSuccess: @escaping (HTTPFileUploadHelper.UploadResult)->Void) {
//        uploadFileToHttpServer(data: data, filename: filename, mimeType: mimeType) { (result) in
//            switch result {
//            case .failure(let error, let errorMessage):
//                DispatchQueue.main.async {
//                    let alert = NSAlert();
//                    alert.icon = NSImage(named: NSImage.cautionName);
//                    alert.messageText = "Upload error";
//                    alert.informativeText = errorMessage ?? "Received an error: \(error.rawValue)";
//                    alert.addButton(withTitle: "OK");
//                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
//                }
//            case .success(_, _, _):
//                DispatchQueue.main.async {
//                    onSuccess(result);
//                }
//            }
//        }
//    }
    
//    func uploadFileToHttpServer(data: Data, filename: String, mimeType contentType: String?, completionHandler: @escaping (UploadResult)->Void) {
//        guard let uploadModule: HttpFileUploadModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(HttpFileUploadModule.ID) else {
//            completionHandler(.failure(error: ErrorCondition.feature_not_implemented, errorMessage: "HttpFileUploadModule not enabled!"));
//            return;
//        }
//        guard let component = uploadModule.availableComponents.first else {
//            print("could not found any HTTP upload component!");
//            completionHandler(.failure(error: ErrorCondition.feature_not_implemented, errorMessage: "Server does not support XEP-0363: HTTP File Upload"));
//            return;
//        }
//
//        if contentType?.starts(with: "image/") ?? false {
//            // send scaled..
//
//        } else if contentType?.starts(with: "video/") ?? false {
//            // send reencoded..
//        } else {
//            // send as it is..
//        }
////        let attributes = try! FileManager.default.attributesOfItem(atPath: url.path);
////        let filesize = attributes[FileAttributeKey.size] as! UInt64;
//        let filesize = data.count;
//
//        uploadModule.requestUploadSlot(componentJid: component.jid, filename: filename, size: filesize, contentType: contentType, onSuccess: { (slot) in
//            DispatchQueue.main.async {
//                self.sharingProgressBar.isHidden = false;
//            }
//            var request = URLRequest(url: slot.putUri);
//            slot.putHeaders.forEach({ (k,v) in
//                request.addValue(v, forHTTPHeaderField: k);
//            });
//            if contentType != nil {
//                request.addValue(contentType!, forHTTPHeaderField: "Content-Type")
//            }
//            request.httpMethod = "PUT";
//            request.httpBody = data;
//
//            let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main);
//            session.dataTask(with: request, completionHandler: { (data, response, error) in
//                let code = ((response as? HTTPURLResponse)?.statusCode ?? 500);
//                guard error == nil && (code == 201 || code == 200) else {
//                    print("received HTTP error response", error as Any, code);
//                    self.sharingProgressBar.isHidden = true;
//                    completionHandler(.failure(error: ErrorCondition.internal_server_error, errorMessage: "Could not upload data to the HTTP server" + (error == nil ? "" : (":\n" + error!.localizedDescription))));
//                    return;
//                }
//
//                self.sharingProgressBar.isHidden = true;
//                if code == 200 {
//                    if let window = self.view.window {
//                        let alert = NSAlert();
//                        alert.icon = NSImage(named: NSImage.cautionName);
//                        alert.messageText = "Warning";
//                        alert.informativeText = "File upload completed but it was not confirmed correctly by your server. Do you wish to proceed anyway?";
//                        alert.addButton(withTitle: "Yes");
//                        alert.addButton(withTitle: "No");
//                        alert.beginSheetModal(for: window, completionHandler: { result in
//                            switch result {
//                            case NSApplication.ModalResponse.alertFirstButtonReturn:
//                                completionHandler(.success(url: slot.getUri, filesize: Int64(filesize), mimeType: contentType));
//                            default:
//                                break;
//                            }
//                        })
//                    }
//                } else {
//                    print("file uploaded at:", slot.getUri);
//                    completionHandler(.success(url: slot.getUri, filesize: Int64(filesize), mimeType: contentType));
//                }
//            }).resume();
//        }, onError: { (errorCondition, errorText) in
//            print("failedd to allocate slot:", errorCondition as Any, errorText as Any);
//            completionHandler(.failure(error: errorCondition ?? ErrorCondition.undefined_condition, errorMessage: errorText));
//        })
//    }
    
        
}
