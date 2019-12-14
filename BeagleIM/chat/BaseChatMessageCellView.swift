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
import LinkPresentation
import TigaseSwift

class BaseChatMessageCellView: NSTableCellView {

    fileprivate static let imageLoadingQueue = DispatchQueue(label: "image_loading_queue");

    fileprivate static let allowedUrlPreviewSchemas = [ "https://", "http://", "file://" ];

    var id: Int = 0;

    @IBOutlet var message: NSTextField!
    @IBOutlet var state: NSTextField?;
    @IBOutlet var previews: Previews?;
    fileprivate var direction: MessageDirection? = nil;

    func set(message item: ChatMessage, nickname: String? = nil, keywords: [String]? = nil) {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue);

        let messageBody = self.messageBody(item: item);
        let matches = detector.matches(in: messageBody, range: NSMakeRange(0, messageBody.utf16.count));
        let msg = NSMutableAttributedString(string: messageBody);
//        var previewsToRetrive: [URL] = [];
//        var previewsToLoad: [(URL,String)] = [];
        var errors: [String] = [];

        var urls: [URL] = [];
        var previewsToShow: [URL] = [];

        matches.forEach { match in
            if var url = match.url {
                msg.addAttribute(.link, value: url, range: match.range);
            }
            if let phoneNumber = match.phoneNumber {
                msg.addAttribute(.link, value: URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "-"))")!, range: match.range);
            }
            if let address = match.components {
                let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                msg.addAttribute(.link, value: mapUrl, range: match.range);
                if #available(macOS 10.15, *) {
                    previewsToShow.append(mapUrl);
                }
            }
        }
        msg.addAttribute(NSAttributedString.Key.font, value: self.message.font!, range: NSMakeRange(0, msg.length));

        if Settings.enableMarkdownFormatting.bool() {
            Markdown.applyStyling(attributedString: msg, showEmoticons: Settings.showEmoticons.bool());
        }
        if let nick = nickname {
            msg.markMention(of: nick, withColor: NSColor.systemBlue, bold: Settings.boldKeywords.bool());
        }
        if let keys = keywords {
            msg.mark(keywords: keys, withColor: NSColor.systemRed, bold: Settings.boldKeywords.bool());
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

        if let previews = self.previews {
            previews.clear();
        }
//            if previewsToShow.isEmpty {
//                previews.clear();
//            } else {
//                if #available(macOS 10.15, *) {
//                    let msgId = item.id;
//                    var metadatas: [LPLinkMetadata] = [];
//
//                    for url in previewsToShow {
//                        if let result = item.preview?[url.absoluteString] {
//                            switch result {
//                            case .success(let previewId):
//                                if let metadata = MetadataCache.instance.metadata(for: previewId) {
//                                    metadatas.append(metadata);
//                                } else if let url = DownloadStore.instance.url(for: previewId) {
//                                    MetadataCache.instance.generateMetadata(for: url, withId: <#T##String#>, completionHandler: { meta in
//                                        // now we have meta..
//                                        if let metadata = meta {
//                                            DispatchQueue.main.async { [weak self] in
//                                                guard let that = self, that.id == msgId else {
//                                                    return;
//                                                }
//                                                metadatas.append(metadata);
//                                                previews.set(previews: metadatas.map({ meta in LPLinkView(metadata: meta) }));
//                                            }
//                                        } else {
//                                            // we cannot do anything.. maybe the file is missing..
//                                        }
//                                    })
//                                } else {
//                                    // do we have anything to do here? most likely not
//                                }
//                            case .failure(let err):
//                                // there was an error, skipping preview for this url...
//                                break;
//                            }
//                        } else {
//                            // we need to try to download it
//                            DownloadManager.instance.downloadFile(destination: DownloadStore.instance, url: url, maxSize: Int64(Settings.imageDownloadSizeLimit.integer()), excludedMimetypes: ["text/html"], completionHandler: { result in
//                                switch result {
//                                case .success(let downloadId):
//                                    // we need to generate preview from download...
//                                    if let localUrl = DownloadStore.instance.url(for: downloadId) {
//                                        DispatchQueue.main.async {
//                                            var values: [String: Result<String,PreviewError>] = item.preview ?? [:];
//                                            values[url.absoluteString] = .success(downloadId);
//                                            DBChatHistoryStore.instance.updateItem(for: item.account, with: item.jid, id: item.id, preview: values);
//                                        }
//                                        MetadataCache.instance.generateMetadata(for: localUrl, withId: downloadId, completionHandler: { meta in
//                                            // now we have meta..
//                                            if let metadata = meta {
//                                                DispatchQueue.main.async { [weak self] in
//                                                    guard let that = self, that.id == msgId else {
//                                                        return;
//                                                    }
//                                                    metadatas.append(metadata);
//                                                    previews.set(previews: metadatas.map({ meta in LPLinkView(metadata: meta) }));
//                                                }
//
//                                                UPDATE PREVIEW IDs...
//
//                                            } else {
//                                                // we cannot do anything.. maybe the file is missing..
//                                            }
//                                        })
//                                    }
//                                case .failure(let downloadError):
//                                    switch downloadError {
//                                        case .networkError(let err):
//                                            // we should retry later on..
//                                            break;
//                                        case .responseError(let err):
//                                            // we should retry later on.. or just drop it..
//                                            break;
//                                        case .tooBig(_), .badMimeType(_):
//                                            // lets generate metadata from original URL
//                                            let previewId = UUID().uuidString;
//                                            MetadataCache.instance.generateMetadata(for: url, withId: previewId, completionHandler: { meta in
//                                                // now we have meta..
//                                                if let metadata = meta {
//                                                    DispatchQueue.main.async { [weak self] in
//                                                        guard let that = self, that.id == msgId else {
//                                                            return;
//                                                        }
//                                                        metadatas.append(metadata);
//                                                        previews.set(previews: metadatas.map({ meta in LPLinkView(metadata: meta) }));
//                                                    }
//
//                                                    UPDATE PREVIEW IDs...
//
//                                                } else {
//                                                    // we cannot do anything.. maybe the file is missing..
//                                                }
//                                            })
//                                            break;
//                                    }
//                                }
//                            });
//                        }
//                    }
//
//                    previews.set(previews: metadatas.map({ meta in LPLinkView(metadata: meta) }));
//                } else {
//
//                }
//            }
//        } else {
//          // nothing to do..
//        }
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
//        if let width = self.superview?.superview?.frame.width {
//            if self.state != nil {
//                self.message.preferredMaxLayoutWidth = width - 68;
//            } else {
//                self.message.preferredMaxLayoutWidth = width - 50;
//            }
//        }
        super.layout();
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

@available(OSX 10.15, *)
class MetadataCache {

    static let instance = MetadataCache();

    private var cache: [URL: Result<LPLinkMetadata, MetadataCache.CacheError>] = [:];
    private let diskCacheUrl: URL;
    private let dispatcher = QueueDispatcher(label: "MetadataCache");

    private var inProgress: [URL: OperationQueue] = [:];
    
    init() {
        diskCacheUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true).appendingPathComponent("metadata", isDirectory: true);
        if !FileManager.default.fileExists(atPath: diskCacheUrl.path) {
            try! FileManager.default.createDirectory(at: diskCacheUrl, withIntermediateDirectories: true, attributes: nil);
        }
    }

    func store(_ value: LPLinkMetadata, for id: String) {
        let fileUrl = diskCacheUrl.appendingPathComponent("\(id).metadata");
        guard let codedData = try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false) else {
            return;
        }

        try? codedData.write(to: fileUrl);
    }

    func metadata(for id: String) -> LPLinkMetadata? {
        guard let data = FileManager.default.contents(atPath: diskCacheUrl.appendingPathComponent("\(id).metadata").path) else {
            return nil;
        }

        return try! NSKeyedUnarchiver.unarchivedObject(ofClass: LPLinkMetadata.self, from: data);
    }

    func generateMetadata(for url: URL, withId id: String, completionHandler: @escaping (LPLinkMetadata?)->Void) {
        dispatcher.async {
            if let queue = self.inProgress[url] {
                queue.addOperation {
                    completionHandler(self.metadata(for: id));
                }
            } else {
                let queue = OperationQueue();
                queue.isSuspended = true;
                self.inProgress[url] = queue;
                
                queue.addOperation {
                    completionHandler(self.metadata(for: id));
                }
                
                DispatchQueue.main.async {
                    let provider = LPMetadataProvider();
                    provider.startFetchingMetadata(for: url, completionHandler: { (meta, error) in
                        if let metadata = meta {
                            self.store(metadata, for: id);
                        } else {
                            print("failed to download metadata for:", url);
                            let metadata = LPLinkMetadata();
                            metadata.originalURL = url;
                            self.store(metadata, for: id);
                        }
                        self.dispatcher.async {
                            self.inProgress.removeValue(forKey: url);
                            queue.isSuspended = false;
                        }
                    })
                }
            }
        }
    }

    enum CacheError: Error {
        case NO_DATA
        case RETRIEVAL_ERROR
    }
}

class Previews: NSView {

    func clear() {
        let subviews = self.subviews;
        subviews.forEach { (view) in
            view.removeFromSuperview();
        }

        self.removeConstraints(self.constraints);
        self.heightAnchor.constraint(equalToConstant: 0).isActive = true;
    }

    @available(macOS 10.15, *)
    func add(preview linkView: LPLinkView) {
        self.removeConstraints(self.constraints);

        linkView.setContentHuggingPriority(.defaultLow, for: .vertical);
        linkView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        linkView.translatesAutoresizingMaskIntoConstraints = false;

        self.addSubview(linkView);

        linkView.heightAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true;

        linkView.topAnchor.constraint(equalTo: self.topAnchor, constant: 0).isActive = true;
        linkView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0).isActive = true;
        linkView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0).isActive = true;
        linkView.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: 0).isActive = true;
    }

    @available(macOS 10.15, *)
    func set(previews: [LPLinkView]) {
        let subviews = self.subviews;
        subviews.forEach { (view) in
            view.removeFromSuperview();
        }

        self.removeConstraints(self.constraints);

        var constraints: [NSLayoutConstraint] = [];

        var topAnchor: NSLayoutYAxisAnchor = self.topAnchor;

        for linkView in previews {
            linkView.setContentHuggingPriority(.defaultLow, for: .vertical);
            linkView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
            linkView.translatesAutoresizingMaskIntoConstraints = false;

            self.addSubview(linkView);

            constraints.append(contentsOf: [
                linkView.heightAnchor.constraint(lessThanOrEqualToConstant: 200),
                linkView.topAnchor.constraint(equalTo: topAnchor, constant: 4),
                linkView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 0),
                linkView.trailingAnchor.constraint(lessThanOrEqualTo: self.trailingAnchor, constant: 0)
            ]);

            topAnchor = linkView.bottomAnchor;
        }
        constraints.append(self.bottomAnchor.constraint(equalTo: topAnchor, constant: 0));

        NSLayoutConstraint.activate(constraints);
    }
}
