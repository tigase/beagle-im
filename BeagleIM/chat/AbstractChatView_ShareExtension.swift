//
//  AbstractChatViewControllerWithSharing.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 29/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class AbstractChatViewControllerWithSharing: AbstractChatViewController, URLSessionTaskDelegate {

    @IBOutlet var sharingProgressBar: NSProgressIndicator!;
    @IBOutlet var sharingButton: NSButton!;
    
    var isSharingAvailable: Bool {
        guard let uploadModule: HttpFileUploadModule = XmppService.instance.getClient(for: account!)?.modulesManager.getModule(HttpFileUploadModule.ID) else {
            return false;
        }
        return uploadModule.isAvailable;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        NotificationCenter.default.addObserver(self, selector: #selector(sharingSupportChanged), name: HttpFileUploadEventHandler.UPLOAD_SUPPORT_CHANGED, object: nil);
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.sharingButton.isEnabled = self.isSharingAvailable;
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
    
    func sendMessage(body: String? = nil, url: String? = nil) -> Bool {
        return false;
    }
    
    @IBAction func attachFile(_ sender: NSButton) {
        self.selectFile { (url) in
            self.uploadFileToHttpServer(url: url) { (uploadedUrl, errorCondition, errorMessage) in
                guard errorCondition == nil else {
                    let alert = NSAlert();
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.messageText = "Upload error";
                    alert.informativeText = errorMessage ?? "Received an error: \(errorCondition!.rawValue)";
                    alert.addButton(withTitle: "OK");
                    alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    return;
                }
                DispatchQueue.main.async {
                    _ = self.sendMessage(url: uploadedUrl);
                }
            }
        }
    }
    
    func selectFile(completionHandler: @escaping (URL)->Void) {
        let openFile = NSOpenPanel();
        openFile.worksWhenModal = true;
        openFile.prompt = "Select files to share";
        openFile.canChooseDirectories = false;
        openFile.canChooseFiles = true;
        openFile.canSelectHiddenExtension = true;
        openFile.canCreateDirectories = false;
        openFile.allowsMultipleSelection = false;
        openFile.resolvesAliases = true;

        openFile.begin { (response) in
            print("got response", response.rawValue);
            if response == .OK, let url = openFile.url {
                completionHandler(url);
            }
        }
    }
    
    func uploadFileToHttpServer(url: URL, completionHandler: @escaping (String?, ErrorCondition?, String?)->Void) {
        print("selected file:", url);
        guard let uploadModule: HttpFileUploadModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(HttpFileUploadModule.ID) else {
            completionHandler(nil, ErrorCondition.feature_not_implemented, "HttpFileUploadModule not enabled!");
            return;
        }
        guard let component = uploadModule.availableComponents.first else {
            print("could not found any HTTP upload component!");
            completionHandler(nil, ErrorCondition.feature_not_implemented, "Server does not support XEP-0363: HTTP File Upload");
            return;
        }

        let attributes = try! FileManager.default.attributesOfItem(atPath: url.path);
        let filesize = attributes[FileAttributeKey.size] as! UInt64;
            
        uploadModule.requestUploadSlot(componentJid: component.jid, filename: url.lastPathComponent, size: Int(filesize), contentType: nil, onSuccess: { (slot) in
            DispatchQueue.main.async {
                self.sharingProgressBar.isHidden = false;
            }
            var request = URLRequest(url: URL(string: slot.putUri)!);
            slot.putHeaders.forEach({ (k,v) in
                request.addValue(v, forHTTPHeaderField: k);
            });
            request.httpMethod = "PUT";
            request.httpBody = try! Data(contentsOf: url);
                
            let session = URLSession(configuration: URLSessionConfiguration.default, delegate: self, delegateQueue: OperationQueue.main);
            session.dataTask(with: request, completionHandler: { (data, response, error) in
                let code = ((response as? HTTPURLResponse)?.statusCode ?? 500);
                guard error == nil && code == 201 else {
                    print("received HTTP error response", error as Any, code);
                    self.sharingProgressBar.isHidden = true;
                    completionHandler(nil, ErrorCondition.internal_server_error, "Could not upload data to the HTTP server");
                    return;
                }
                    
                print("file uploaded at:", slot.getUri);
                self.sharingProgressBar.isHidden = true;
                completionHandler(slot.getUri, nil, nil);
            }).resume();
        }, onError: { (errorCondition, errorText) in
            print("failedd to allocate slot:", errorCondition as Any, errorText as Any);
            completionHandler(nil, errorCondition, errorText);
        })
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            self.sharingProgressBar.minValue = 0;
            self.sharingProgressBar.maxValue = 1;
            self.sharingProgressBar.doubleValue = Double(totalBytesSent) / Double(totalBytesExpectedToSend);
            if self.sharingProgressBar.doubleValue == 1 {
                self.sharingProgressBar.isHidden = true;
                self.sharingProgressBar.doubleValue = 0;
            } else {
                self.sharingProgressBar.isHidden = false;
            }
        }
    }
}
