//
// BaseChatAttachmentCellView.swift
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
import TigaseSwift
import LinkPresentation
import AVFoundation

class ChatAttachmentCellView: BaseChatCellView {

    @IBOutlet var customView: NSView!;
    @IBOutlet var downloadButton: NSButton?;
    @IBOutlet var actionButton: NSPopUpButton? {
        didSet {
            if let btn = self.actionButton {
                NotificationCenter.default.addObserver(self, selector: #selector(willShowPopup), name: NSPopUpButton.willPopUpNotification, object: btn);
            }
        }
    }
    
    fileprivate var progressIndicator: NSProgressIndicator? {
        didSet {
            if let value = oldValue {
                value.stopAnimation(self);
                value.removeFromSuperview();
            }
            if let value = progressIndicator {
                value.translatesAutoresizingMaskIntoConstraints = false;
                value.isIndeterminate = true;
                value.style = .spinning;
                self.customView.addSubview(value);
                NSLayoutConstraint.activate([
                    self.customView.centerYAnchor.constraint(equalTo: value.centerYAnchor),
                    self.customView.leadingAnchor.constraint(equalTo: value.leadingAnchor, constant: -12),
                    self.customView.heightAnchor.constraint(greaterThanOrEqualTo: value.heightAnchor),
                    self.customView.widthAnchor.constraint(greaterThanOrEqualTo: value.widthAnchor)
                ]);
                value.startAnimation(self);
                self.downloadButton?.isHidden = true;
            } else {
                self.downloadButton?.isHidden = false;
            }
        }
    }
    
    fileprivate var direction: MessageDirection? = nil;
    fileprivate var item: ConversationEntry?;

    var customTrackingArea: NSTrackingArea?;
    
    deinit {
        if #available(macOS 10.15, *) {
            for item in self.customView.subviews.filter({ $0 is LPLinkView}) {
                if let it = item as? LPLinkViewPool.PoolableLPLinkView {
                    LPLinkViewPool.instance.release(linkView: it);
                }
            }
        }
    }
    
    
    
    func set(item: ConversationEntry, url: String, appendix: ChatAttachmentAppendix) {
        self.item = item;
        super.set(item: item);
        self.direction = item.state.direction;
                
        let subviews = self.customView.subviews;
        subviews.forEach { (view) in
            if let it = view as? LPLinkViewPool.PoolableLPLinkView {
                LPLinkViewPool.instance.release(linkView: it)
            }
            view.removeFromSuperview();
        }
        customView.trackingAreas.forEach { (area) in
            customView.removeTrackingArea(area)
        }
        
        self.progressIndicator = nil;

        guard case let .attachment(url, appendix) = item.payload else {
            return;
        }
        
        if !(appendix.mimetype?.starts(with: "audio/") ?? false), let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            self.downloadButton?.isEnabled = false;
            self.downloadButton?.isHidden = true;
            self.actionButton?.isEnabled = true;
            self.actionButton?.isHidden = false;
            var metadata = MetadataCache.instance.metadata(for: "\(item.id)");
//                metadata?.videoProvider = nil;
            var isNew = false;

            if (metadata == nil) {
                metadata = LPLinkMetadata();
                metadata!.originalURL = localUrl;
                isNew = true;
            }
                
            let linkView = LPLinkViewPool.instance.acquire(url: localUrl);
                
            linkView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
            linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
            linkView.translatesAutoresizingMaskIntoConstraints = false;
            linkView.metadata = metadata!;
                
            self.customView.addSubview(linkView);

            NSLayoutConstraint.activate([
                linkView.topAnchor.constraint(equalTo: self.customView.topAnchor, constant: 0),
                linkView.bottomAnchor.constraint(equalTo: self.customView.bottomAnchor, constant: 0),
                linkView.leadingAnchor.constraint(equalTo: self.customView.leadingAnchor, constant: 0),
                linkView.trailingAnchor.constraint(equalTo: self.customView.trailingAnchor, constant: 0)
            ]);
                
            if isNew {
                MetadataCache.instance.generateMetadata(for: localUrl, withId: "\(item.id)", completionHandler: { [weak linkView] meta1 in
                    guard let meta = meta1 else {
                        return;
                    }
                    DispatchQueue.main.async {
                        guard let linkView = linkView, linkView.metadata.originalURL == localUrl else {
                            return;
                        }
                        linkView.metadata = meta;
                    }
                })
            }
        } else {
            self.downloadButton?.isEnabled = (appendix.state != .gone && appendix.state != .downloaded);
            self.downloadButton?.isHidden = (appendix.state == .gone || appendix.state == .downloaded);
            self.actionButton?.isEnabled = appendix.state == .downloaded;
            self.actionButton?.isHidden = appendix.state != .downloaded;
            
            let attachmentInfo = AttachmentInfoView(frame: .zero);
            attachmentInfo.cellView = self;
            self.customView.addSubview(attachmentInfo);
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: attachmentInfo.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: attachmentInfo.trailingAnchor),
                customView.topAnchor.constraint(equalTo: attachmentInfo.topAnchor),
                customView.bottomAnchor.constraint(equalTo: attachmentInfo.bottomAnchor)
            ])
            attachmentInfo.set(item: item, url: url, appendix: appendix);
            
            switch appendix.state {
            case .new:
                let sizeLimit = Settings.fileDownloadSizeLimit;
                if sizeLimit > 0 {
                    if (DBRosterStore.instance.item(for: item.conversation.account, jid: JID(item.conversation.jid))?.subscription ?? .none).isFrom || (DBChatStore.instance.conversation(for: item.conversation.account, with: item.conversation.jid) as? Room != nil) {
                        _ = DownloadManager.instance.download(item: item, url: url, maxSize: Int64(sizeLimit));
                        progressIndicator = NSProgressIndicator();
                        return;
                    }
                }
                if DownloadManager.instance.downloadInProgress(for: item) {
                    progressIndicator = NSProgressIndicator();
                }
            default:
                if DownloadManager.instance.downloadInProgress(for: item) {
                    progressIndicator = NSProgressIndicator();
                }
            }
        }
    }
    
    @IBAction func downloadClicked(_ sender: Any) {
        guard let item = self.item, case .attachment(let url, _) = item.payload else {
            return;
        }
        
        guard DownloadStore.instance.url(for: "\(item.id)") != nil else {
            _ = DownloadManager.instance.download(item: item, url: url, maxSize: Int64.max);
            self.progressIndicator = NSProgressIndicator();
            return;
        }
    }
    
    @objc func willShowPopup(_ notification: Notification) {
        guard let btn = notification.object as? NSPopUpButton, self.actionButton == btn else {
            return;
        }
        
        guard let menu = btn.menu?.item(withTitle: NSLocalizedString("Share", comment: "Share menu title"))?.submenu else {
            return;
        }
        
        menu.removeAllItems();
        
        guard let item = self.item else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        
        let sharingServices = NSSharingService.sharingServices(forItems: [localUrl]);
        for service in sharingServices {
            let item = menu.addItem(withTitle: service.title, action: nil, keyEquivalent: "");
            item.image = service.image;
            item.target = self;
            item.action = #selector(shareItemSelected);
            item.isEnabled = true;
        }
    }

    @objc func shareItemSelected(_ menuItem: NSMenuItem) {
        guard let item = self.item else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        
        NSSharingService.sharingServices(forItems: [localUrl]).first(where: { (service) -> Bool in
            service.title == menuItem.title;
        })?.perform(withItems: [localUrl]);
    }
    
    @IBAction func openFile(_ sender: Any) {
        guard let item = self.item else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        NSWorkspace.shared.open(localUrl);
    }
    
    @IBAction func copyFile(_ sender: Any) {
        guard let item = self.item else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        NSPasteboard.general.clearContents();
        NSPasteboard.general.setString(localUrl.absoluteString, forType: .fileURL);
    }
    
    @IBAction func saveFile(_ sender: Any) {
        guard let item = self.item else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            return;
        }
        let savePanel = NSSavePanel();
        let ext = localUrl.pathExtension;
        if !ext.isEmpty {
            savePanel.allowedFileTypes = [ext];
        }
        savePanel.nameFieldStringValue = localUrl.lastPathComponent;
        savePanel.allowsOtherFileTypes = true;
        savePanel.beginSheetModal(for: self.window!, completionHandler: { response in
            guard response == NSApplication.ModalResponse.OK, let url = savePanel.url else {
                return;
            }
            try? FileManager.default.copyItem(at: localUrl, to: url);
        })
    }

    @IBAction func deleteFile(_ sender: Any) {
        guard let item = self.item else {
            return;
        }
        DownloadStore.instance.deleteFile(for: "\(item.id)");
        DBChatHistoryStore.instance.updateItem(for: item.conversation, id: item.id, updateAppendix: { appendix in
            appendix.state = .removed;
        })
    }
    
    func infoClicked() {
        guard let item = self.item else {
            return;
        }
        if DownloadStore.instance.url(for: "\(item.id)") != nil {
            self.openFile(self);
        } else {
            self.downloadClicked(self);
        }
    }
    
    
    override func layout() {
        if Settings.alternateMessageColoringBasedOnDirection {
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
    }
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize);
        for subview in customView.subviews {
            if let info = subview as? AttachmentInfoView {
                info.iconView.widthConstraint?.constant = min(350, self.frame.width - 98);
            }
        }
    }
    
    class AttachmentInfoView: NSView, AVAudioPlayerDelegate {
        
        static let timeFormatter: DateComponentsFormatter = {
            let formatter = DateComponentsFormatter();
            formatter.unitsStyle = .abbreviated;
            formatter.zeroFormattingBehavior = .dropAll;
            formatter.allowedUnits = [.minute,.second]
            return formatter;
        }();
        
        let iconView: ImageAttachmentPreview;
        let filename: NSTextField;
        let details: NSTextField;
        let actionButton: NSButton!;
        
        weak var cellView: ChatAttachmentCellView?;
        
        private var viewType: ViewType = .none {
            didSet {
                guard viewType != oldValue else {
                    return;
                }
                switch oldValue {
                case .none:
                    break;
                case .audioFile:
                    NSLayoutConstraint.deactivate(audioFileViewConstraints);
                case .file:
                    NSLayoutConstraint.deactivate(fileViewConstraints);
                case .imagePreview:
                    NSLayoutConstraint.deactivate(imagePreviewConstraints);
                }
                switch viewType {
                case .none:
                    break;
                case .audioFile:
                    NSLayoutConstraint.activate(audioFileViewConstraints);
                case .file:
                    NSLayoutConstraint.activate(fileViewConstraints);
                case .imagePreview:
                    NSLayoutConstraint.activate(imagePreviewConstraints);
                }
                iconView.isImagePreview = viewType == .imagePreview;
            }
        }
        private var audioFileViewConstraints: [NSLayoutConstraint] = [];
        private var fileViewConstraints: [NSLayoutConstraint] = [];
        private var imagePreviewConstraints: [NSLayoutConstraint] = [];
        private var fileUrl: URL?;
        
        override init(frame: NSRect) {
            iconView = ImageAttachmentPreview(frame: .zero);
            iconView.imageScaling = .scaleProportionallyUpOrDown;
            iconView.image = NSWorkspace.shared.icon(forFileType: "image/png");
            iconView.translatesAutoresizingMaskIntoConstraints = false;
            iconView.setContentHuggingPriority(.defaultHigh, for: .vertical);
            iconView.setContentHuggingPriority(.defaultHigh, for: .horizontal);
//            iconView.setContentHuggingPriority(.defaultHigh, for: .vertical);
            iconView.setContentCompressionResistancePriority(.defaultLow, for: .vertical);
            //iconView.setContentCompressionResistancePriority(.fittingSizeCompression, for: .vertical);
            iconView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);

            filename = NSTextField(labelWithString: "File");
            filename.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .semibold);
            filename.textColor = NSColor.labelColor;
            filename.setContentHuggingPriority(.defaultLow, for: .horizontal)
            filename.translatesAutoresizingMaskIntoConstraints = false;
            
            actionButton = NSButton(image: NSImage(named: "play.circle.fill")!, target: nil, action: nil);
            actionButton.translatesAutoresizingMaskIntoConstraints = false;
            actionButton.isBordered = false;
            actionButton.contentTintColor = NSColor.secondaryLabelColor;
            
            details = NSTextField(labelWithString: "");
            details.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2, weight: .regular);
            details.textColor = NSColor.secondaryLabelColor;
            details.setContentHuggingPriority(.defaultLow, for: .horizontal)
            details.translatesAutoresizingMaskIntoConstraints = false;

            super.init(frame: frame);
            self.translatesAutoresizingMaskIntoConstraints = false;
            
            self.addSubview(iconView);
            self.addSubview(filename);
            self.addSubview(details);
            self.addSubview(actionButton);
            
            fileViewConstraints = [
                iconView.heightAnchor.constraint(equalToConstant: 30),
                
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
                iconView.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                iconView.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                
                filename.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
                filename.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                filename.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
                
                details.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
                details.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 0),
                details.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                details.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
                
                actionButton.heightAnchor.constraint(equalToConstant: 0),
                actionButton.widthAnchor.constraint(equalToConstant: 0),
                actionButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0),
                actionButton.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0)
            ];
            
            audioFileViewConstraints = [
                iconView.heightAnchor.constraint(equalToConstant: 30),
                iconView.widthAnchor.constraint(equalTo: iconView.heightAnchor),
                
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 10),
                iconView.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                iconView.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor, constant: 8),
//                iconView.bottomAnchor.constraint(lessThanOrEqualTo: self.bottomAnchor, constant: -8),
                
                filename.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                filename.topAnchor.constraint(equalTo: self.topAnchor, constant: 8),
                filename.trailingAnchor.constraint(equalTo: self.actionButton.leadingAnchor, constant: -10),
                
                details.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 10),
                details.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 4),
                details.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                // -- this is causing issue with progress indicatior!!
                details.trailingAnchor.constraint(equalTo: self.actionButton.leadingAnchor, constant: -10),
                
                actionButton.heightAnchor.constraint(equalToConstant: 30),
                actionButton.widthAnchor.constraint(equalTo: actionButton.heightAnchor),
                actionButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -10),
                actionButton.centerYAnchor.constraint(equalTo: self.centerYAnchor),
                actionButton.topAnchor.constraint(greaterThanOrEqualTo: self.topAnchor, constant: 8)
            ];
            
            imagePreviewConstraints = [
                iconView.widthAnchor.constraint(lessThanOrEqualToConstant: 350),
                iconView.heightAnchor.constraint(lessThanOrEqualToConstant: 350),
                iconView.widthAnchor.constraint(lessThanOrEqualTo: self.widthAnchor),
                
                iconView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                iconView.topAnchor.constraint(equalTo: self.topAnchor),
                iconView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                
                filename.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
                filename.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
                filename.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
                
                details.leadingAnchor.constraint(equalTo: self.leadingAnchor, constant: 12),
                details.topAnchor.constraint(equalTo: filename.bottomAnchor, constant: 0),
                details.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: -8),
                details.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: -12),
                
                actionButton.heightAnchor.constraint(equalToConstant: 0),
                actionButton.widthAnchor.constraint(equalToConstant: 0),
                actionButton.trailingAnchor.constraint(equalTo: self.trailingAnchor, constant: 0),
                actionButton.bottomAnchor.constraint(equalTo: self.bottomAnchor, constant: 0)
            ];
            
            actionButton.target = self;
            actionButton.action = #selector(actionTapped(_:));
        }
        
        required init?(coder: NSCoder) {
            return nil;
        }
        
        override func prepareForReuse() {
            self.stopPlayingAudio();
            super.prepareForReuse();
        }
        
        override func mouseDown(with event: NSEvent) {
            cellView?.infoClicked();
        }
        
        override func layout() {
            super.layout();
        }
        
        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.saveGraphicsState();
            
            let path = NSBezierPath(roundedRect: dirtyRect, xRadius: 10, yRadius: 10);
            path.addClip();
            NSColor.separatorColor.setFill();
            path.fill();
                        
            super.draw(dirtyRect);
            NSGraphicsContext.restoreGraphicsState();
        }
                
        func set(item: ConversationEntry, url: String, appendix: ChatAttachmentAppendix) {
            self.fileUrl = DownloadStore.instance.url(for: "\(item.id)")
            if let fileUrl = self.fileUrl {
                filename.stringValue = fileUrl.lastPathComponent;
                let fileSize = fileSizeToString(try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.size] as? UInt64);
                if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileUrl.pathExtension as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                    details.stringValue = "\(typeName) - \(fileSize)";
                    if UTTypeConformsTo(uti, kUTTypeImage) {
                        self.viewType = .imagePreview;
                        iconView.image = NSImage(contentsOf: fileUrl);
                    } else if UTTypeConformsTo(uti, kUTTypeAudio) {
                        self.viewType = .audioFile;
                        let asset = AVURLAsset(url: fileUrl);
                        asset.loadValuesAsynchronously(forKeys: ["duration"], completionHandler: {
                            DispatchQueue.main.async {
                                guard self.fileUrl == fileUrl else {
                                    return;
                                }
                                if asset.duration != .invalid && asset.duration != .zero {
                                    let length = CMTimeGetSeconds(asset.duration);
                                    if let lengthStr = AttachmentInfoView.timeFormatter.string(from: length) {
                                        self.details.stringValue = "\(typeName) - \(fileSize) - \(lengthStr)";
                                    }
                                }
                            }
                        });
                        iconView.image = NSWorkspace.shared.icon(forFile: fileUrl.path);
                    } else {
                        self.viewType = .file;
                        iconView.image = NSWorkspace.shared.icon(forFile: fileUrl.path);
                    }
                } else {
                    details.stringValue = fileSize;
                    iconView.image = NSWorkspace.shared.icon(forFile: fileUrl.path);
                    self.viewType = .file;
                }
            } else {
                let filename = appendix.filename ?? URL(string: url)?.lastPathComponent ?? "";
                if filename.isEmpty {
                    self.filename.stringValue = NSLocalizedString("Unknown file", comment: "Unknown file");
                } else {
                    self.filename.stringValue = filename;
                }
                if let size = appendix.filesize {
                    if let mimetype = appendix.mimetype, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                        let fileSize = size >= 0 ? fileSizeToString(UInt64(size)) : "--";
                        details.stringValue = "\(typeName) - \(fileSize)";
                        iconView.image = NSWorkspace.shared.icon(forFileType: uti as String);
                    } else {
                        details.stringValue = fileSizeToString(UInt64(size));
                        iconView.image = NSWorkspace.shared.icon(forFileType: "");
                    }
                } else {
                    details.stringValue = "--";
                    iconView.image = NSWorkspace.shared.icon(forFileType: "");
                }
                self.viewType = .file;
            }
        }
        
        func fileSizeToString(_ sizeIn: UInt64?) -> String {
            guard let size = sizeIn else {
                return "";
            }
            let formatter = ByteCountFormatter();
            formatter.countStyle = .file;
            return formatter.string(fromByteCount: Int64(size));
        }
        
        private var audioPlayer: AVAudioPlayer?;
        
        private func startPlayingAudio() {
            stopPlayingAudio();
            guard let fileUrl = self.fileUrl else {
                return;
            }
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: fileUrl);
                audioPlayer?.delegate = self;
                audioPlayer?.volume = 1.0;
                audioPlayer?.play();
                self.actionButton.image = NSImage(named: "stop.circle.fill");
            } catch {
                self.stopPlayingAudio();
            }
        }
        
        private func stopPlayingAudio() {
            audioPlayer?.stop();
            audioPlayer = nil;
            self.actionButton.image = NSImage(named: "play.circle.fill");
        }
        
        @objc func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            audioPlayer?.stop();
            audioPlayer = nil;
            self.actionButton.image = NSImage(named: "play.circle.fill");
        }
        
        @objc func actionTapped(_ sender: Any) {
            if audioPlayer == nil {
                self.startPlayingAudio();
            } else {
                self.stopPlayingAudio();
            }
        }
        
        enum ViewType {
            case none
            case audioFile
            case file
            case imagePreview
        }
    }
    
}

class ImageAttachmentPreview: NSImageView {
    
    var isImagePreview: Bool = false {
        didSet {
            widthConstraint?.isActive = isImagePreview;
        }
    }
    
    var ratioConstraint: NSLayoutConstraint?;
    var widthConstraint: NSLayoutConstraint?;
    
    override init(frame: NSRect) {
        super.init(frame: frame);
        
        widthConstraint = self.widthAnchor.constraint(equalToConstant: 0);
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var image: NSImage? {
        didSet {
            if let constraint = ratioConstraint {
                self.removeConstraint(constraint);
                ratioConstraint = nil;
            }
            if let value = image {
                ratioConstraint = self.heightAnchor.constraint(equalTo: self.widthAnchor, multiplier: value.size.height / value.size.width);
                NSLayoutConstraint.activate([ratioConstraint!])
            }
        }
    }
        
    override func draw(_ dirtyRect: NSRect) {
        if isImagePreview {
        NSGraphicsContext.saveGraphicsState();
        
            let path = NSBezierPath(roundedRect: NSRect(x: dirtyRect.minX, y: dirtyRect.minY - 10.0, width: dirtyRect.width, height: dirtyRect.height + 10), xRadius: 10, yRadius: 10);
        path.addClip();
        NSColor.separatorColor.setFill();
        path.fill();
                    
        super.draw(dirtyRect);
        NSGraphicsContext.restoreGraphicsState();
        }  else {
            super.draw(dirtyRect);
        }
    }
    
    override func layout() {
        super.layout();
    }
}
