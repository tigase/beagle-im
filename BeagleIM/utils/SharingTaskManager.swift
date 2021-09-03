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
    
    func progress(for chat: Conversation) -> Double? {
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
        let chat: Conversation;
        private(set) var items: [AbstractSharingTaskItem] = [];
        let operationQueue = OperationQueue();
        private weak var window: NSWindow?;
        var progress: Double? {
            guard items.firstIndex(where: { $0.progress == nil }) == nil else {
                return nil;
            }
            return items.reduce(0.0, { result, task in result + task.progress! }) / Double(items.count);
        }
        
        private let semaphore = DispatchSemaphore(value: 1);

        private var imageQuality: ImageQuality?;
        private var videoQuality: VideoQuality?;
        
        private var isSslTrusted = false;
        private var isInvalidHttpResponseAccepted: Bool?;

        convenience init(controller: AbstractChatViewControllerWithSharing, items: [AbstractSharingTaskItem], askForQuality: Bool) {
            self.init(controller: controller, items: items, imageQuality: askForQuality ? nil : ImageQuality.current, videoQuality: askForQuality ? nil : VideoQuality.current)
        }
        
        init(controller: AbstractChatViewControllerWithSharing, items: [AbstractSharingTaskItem], imageQuality: ImageQuality?, videoQuality: VideoQuality?) {
            self.chat = controller.conversation;
            self.window = controller.view.window;
            self.items = items;
            for item in items {
                item.task = self;
            }
            self.imageQuality = imageQuality;
            self.videoQuality = videoQuality;
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
                    alert.messageText = NSLocalizedString("Sharing error", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to share %d item(s) due to following errors:\n %@", comment: "alert window message"), errors.count, errors.map({ $0.message }).joined(separator: "\n"));
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.beginSheetModal(for: window, completionHandler: { response in
                        // nothing to do..
                    })
                }
                SharingTaskManager.instance.ended(task: self);
            }
        }
                
        func askForImageQuality(completionHandler: @escaping (Result<ImageQuality,ShareError>)->Void) {
            SharingTaskManager.instance.dispatcher.async {
                self.semaphore.wait();
                guard let imageQuality = self.imageQuality else {
                    guard let window = self.window else {
                        completionHandler(.success(ImageQuality.current));
                        return;
                    }
                    MediaHelper.askImageQuality(window: window, forceQualityQuestion: true, { result in
                        switch result {
                        case .success(let quality):
                            self.imageQuality = quality;
                        default:
                            break;
                        }
                        self.semaphore.signal();
                        completionHandler(result);
                    })
                    return;
                }
                self.semaphore.signal();
                completionHandler(.success(imageQuality));
            }
        }

        func askForVideoQuality(completionHandler: @escaping (Result<VideoQuality,ShareError>)->Void) {
            SharingTaskManager.instance.dispatcher.async {
                self.semaphore.wait();
                guard let videoQuality = self.videoQuality else {
                    guard let window = self.window else {
                        completionHandler(.success(VideoQuality.current));
                        return;
                    }
                    MediaHelper.askVideoQuality(window: window, forceQualityQuestion: true, { result in
                        switch result {
                        case .success(let quality):
                            self.videoQuality = quality;
                        default:
                            break;
                        }
                        self.semaphore.signal();
                        completionHandler(result);
                    })
                    return;
                }
                self.semaphore.signal();
                completionHandler(.success(videoQuality));
            }
        }

        
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
                        alert.messageText = NSLocalizedString("Warning", comment: "alert window title");
                        alert.informativeText = NSLocalizedString("File upload completed but it was not confirmed correctly by your server. Do you wish to proceed anyway?", comment: "alert window message");
                        alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Button"));
                        alert.addButton(withTitle: NSLocalizedString("No", comment: "Button"));
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
                    alert.messageText = NSLocalizedString("Invalid SSL certificate", comment: "alert window title")
                    alert.informativeText = info.issuer == nil ? String.localizedStringWithFormat(NSLocalizedString("HTTP File Upload server presented invalid SSL certificate for %@.\nReceived certificate %@ (%@) is self-signed!\n\nWould you like to connect to the server anyway?", comment: "alert window message - part 1"), challenge.protectionSpace.host, info.details.name, info.details.fingerprintSha1) : String.localizedStringWithFormat(NSLocalizedString("HTTP File Upload server presented invalid SSL certificate for %@.\nReceived certificate %@ (%@) is issued by %@.\n\nWould you like to connect to the server anyway?", comment: "alert window message - part 1"), challenge.protectionSpace.host, info.details.name, info.details.fingerprintSha1, info.issuer!.name);
                    alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Button"));
                    alert.addButton(withTitle: NSLocalizedString("No", comment: "Button"));
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
    
    func prepareAttachment(chat: Conversation, originalURL: URL, completionHandler: @escaping (Result<(URL,Bool,((URL)->URL)?),ShareError>)->Void);
    
    func sendAttachment(chat: Conversation, originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?, completionHandler: (()->Void)?);
 
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
    private let chat: Conversation;
    private(set) var result: Result<URL,ShareError>?;
    
    init(chat: Conversation) {
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
    
    private func sendAttachmentToConversation(originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?, completionHandler: (() -> Void)?) {
        var appendix = ChatAttachmentAppendix();
        appendix.state = .downloaded;
        appendix.filename = originalUrl.lastPathComponent;
        appendix.filesize = Int(filesize);
        appendix.mimetype = mimeType;
        chat.sendAttachment(url: uploadedUrl.absoluteString, appendix: appendix, originalUrl: originalUrl, completionHandler: completionHandler);
    }
    
    func downscaleIfRequired(at source: URL, completionHandler: @escaping (Result<(URL,Bool),ShareError>)->Void) {
        guard let mimeType = SharingTaskManager.guessContentType(of: source) else {
            completionHandler(.success((source, false)));
            return;
        }
        
        if mimeType.starts(with: "image/") {
            if let task = self.task {
                task.askForImageQuality(completionHandler: { result in
                    switch result {
                    case .success(let quality):
                        MediaHelper.compressImage(url: source, filename: UUID().uuidString, quality: quality, deleteSource: false, completionHandler: { result in
                            switch result {
                            case .success(let url):
                                completionHandler(.success((url, quality != .original)));
                            case .failure(let error):
                                completionHandler(.failure(error));
                            }
                        });
                    case .failure(let error):
                        completionHandler(.failure(error));
                    }
                })
            } else {
                completionHandler(.success((source, false)));
            }
        } else if mimeType.starts(with: "video/") {
            if let task = self.task {
                task.askForVideoQuality(completionHandler: { result in
                    switch result {
                    case .success(let quality):
                        MediaHelper.compressMovie(url: source, filename: UUID().uuidString, quality: quality, deleteSource: false, progressCallback: { progress in
                            // lets ignore it for now..
                        }, completionHandler: { result in
                            switch result {
                            case .success(let url):
                                completionHandler(.success((url, quality != .original)));
                            case .failure(let error):
                                completionHandler(.failure(error));
                            }
                        })
                    case .failure(let error):
                        completionHandler(.failure(error));
                    }
                })
            } else {
                completionHandler(.success((source, false)));
            }
        } else {
            completionHandler(.success((source, false)));
        }
    }
    
    func preprocessAndSendFile(url: URL, completionHandler: (()->Void)?) {
        let filename = url.lastPathComponent;
        downscaleIfRequired(at: url, completionHandler: { result in
            switch result {
            case .success((let newUrl, let isCopy)):
                self.prepareAndSendFile(url: newUrl, filename: filename, completionHandler: {
                    if isCopy {
                        try? FileManager.default.removeItem(at: newUrl);
                    }
                    completionHandler?();
                });
            case .failure(let error):
                self.completed(with: .failure(error));
                completionHandler?();
            }
        });
    }
    
    func prepareAndSendFile(url: URL, filename: String, completionHandler: (()->Void)?) {
        chat.prepareAttachment(url: url, completionHandler: { result in
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
        self.uploadFileToHttpServer(url: url, filename: filename, filesize: filesize, mimeType: mimeType, completionHandler: { result in
            switch result {
            case .success(let uploadedUrl):
                let urlToSend = urlConverter?(uploadedUrl) ?? uploadedUrl;
                self.sendAttachmentToConversation(originalUrl: originalUrl, uploadedUrl: urlToSend, filesize: Int64(filesize), mimeType: mimeType, completionHandler: completionHandler);
            case .failure(let error):
                if let task = self.task {
                    switch error {
                    case .invalidResponseCode(let uploadedUrl):
                        task.askForInvalidHttpResponse(url: uploadedUrl, completionHandler: { result1 in
                            if result1 {
                                self.sendAttachmentToConversation(originalUrl: originalUrl, uploadedUrl: uploadedUrl, filesize: Int64(filesize), mimeType: mimeType, completionHandler: completionHandler);
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
    
    func uploadFileToHttpServer(url: URL, filename: String, filesize: Int, mimeType: String?, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard let context = chat.context else {
            completionHandler(.failure(.unknownError));
            return;
        }
        guard let inputStream = InputStream(url: url) else {
            completionHandler(.failure(.noAccessError));
            return;
        }
        HTTPFileUploadHelper.upload(withClient: context, filename: filename, inputStream: inputStream, filesize: filesize, mimeType: mimeType, delegate: self, completionHandler: { result in
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
    
    private let deleteFileOnCompletion: Bool;
    
    init(chat: Conversation, url: URL, deleteFileOnCompletion: Bool = false) {
        self.url = url;
        self.deleteFileOnCompletion = deleteFileOnCompletion;
        super.init(chat: chat);
    }
    
    override func start() {
        share(url: url);
    }
    
    func share(url: URL) {
        self.preprocessAndSendFile(url: url, completionHandler: {
            if self.deleteFileOnCompletion {
                try? FileManager.default.removeItem(at: url);
            }
        });
    }
    
}

class FilePromiseReceiverTaskItem: AbstractSharingTaskItem {
    
    let tmpUrl = FileManager.default.temporaryDirectory;
    
    let filePromiseReceiver: NSFilePromiseReceiver;
    
    init(chat: Conversation, filePromiseReceiver: NSFilePromiseReceiver) {
        self.filePromiseReceiver = filePromiseReceiver;
        super.init(chat: chat);
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
            self.preprocessAndSendFile(url: fileUrl, completionHandler: {
                try? FileManager.default.removeItem(at: fileUrl);
            });
        }
    }
    
}

