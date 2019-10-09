//
// BaseChatMessageCellView.swift
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


class BaseChatMessageCellView: NSTableCellView {
    
    fileprivate static let imageLoadingQueue = DispatchQueue(label: "image_loading_queue");
    
    var id: Int = 0;
    
    @IBOutlet var message: NSTextField!
    @IBOutlet var state: NSTextField?;
    fileprivate var direction: MessageDirection? = nil;
    
    func set(message item: ChatMessage) {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue);
        
        let messageBody = self.messageBody(item: item);
        let matches = detector.matches(in: messageBody, range: NSMakeRange(0, messageBody.utf16.count));
        let msg = NSMutableAttributedString(string: messageBody);
        var previewsToRetrive: [URL] = [];
        var previewsToLoad: [(URL,String)] = [];
        var errors: [String] = [];
        matches.forEach { match in
            if let url = match.url {
                if let previewId = item.preview?[url.absoluteString] {
                    if previewId.starts(with: "ERROR") {
                        var error = "";
                        if previewId.contains(":") {
                            switch previewId.dropFirst("ERROR:".count) {
                            case "NSURLErrorServerCertificateUntrusted":
                                error = "Could not retrieve preview - invalid SSL certificate!";
                            case "SizeExceeded":
                                error = "Could not retrieve preview - file size exceeded!";
                            default:
                                error = "Could not retrieve preview - an error occurred";
                            }
                        } else {
                            error = "Could not retrieve preview - an error occurred";
                        }
                        if !errors.contains(error) {
                            errors.append(error);
                        }
                    } else if "NONE" != previewId {
                        previewsToLoad.append((url, previewId));
                    }
                }
                msg.addAttribute(.link, value: url, range: match.range);
                
                if item.preview == nil {
                    previewsToRetrive.append(url);
                }
            }
            if let phoneNumber = match.phoneNumber {
                msg.addAttribute(.link, value: URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "-"))")!, range: match.range);
            }
            if let address = match.components {
                let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                msg.addAttribute(.link, value: URL(string: "http://maps.apple.com/?q=\(query!)")!, range: match.range);
            }
        }
        msg.addAttribute(NSAttributedString.Key.font, value: self.message.font!, range: NSMakeRange(0, msg.length));
        
        if Settings.enableMarkdownFormatting.bool() {
            Markdown.applyStyling(attributedString: msg, showEmoticons: Settings.showEmoticons.bool());
        }
        
        if let errorMessage = item.error {
            msg.append(NSAttributedString(string: "\n------\n\(errorMessage)", attributes: [.foregroundColor : NSColor.systemRed]));
        }

        switch item.state {
        case .incoming_error, .incoming_error_unread:
            self.message.textColor = NSColor.systemRed;
            self.state?.stringValue = "\u{203c}";
        case .outgoing_unsent:
            self.message.textColor = NSColor.secondaryLabelColor;
            self.state?.stringValue = "\u{1f4e4}";
        case .outgoing_delivered:
            self.message.textColor = nil;
            self.state?.stringValue = "\u{2713}";
        case .outgoing_error, .outgoing_error_unread:
            self.message.textColor = nil;
            self.state?.stringValue = "\u{203c}";
        default:
            self.state?.stringValue = "";
            self.message.textColor = nil;//NSColor.textColor;
        }
        self.state?.textColor = item.state.isError ? NSColor.systemRed : NSColor.secondaryLabelColor;
        self.direction = item.state.direction;

        self.toolTip = BaseChatMessageCellView.tooltipFormatter.string(from: item.timestamp) + (errors.isEmpty ? "" : "\n" + errors.joined(separator: "\n"));
        
        if previewsToLoad.isEmpty {
            BaseChatMessageCellView.downloadPreviews(for: item, urls: previewsToRetrive);
        } else {
            DownloadCache.instance.getImages(for: previewsToLoad) { (loaded, sync) in
                var first = true;
                let msgStr = msg.string;
                loaded.forEach { (arg0) in
                    let (url, image) = arg0
                    self.appendPreview(message: msg, url: url, image: image, first: first);
                    first = false;
                }
                if !sync && !first {
                    DispatchQueue.main.async {
                        if self.message.attributedStringValue.string == msgStr {
                            self.message.attributedStringValue = msg;
                        } else {
                            print("items do not match!");
                        }
                    }
                }
            }
        }
        self.message.attributedStringValue = msg;
    }
    
    override func layout() {
        if Settings.alternateMessageColoringBasedOnDirection.bool() {
            if let direction = self.direction {
                switch direction {
                case .incoming:
                    self.wantsLayer = true;
                    self.layer?.backgroundColor = NSColor(named: "chatBackgroundColor")!.cgColor;
                case .outgoing:
                    self.wantsLayer = true;
                    self.layer?.backgroundColor = NSColor(named: "chatOutgoingBackgroundColor")!.cgColor;
                }
            }
        }
        super.layout();
        if let width = self.superview?.superview?.frame.width {
            self.message.preferredMaxLayoutWidth = width - 78;
        }
    }
    
    fileprivate func appendPreview(message msg: NSMutableAttributedString, url: URL, image origImage: NSImage, first: Bool) {
        let att = NSTextAttachment(data: nil, ofType: nil);
        let image = scalled(image: origImage);
        att.image = image;
        //ten bounds wypadałoby dostosowywać w zależności od zmiany szerokości okna!!
        //print("W:", image.size.width, "H:", image.size.height);
        att.bounds = NSRect(x: att.bounds.origin.x, y: att.bounds.origin.y, width: image.size.width, height: image.size.height);
        if first {
            msg.append(NSAttributedString(string: "\n"));
        } else {
            msg.append(NSAttributedString(string: " "));
        }
        let pos = msg.length;
        msg.append(NSAttributedString(attachment: att));
        msg.addAttribute(.link, value: url, range: NSRange(pos..<(pos+1)));
    }

    private func scalled(image origImage: NSImage) -> NSImage {
        if #available(OSX 10.15, *) {
            return origImage.scaledAndFlipped(maxWidth: 250.0, maxHeight: 200.0, flipX: false, flipY: false, roundedRadius: 8.0);
        } else {
            return origImage.scaledAndFlipped(maxWidth: 250.0, maxHeight: 200.0, flipX: false, flipY: true, roundedRadius: 8.0);
        }
    }
    
    fileprivate func messageBody(item: ChatMessage) -> String {
        guard let msg = item.encryption.message() else {
//            guard let error = item.error else {
//                return item.message;
//            }
//            return "\(item.message)\n-----\n\(error)";
            return item.message;
        }
        return msg;
    }

    func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return BaseChatMessageCellView.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return BaseChatMessageCellView.fullFormatter.string(from: ts);
        } else {
            return BaseChatMessageCellView.defaultFormatter.string(from: ts);
        }
        
    }
    
    fileprivate static func downloadPreviews(for item: ChatMessage, urls: [URL]) {
        guard !urls.isEmpty && Settings.imageDownloadSizeLimit.integer() > 0 else {
            return;
        }
        
        DispatchQueue.global().async {
            var preview = item.preview ?? [:];
            
            let finisher: (URL, String)->Void = { url, previewId in
                DispatchQueue.main.async {
                    preview[url.absoluteString] = previewId;
                    var result = true;
                    urls.forEach({ u in
                        result = result && preview[u.absoluteString] != nil;
                    })
                    if result {
                        DBChatHistoryStore.instance.updateItem(for: item.account, with: item.jid, id: item.id, preview: [url.absoluteString: previewId]);
                    }
                }
            };
            
            let sessionConfig = URLSessionConfiguration.default;
            let session = URLSession(configuration: sessionConfig);
            urls.forEach { (url) in
                if let previewId = DownloadCache.instance.hasFile(for: url) {
                    finisher(url, previewId);
                    return;
                } else {
                    BaseChatMessageCellView.downloadPreviewGetHeaders(session: session, url: url, completion: { (statusCode, error, mimeType, length) in
                        guard error == nil else {
                            if (error!._code == -1202 && error!._domain == "NSURLErrorDomain") {
                                finisher(url, "ERROR:NSURLErrorServerCertificateUntrusted");
                            } else {
                                finisher(url, "ERROR");
                            }
                            return;
                        }
                        var isImage = (mimeType?.hasPrefix("image/") ?? false);
                        if !isImage {
                            if let fileExtension = url.lastPathComponent.split(separator: ".").last {
                                isImage = fileExtension == "jpg" || fileExtension == "jpeg" || fileExtension == "png";
                            }
                        }
                        if isImage, let size = length {
                            if size < Int64(Settings.imageDownloadSizeLimit.integer()) {
                                BaseChatMessageCellView.downloadPreviewImage(session: session, url: url, completion: { (url, previewId) in
                                    finisher(url, previewId);
                                })
                            } else {
                                finisher(url, "ERROR:SizeExceeeded");
                            }
                        } else {
                            finisher(url, "NONE");
                        }
                    });
                }
            }
        }
    }
    
    fileprivate static func downloadPreviewImage(session: URLSession, url: URL, completion: @escaping (URL, String)->Void) {
        let request = URLRequest(url: url);
        let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                do {
                    let previewId = try DownloadCache.instance.addImage(url: tempLocalUrl, maxWidthOrHeight: 300, previewFor: url);
                    completion(url, previewId);
                } catch _ {
                    //print("could not copy downloaded file!", writeError);
                    completion(url, "NONE");
                }
            } else {
                guard error == nil else {
                    if (error!._code == -1202 && error!._domain == "NSURLErrorDomain") {
                        completion(url, "ERROR:NSURLErrorServerCertificateUntrusted");
                    } else {
                        completion(url, "ERROR");
                    }
                    return;
                }
                
                //print("could not download file:", error?.localizedDescription);
                completion(url, "NONE");
            }
        }
        task.resume();
    }
    
    fileprivate static func downloadPreviewGetHeaders(session: URLSession, url: URL, completion: @escaping (Int, Error?, String?, Int64?)->Void) {
        var request = URLRequest(url: url);
        request.httpMethod = "HEAD";
        session.dataTask(with: request) { (data, resp, error) in
            let response = resp as? HTTPURLResponse;
            completion(response?.statusCode ?? 500, error, response?.mimeType, response?.expectedContentLength);
            }.resume();
    }
    
    fileprivate static let todaysFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateStyle = .none;
        f.timeStyle = .short;
        return f;
    })();
    fileprivate static let defaultFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM", options: 0, locale: NSLocale.current);
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    fileprivate static let fullFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy", options: 0, locale: NSLocale.current);
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    
    fileprivate static let tooltipFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.locale = NSLocale.current;
        f.dateStyle = .medium
        f.timeStyle = .medium;
        return f;
    })();


}
