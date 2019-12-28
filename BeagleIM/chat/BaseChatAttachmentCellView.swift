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
            if #available(macOS 10.15, *) {
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
                        DispatchQueue.main.async {
                            linkView?.metadata = meta;
                        }
                    })
                }
            } else {
                let attachmentInfo = AttachmentInfoView(frame: .zero);
                self.customView.addSubview(attachmentInfo);
                attachmentInfo.cellView = self;
                NSLayoutConstraint.activate([
                    customView.leadingAnchor.constraint(equalTo: attachmentInfo.leadingAnchor),
                    customView.trailingAnchor.constraint(equalTo: attachmentInfo.trailingAnchor),
                    customView.topAnchor.constraint(equalTo: attachmentInfo.topAnchor),
                    customView.bottomAnchor.constraint(equalTo: attachmentInfo.bottomAnchor)
                ])
                attachmentInfo.set(item: item);
            }
        } else {
            self.downloadButton?.isEnabled = item.appendix.state != .gone;
            self.downloadButton?.isHidden = item.appendix.state == .gone;
            self.actionButton?.isEnabled = false;
            self.actionButton?.isHidden = true;
            
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
            
            switch item.appendix.state {
            case .new:
                let sizeLimit = Settings.fileDownloadSizeLimit.integer();
                if sizeLimit > 0 {
                    if let client = XmppService.instance.getClient(for: item.account), (client.rosterStore?.get(for: JID(item.jid))?.subscription ?? .none).isFrom || (DBChatStore.instance.getChat(for: item.account, with: item.jid) as? Room != nil) {
                        DownloadManager.instance.download(item: item, maxSize: Int64(sizeLimit));
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
        guard let item = self.item else {
            return;
        }
        
        guard let localUrl = DownloadStore.instance.url(for: "\(item.id)") else {
            DownloadManager.instance.download(item: item, maxSize: Int64.max);
            self.progressIndicator = NSProgressIndicator();
            return;
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
        DBChatHistoryStore.instance.updateItem(for: item.account, with: item.jid, id: item.id, updateAppendix: { appendix in
            appendix.state = .removed;
        })
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
    
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize);
        for subview in customView.subviews {
            if let info = subview as? AttachmentInfoView {
                info.iconView.widthConstraint?.constant = min(350, self.frame.width - 98);
            }
        }
    }
    
    class AttachmentInfoView: NSView {
        
        let iconView: ImageAttachmentPreview;
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
                iconView.isImagePreview = viewType == .imagePreview;
            }
        }
        private var fileViewConstraints: [NSLayoutConstraint] = [];
        private var imagePreviewConstraints: [NSLayoutConstraint] = [];
        
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
                details.heightAnchor.constraint(equalTo: filename.heightAnchor)
            ];
        }
        
        required init?(coder: NSCoder) {
            return nil;
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
                let filename = item.appendix.filename ?? URL(string: item.url)?.lastPathComponent ?? "";
                if filename.isEmpty {
                    self.filename.stringValue =  "Unknown file";
                } else {
                    self.filename.stringValue = filename;
                }
                if let size = item.appendix.filesize {
                    if let mimetype = item.appendix.mimetype, let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassMIMEType, mimetype as CFString, nil)?.takeRetainedValue(), let typeName = UTTypeCopyDescription(uti)?.takeRetainedValue() as String? {
                        let fileSize = fileSizeToString(UInt64(size));
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
        
        enum ViewType {
            case none
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

class ChatAttachmentCellView: BaseChatAttachmentCellView {

    @IBOutlet var avatar: AvatarView!
    @IBOutlet var senderName: NSTextField!
    @IBOutlet var timestamp: NSTextField!
       
    func set(avatar: NSImage?) {
        self.avatar?.image = avatar;
    }
    
    func set(senderName: String?) {
        self.senderName.stringValue = senderName!;
        self.avatar?.name = senderName;
    }
       
    override func set(item: ChatAttachment) {
        var timestampStr: NSMutableAttributedString? = nil;

        switch item.encryption {
        case .decrypted, .notForThisDevice, .decryptionFailed:
            let secured = NSMutableAttributedString(string: "\u{1F512}");
            if timestampStr != nil {
                timestampStr?.append(secured);
            } else {
                timestampStr = secured;
            }
        default:
            break;
        }
           
        if timestampStr != nil {
            timestampStr!.append(item.state == .outgoing_unsent ? NSAttributedString(string: " Unsent") : NSMutableAttributedString(string: " " + formatTimestamp(item.timestamp)));
            self.timestamp.attributedStringValue = timestampStr!;
        } else {
            self.timestamp.attributedStringValue = item.state == .outgoing_unsent ? NSAttributedString(string: "Unsent") : NSMutableAttributedString(string: formatTimestamp(item.timestamp));
        }
        super.set(item: item);
    }
    
    func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return ChatAttachmentCellView.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return ChatAttachmentCellView.fullFormatter.string(from: ts);
        } else {
            return ChatAttachmentCellView.defaultFormatter.string(from: ts);
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

class ChatAttachmentContinuationCellView: BaseChatAttachmentCellView {

}
