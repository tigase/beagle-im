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

class BaseChatAttachmentCellView: NSTableCellView {

    @IBOutlet var customView: NSView!;
    @IBOutlet var state: NSTextField?;
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
    fileprivate var item: ChatAttachment?;

    var customTrackingArea: NSTrackingArea?;
    
    func set(item: ChatAttachment) {
        self.item = item;
        switch item.state {
        case .incoming_error, .incoming_error_unread:
            self.state?.stringValue = "\u{203c}";
        case .outgoing_unsent:
            self.state?.stringValue = "\u{1f4e4}";
        case .outgoing_delivered:
            self.state?.stringValue = "\u{2713}";
        case .outgoing_error, .outgoing_error_unread:
            self.state?.stringValue = "\u{203c}";
        default:
            self.state?.stringValue = "";
        }
        self.state?.textColor = item.state.isError ? NSColor.systemRed : NSColor.secondaryLabelColor;
        self.direction = item.state.direction;
        
//        self.actionButton?.wantsLayer = true;
//        self.actionButton?.layer?.backgroundColor = NSColor.red.cgColor;
//
//        self.downloadButton?.wantsLayer = true;
//        self.downloadButton?.layer?.backgroundColor = NSColor.orange.cgColor;
//
//        self.state?.wantsLayer = true;
//        self.state?.layer?.backgroundColor = NSColor.green.cgColor;
        
        let subviews = self.customView.subviews;
        subviews.forEach { (view) in
            view.removeFromSuperview();
        }
        customView.trackingAreas.forEach { (area) in
            customView.removeTrackingArea(area)
        }
        
        self.progressIndicator = nil;
        
        if let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            self.downloadButton?.isEnabled = false;
            self.downloadButton?.isHidden = true;
            self.actionButton?.isEnabled = true;
            self.actionButton?.isHidden = false;
            if #available(macOS 10.15, *), false {
                var metadata = MetadataCache.instance.metadata(for: "\(item.id)");
                var isNew = false;

                if (metadata == nil) {
                    metadata = LPLinkMetadata();
                    metadata!.originalURL = localUrl;
                    isNew = true;
                }
                
                let linkView = LPLinkView(metadata: metadata!);
                
                linkView.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
                linkView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
                linkView.translatesAutoresizingMaskIntoConstraints = false;

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
                        linkView?.metadata = meta;
                    })
                }
            } else {
                let attachmentInfo = AttachmentInfoView(frame: .zero);
                attachmentInfo.cellView = self;
                self.customView.addSubview(attachmentInfo);
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: attachmentInfo.leadingAnchor),
                    customView.trailingAnchor.constraint(equalTo: attachmentInfo.trailingAnchor),
                    customView.topAnchor.constraint(equalTo: attachmentInfo.topAnchor),
                    customView.bottomAnchor.constraint(equalTo: attachmentInfo.bottomAnchor)
                ])
                attachmentInfo.set(item: item);
            }
        } else {
            self.downloadButton?.isEnabled = true;
            self.downloadButton?.isHidden = false;
            self.actionButton?.isEnabled = false;
            self.actionButton?.isHidden = true;
            
//            let trackingArea = NSTrackingArea(rect: customView.frame, options: [.], owner: <#T##Any?#>, userInfo: <#T##[AnyHashable : Any]?#>)
//
//            let imageButton = NSButton(image: NSWorkspace.shared.icon(forFileType: "image/png"), target: self, action: #selector(downloadClicked(_:)));
            let attachmentInfo = AttachmentInfoView(frame: .zero);
            attachmentInfo.cellView = self;
            self.customView.addSubview(attachmentInfo);
            NSLayoutConstraint.activate([
                customView.leadingAnchor.constraint(equalTo: attachmentInfo.leadingAnchor),
                customView.trailingAnchor.constraint(equalTo: attachmentInfo.trailingAnchor),
                customView.topAnchor.constraint(equalTo: attachmentInfo.topAnchor),
                customView.bottomAnchor.constraint(equalTo: attachmentInfo.bottomAnchor)
            ])
            attachmentInfo.set(item: item);
            
            if DownloadManager.instance.downloadInProgress(for: URL(string: item.url)!, completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    guard let that = self, let id = that.item?.id, id == item.id else {
                        return;
                    }
                    that.downloadCompleted(result: result, item: item);
                }
            }) {
                progressIndicator = NSProgressIndicator();
            }
        }
    }

//    override func updateTrackingAreas() {
//        super.updateTrackingAreas();
//        if customTrackingArea == nil {
//            let trackingArea = NSTrackingArea(rect: self.frame, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil);
//            addTrackingArea(trackingArea);
//            customTrackingArea = trackingArea;
//        }
//    }
//
//    override func mouseEntered(with event: NSEvent) {
//        // is is not working as expected :/
//        //downloadButton?.isHidden = false;
//    }
//
//    override func mouseExited(with event: NSEvent) {
//        //downloadButton?.isHidden = true;
//    }
    
    @IBAction func downloadClicked(_ sender: Any) {
        guard let item = self.item else {
            return;
        }
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            let url = URL(string: item.url)!;
            
            self.progressIndicator = NSProgressIndicator();
            
            DownloadManager.instance.downloadFile(destination: DownloadStore.instance, as: "\(item.id)", url: url, maxSize: Int64.max, excludedMimetypes: [], completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    guard let that = self, let id = that.item?.id, id == item.id else {
                        return;
                    }
                    that.downloadCompleted(result: result, item: item);
                }
            })
            return;
        }
        
        //print("opening file:", localUrl);
        
//        let menu = NSMenu(title: "Actions");
    }
    
    func downloadCompleted(result: Result<String,DownloadManager.DownloadError>, item: ChatAttachment) {
        self.progressIndicator = nil;
        switch result {
        case .success(let localUrl):
            print("download completed!");
            guard let localItem = self.item, localItem.id == item.id else {
                return;
            }
            self.set(item: item);
            break;
        case .failure(let err):
            break;
        }
    }
    
    @objc func willShowPopup(_ notification: Notification) {
        guard let btn = notification.object as? NSPopUpButton, self.actionButton == btn else {
            return;
        }
        
        guard let menu = btn.menu?.item(withTitle: "Share")?.submenu else {
            return;
        }
        
        print("menu:", menu.items.map({ it in it.title }));
        
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
        print("menu:", menu.items.map({ it in it.title }));
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
    
    @IBAction func saveFile(_ sender: Any) {
        
    }

    @IBAction func deleteFile(_ sender: Any) {
        guard let item = self.item else {
            return;
        }
        DownloadStore.instance.deleteFile(for: "\(item.id)");
        self.set(item: item);
    }
    
    func infoClicked() {
        guard let item = self.item else {
            return;
        }
        if let localUrl = DownloadStore.instance.url(for: "\(item.id)") {
            self.openFile(self);
        } else {
            self.downloadClicked(self);
        }
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
    }
    
    class AttachmentInfoView: NSView {
        
        let iconView: NSImageView;
        let filename: NSTextField;
        let details: NSTextField;
        
        weak var cellView: BaseChatAttachmentCellView?;
        
        private var viewType: ViewType = .none {
            didSet {
                guard viewType != oldValue else {
                    return;
                }
                switch oldValue {
                case .none:
                    break;
                case .file:
                    NSLayoutConstraint.deactivate(fileViewConstraints);
                case .imagePreview:
                    NSLayoutConstraint.deactivate(imagePreviewConstraints);
                }
                switch viewType {
                    case .none:
                        break;
                    case .file:
                        NSLayoutConstraint.activate(fileViewConstraints);
                    case .imagePreview:
                        NSLayoutConstraint.activate(imagePreviewConstraints);
                }
            }
        }
        private var fileViewConstraints: [NSLayoutConstraint] = [];
        private var imagePreviewConstraints: [NSLayoutConstraint] = [];
        
        override init(frame: NSRect) {
            iconView = NSImageView(frame: .zero);
            iconView.imageScaling = .scaleProportionallyUpOrDown;
            iconView.image = NSWorkspace.shared.icon(forFileType: "image/png");
            iconView.translatesAutoresizingMaskIntoConstraints = false;

            filename = NSTextField(labelWithString: "File");
            filename.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .semibold);
            filename.textColor = NSColor.labelColor;
            filename.translatesAutoresizingMaskIntoConstraints = false;
            
            details = NSTextField(labelWithString: "");
            details.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 2, weight: .regular);
            details.textColor = NSColor.secondaryLabelColor;
            details.translatesAutoresizingMaskIntoConstraints = false;
            
            super.init(frame: frame);
            self.translatesAutoresizingMaskIntoConstraints = false;
            
            self.addSubview(iconView);
            self.addSubview(filename);
            self.addSubview(details);
            
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
                details.heightAnchor.constraint(equalTo: filename.heightAnchor)
            ];
            
            imagePreviewConstraints = [
//                iconView.heightAnchor.constraint(equalToConstant: 30),
                
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
                details.heightAnchor.constraint(equalTo: filename.heightAnchor)
            ];
        }
        
        required init?(coder: NSCoder) {
            return nil;
        }
        
        override func mouseDown(with event: NSEvent) {
            cellView?.infoClicked();
        }
        
        override func draw(_ dirtyRect: NSRect) {
            NSGraphicsContext.saveGraphicsState();
            
            let path = NSBezierPath(roundedRect: dirtyRect, xRadius: 10, yRadius: 10);
            path.addClip();
            NSColor.separatorColor.setFill();
            path.fill();
            
            NSGraphicsContext.restoreGraphicsState();
            
            super.draw(dirtyRect);
        }
                
        func set(item: ChatAttachment) {
            if let fileUrl = DownloadStore.instance.url(for: "\(item.id)") {
                filename.stringValue = fileUrl.lastPathComponent;
                let fileSize = fileSizeToString(try? FileManager.default.attributesOfItem(atPath: fileUrl.path)[.size] as? UInt64);
                if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, fileUrl.pathExtension as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                    details.stringValue = "\(typeName) - \(fileSize)";
                    if UTTypeConformsTo(uti, kUTTypeImage) {
                        self.viewType = .imagePreview;
                        iconView.image = NSImage(contentsOf: fileUrl);
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
                let filename = URL(string: item.url)?.lastPathComponent ?? "";
                if filename.isEmpty {
                    self.filename.stringValue =  "Unknown file";
                } else {
                    self.filename.stringValue = filename;
                }
                details.stringValue = "--";
                iconView.image = NSWorkspace.shared.icon(forFileType: "");
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
        
        enum ViewType {
            case none
            case file
            case imagePreview
        }
    }
}

class ChatAttachmentContinuationCellView: BaseChatAttachmentCellView {
    
}
