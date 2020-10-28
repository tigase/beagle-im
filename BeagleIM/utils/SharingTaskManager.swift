//
// SharingTaskManager.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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

class SharingTaskManager {
    
    static let PROGRESS_CHANGED = Notification.Name(rawValue: "sharingTaskProgressChanged");
    
    static let instance = SharingTaskManager();
    
    private var tasks: [SharingTask] = [];
    let dispatcher = QueueDispatcher(label: "SharingTaskManager");
 
    static func guessContentType(of url: URL) -> String? {
        guard let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier else {
            return nil;
        }

        return UTTypeCopyPreferredTagWithClass(uti as CFString, kUTTagClassMIMEType)?.takeRetainedValue() as String?;
    }
    
    func progress(for chat: DBChatProtocol) -> Double? {
        let tasks = dispatcher.sync {
            return self.tasks.filter({ $0.chat.id == chat.id });
        }
        guard !tasks.isEmpty else {
            return 1.0;
        }
        guard tasks.firstIndex(where: { $0.progress == nil }) == nil else {
            return nil;
        }
        return tasks.reduce(0.0, { result, task in result + task.progress! }) / Double(tasks.count);
    }
    
    func share(task: SharingTask) {
        dispatcher.sync {
            self.tasks.append(task);
            print("starting task: \(task.id)")
            task.start();
        }
    }
    
    func ended(task: SharingTask) {
        dispatcher.sync {
            if let idx = self.tasks.firstIndex(of: task) {
                print("removing task: \(task.id)")
                self.tasks.remove(at: idx);
            }
        }
    }
    
    class SharingTask: Identifiable, Equatable {
        
        static func == (lhs: SharingTaskManager.SharingTask, rhs: SharingTaskManager.SharingTask) -> Bool {
            return lhs.id == rhs.id;
        }

        let id = UUID();
        let chat: DBChatProtocol;
        private(set) var items: [AbstractSharingTaskItem] = [];
        let operationQueue = OperationQueue();
        private weak var window: NSWindow?;
        var progress: Double? {
            guard items.firstIndex(where: { $0.progress == nil }) == nil else {
                return nil;
            }
            return items.reduce(0.0, { result, task in result + task.progress! }) / Double(items.count);
        }
        private var isSslTrusted = false;
        private let semaphore = DispatchSemaphore(value: 1);

        init(controller: AbstractChatViewControllerWithSharing, items: [AbstractSharingTaskItem]) {
            self.chat = controller.chat;
            self.window = controller.view.window;
            self.items = items;
            for item in items {
                item.task = self;
            }
        }
        
        func start() {
            for item in items {
                item.start();
            }
            NotificationCenter.default.post(name: SharingTaskManager.PROGRESS_CHANGED, object: self.chat);
        }
        
        func addItem(_ item: AbstractSharingTaskItem) {
            self.items.append(item);
            item.task = self;
        }
        
        func itemProgressUpdated(_ item: AbstractSharingTaskItem) {
            NotificationCenter.default.post(name: SharingTaskManager.PROGRESS_CHANGED, object: self.chat);
        }
        
        func itemCompleted(_ item: AbstractSharingTaskItem) {
            NotificationCenter.default.post(name: SharingTaskManager.PROGRESS_CHANGED, object: self.chat);
            if progress == 1.0 {
                // sharing of all items is now completed..
                var errors: [ShareError] = [];
                for it in items {
                    switch it.result! {
                    case .failure(let error):
                        errors.append(error);
                    default:
                        break;
                    }
                }
            
                if !errors.isEmpty, let window = self.window {
                    let alert = NSAlert();
                    alert.messageText = "Sharing error";
                    alert.informativeText = "It was not possible to share \(errors.count) item(s) due to following errors:\n \(errors.map({ $0.message }).joined(separator: "\n"))";
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: window, completionHandler: { response in
                        // nothing to do..
                    })
                }
                SharingTaskManager.instance.ended(task: self);
            }
        }
        
        private var isInvalidHttpResponseAccepted: Bool?;
        
        func askForInvalidHttpResponse(url: URL, completionHandler: @escaping (Bool)->Void) {
            guard let window = self.window else {
                completionHandler(false);
                return;
            }

            SharingTaskManager.instance.dispatcher.async {
                self.semaphore.wait();
                guard let value = self.isInvalidHttpResponseAccepted else {
                    DispatchQueue.main.async {
                        let alert = NSAlert();
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.messageText = "Warning";
                        alert.informativeText = "File upload completed but it was not confirmed correctly by your server. Do you wish to proceed anyway?";
                        alert.addButton(withTitle: "Yes");
                        alert.addButton(withTitle: "No");
                        alert.beginSheetModal(for: window, completionHandler: { response in
                            switch response {
                            case .alertFirstButtonReturn:
                                self.isInvalidHttpResponseAccepted = true;
                            default:
                                self.isInvalidHttpResponseAccepted = false;
                            }
                            self.semaphore.signal();
                            completionHandler(self.isInvalidHttpResponseAccepted!);
                        })
                    }
                    return;
                }
                self.semaphore.signal();
                completionHandler(value);
            }
        }
                
        func askForSSLCertificateTrust(_ trust: SecTrust, challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard let window = self.window else {
                completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil);
                return;
            }
            let info = SslCertificateInfo(trust: trust);
            
            SharingTaskManager.instance.dispatcher.async {
                self.semaphore.wait();
                guard !self.isSslTrusted else {
                    self.semaphore.signal();
                    let credential = URLCredential(trust: trust);
                    completionHandler(URLSession.AuthChallengeDisposition.useCredential, credential);
                    return;
                }

                DispatchQueue.main.async {
                    let alert = NSAlert();
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.messageText = "Invalid SSL certificate";
                    alert.informativeText = "HTTP File Upload server presented invalid SSL certificate for \(challenge.protectionSpace.host).\nReceived certificate \(info.details.name) (\(info.details.fingerprintSha1))" + (info.issuer == nil ? " is self-signed!" : " issued by \(info.issuer!.name).") + "\n\nWould you like to connect to the server anyway?";
                    alert.addButton(withTitle: "Yes");
                    alert.addButton(withTitle: "No");
                    alert.beginSheetModal(for: window, completionHandler: { (response) in
                        switch response {
                        case .alertFirstButtonReturn:
                            self.isSslTrusted = true;
                            let credential = URLCredential(trust: trust);
                            completionHandler(URLSession.AuthChallengeDisposition.useCredential, credential);
                        default:
                            completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil);
                        }
                        self.semaphore.signal();
                    })
                }
            }
        }
    }

}

protocol AttachmentSender {
    
    func prepareAttachment(chat: DBChatProtocol, originalURL: URL, completionHandler: @escaping (Result<(URL,Bool,((URL)->URL)?),ShareError>)->Void);
    
    func sendAttachment(chat: DBChatProtocol, originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?, completionHandler: (()->Void)?);
 
}

class AbstractSharingTaskItem: NSObject, URLSessionDelegate {
    
    private(set) var progress: Double? = nil {
        didSet {
            if let task = self.task {
                task.itemProgressUpdated(self);
            }
        }
    }
    weak var task: SharingTaskManager.SharingTask?;
    private let attachmentSender: AttachmentSender;
    private let chat: DBChatProtocol;
    private(set) var result: Result<URL,ShareError>?;
    
    init(chat: DBChatProtocol, sender: AttachmentSender) {
        self.attachmentSender = sender;
        self.chat = chat;
    }
    
    func completed(with result: Result<URL,ShareError>) {
        print("completed: \(result)");
        DispatchQueue.main.async {
            self.progress = 1.0;
            self.result = result;
            guard let task = self.task else {
                return;
            }
            task.itemCompleted(self);
        }
    }
    
    func start() {
        completed(with: .failure(.notSupported));
    }
    
    func prepareAndSendFile(url: URL, completionHandler: (()->Void)?) {
        let filename = url.lastPathComponent;
        attachmentSender.prepareAttachment(chat: chat, originalURL: url, completionHandler: { result in
            switch result {
            case .success(let (newUrl, isCopy, urlConverter)):
                self.sendFile(originalUrl: url, url: newUrl, filename: filename, urlConverter: urlConverter, completionHandler: {
                    if isCopy {
                        try? FileManager.default.removeItem(at: newUrl);
                    }
                    completionHandler?();
                })
            case .failure(let error):
                self.completed(with: .failure(error));
                completionHandler?();
            }
        });
    }
    
    func sendFile(originalUrl: URL, url: URL, filename: String, urlConverter: ((URL)->URL)?, completionHandler: (()->Void)?) {
        let mimeType = SharingTaskManager.guessContentType(of: url);
        guard let filesize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            self.completed(with: .failure(.noAccessError));
            completionHandler?();
            return;
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20.0) {
        self.uploadFileToHttpServer(url: url, filename: filename, filesize: filesize, mimeType: mimeType, completionHandler: { result in
            switch result {
            case .success(let uploadedUrl):
                let urlToSend = urlConverter?(uploadedUrl) ?? uploadedUrl;
                self.attachmentSender.sendAttachment(chat: self.chat, originalUrl: originalUrl, uploadedUrl: urlToSend, filesize: Int64(filesize), mimeType: mimeType, completionHandler: completionHandler);
            case .failure(let error):
                if let task = self.task {
                    switch error {
                    case .invalidResponseCode(let uploadedUrl):
                        task.askForInvalidHttpResponse(url: uploadedUrl, completionHandler: { result1 in
                            if result1 {
                                self.attachmentSender.sendAttachment(chat: self.chat, originalUrl: originalUrl, uploadedUrl: uploadedUrl, filesize: Int64(filesize), mimeType: mimeType, completionHandler: completionHandler);
                                self.completed(with: .success(uploadedUrl));
                            } else {
                                completionHandler?();
                                self.completed(with: .failure(error));
                            }
                        })
                        return;
                    default:
                        completionHandler?();
                        break;
                    }
                }
                break;
            }
            self.completed(with: result);
        })
        }
    }
    
    func uploadFileToHttpServer(url: URL, filename: String, filesize: Int, mimeType: String?, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard let inputStream = InputStream(url: url) else {
            completionHandler(.failure(.noAccessError));
            return;
        }
        HTTPFileUploadHelper.upload(forAccount: chat.account, filename: filename, inputStream: inputStream, filesize: filesize, mimeType: mimeType, delegate: self, completionHandler: { result in
            switch result {
            case .success(let url) :
                completionHandler(.success(url));
            case .failure(let error):
                completionHandler(.failure(error));
            }
        });
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            self.progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend);
        }
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust, let trust = challenge.protectionSpace.serverTrust {
            var trustResult: SecTrustResultType = .invalid;
            if SecTrustGetTrustResult(trust, &trustResult) == noErr {
                if trustResult == .proceed || trustResult == .unspecified {
                     let credential = URLCredential(trust: trust);
                    completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, credential);
                    return;
                }
            }

            guard let task = self.task else {
                completionHandler(.performDefaultHandling, nil);
                return;
            }
            task.askForSSLCertificateTrust(trust, challenge: challenge, completionHandler: completionHandler);
        } else {
            completionHandler(URLSession.AuthChallengeDisposition.performDefaultHandling, nil);
        }
    }
}

class FileURLSharingTaskItem: AbstractSharingTaskItem {
             
    let url: URL;
    
    init(chat: DBChatProtocol, sender: AttachmentSender, url: URL) {
        self.url = url;
        super.init(chat: chat, sender: sender);
    }
    
    override func start() {
        share(url: url);
    }
    
    func share(url: URL) {
        self.prepareAndSendFile(url: url, completionHandler: nil);
    }
    
}

class FilePromiseReceiverTaskItem: AbstractSharingTaskItem {
    
    let tmpUrl = FileManager.default.temporaryDirectory;
    
    let filePromiseReceiver: NSFilePromiseReceiver;
    
    init(chat: DBChatProtocol, sender: AttachmentSender, filePromiseReceiver: NSFilePromiseReceiver) {
        self.filePromiseReceiver = filePromiseReceiver;
        super.init(chat: chat, sender: sender);
    }
    
    override func start() {
        self.share(filePromiseReceiver: filePromiseReceiver);
    }
    
    func share(filePromiseReceiver: NSFilePromiseReceiver) {
        guard let queue = self.task?.operationQueue else {
            completed(with: .failure(.unknownError));
            return;
        }
        filePromiseReceiver.receivePromisedFiles(atDestination: tmpUrl, options: [:], operationQueue: queue) { (fileUrl, error) in
            guard error == nil else {
                self.completed(with: .failure(.noAccessError));
                return;
            }
            self.prepareAndSendFile(url: fileUrl, completionHandler: {
                try? FileManager.default.removeItem(at: fileUrl);
            });
        }
    }
    
}

