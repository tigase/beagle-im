//
// ChatViewController.swift
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
import Martin
import MartinOMEMO
import Combine
import TigaseLogging

class ChatViewController: AbstractChatViewControllerWithSharing, ConversationLogContextMenuDelegate, NSMenuItemValidation {

    @IBOutlet var buddyAvatarView: AvatarViewWithStatus!
    @IBOutlet var buddyNameLabel: NSTextFieldCell!
    @IBOutlet var buddyJidLabel: NSTextFieldCell!
    @IBOutlet var buddyStatusLabel: NSTextField!;

    fileprivate var lastTextChange: Date = Date();
    fileprivate var lastTextChangeTimer: Foundation.Timer?;

    @IBOutlet var audioCall: NSButton!
    @IBOutlet var videoCall: NSButton!
    @IBOutlet var infoButton: NSButton!;

    @IBOutlet var scriptsButton: NSPopUpButton!;

    @IBOutlet var encryptButton: DropDownButton!;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    var chat: Chat {
        return conversation as! Chat;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        self.encryptButton = createEncryptButton();
        bottomView.addView(self.encryptButton, in: .trailing)

        audioCall.isHidden = false;
        videoCall.isHidden = false;
        scriptsButton.isHidden = true;
    }

    func createEncryptButton() -> DropDownButton {
        let buttonSize = NSFont.systemFontSize * 2;
        let encryptButton = DropDownButton();
        let menu = NSMenu(title: "");
        let unencrypedItem = NSMenuItem(title: NSLocalizedString("Unencrypted", comment: "encryption option"), action: #selector(encryptionChanged(_:)), keyEquivalent: "");
        unencrypedItem.image = NSImage(named: "lock.open.fill");//?.scaled(maxWidthOrHeight: buttonSize);
        unencrypedItem.image?.size = NSSize(width: 16, height: 16);
        menu.addItem(unencrypedItem);
        let defaultItem = NSMenuItem(title: NSLocalizedString("Default", comment: "encryption option"), action: #selector(encryptionChanged(_:)), keyEquivalent: "");
        defaultItem.image = NSImage(named: "lock.circle");//?.scaled(maxWidthOrHeight: buttonSize);
        defaultItem.image?.size = NSSize(width: 16, height: 16);
        menu.addItem(defaultItem);
        let omemoItem = NSMenuItem(title: NSLocalizedString("OMEMO", comment: "encryption option"), action: #selector(encryptionChanged(_:)), keyEquivalent: "");
        omemoItem.image = NSImage(named: "lock.fill");//?.scaled(maxWidthOrHeight: buttonSize);
        omemoItem.image?.size = NSSize(width: 16, height: 16);
        menu.addItem(omemoItem);
        encryptButton.menu = menu;
        encryptButton.bezelStyle = .regularSquare;
        NSLayoutConstraint.activate([encryptButton.widthAnchor.constraint(equalToConstant: buttonSize), encryptButton.widthAnchor.constraint(equalTo: encryptButton.heightAnchor)]);
        
        encryptButton.isBordered = false;
        encryptButton.isEnabled = false;
        encryptButton.isBordered = false;

        return encryptButton;
    }
    
    override func viewWillAppear() {
        self.conversationLogController?.contextMenuDelegate = self;

        conversation.displayNamePublisher.assign(to: \.title, on: buddyNameLabel).store(in: &cancellables);
        conversation.displayNamePublisher.map({ $0 as String? }).assign(to: \.name, on: buddyAvatarView).store(in: &cancellables);
        buddyAvatarView.displayableId = conversation;
        chat.descriptionPublisher.map({ $0 ?? "" }).assign(to: \.stringValue, on: buddyStatusLabel).store(in: &cancellables);
        chat.descriptionPublisher.assign(to: \.toolTip, on: buddyStatusLabel).store(in: &cancellables);
        buddyJidLabel.title = jid.description;

        buddyAvatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        
        let itemsCount = self.scriptsButton.menu?.items.count ?? 0;
        if itemsCount > 1 {
            for _ in 1..<itemsCount {
                self.scriptsButton.menu?.removeItem(at: 1)
            }
        }
        if let scripts = ScriptsManager.instance.contactScripts() {
            scripts.forEach { (script) in
                let item = NSMenuItem(title: script.name, action: #selector(scriptActivated(sender:)), keyEquivalent: "");
                item.target = self;
                self.scriptsButton.menu?.addItem(item);
            }
        }
        self.scriptsButton.isHidden = ScriptsManager.instance.contactScripts() == nil;

//        self.updateCapabilities();
        
        CaptureDeviceManager.authorizationStatusPublisher(for: .audio).map({ $0 == .authorized || $0 == .notDetermined }).map({ !$0 }).receive(on: DispatchQueue.main).assign(to: \.isHidden, on: audioCall).store(in: &cancellables);
        CaptureDeviceManager.authorizationStatusPublisher(for: .audio).map({ permission -> Bool in
            return permission == .authorized || permission == .notDetermined;
        }).combineLatest(CaptureDeviceManager.authorizationStatusPublisher(for: .video).map({ permission -> Bool in permission == .authorized || permission == .notDetermined }), { audio, video -> Bool in
                return !(audio && video);
        }).receive(on: DispatchQueue.main).assign(to: \.isHidden, on: videoCall).store(in: &cancellables);

        super.viewWillAppear();
        lastTextChangeTimer = Foundation.Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true, block: { (timer) in
            if self.lastTextChange.timeIntervalSinceNow < -10.0 {
                self.change(chatState: .active);
            }
        });

        chat.$features.combineLatest(Settings.$messageEncryption).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (features, defEncryption) in
            self?.refreshEncryptionStatus(features: features, defEncryption: defEncryption);
        }).store(in: &cancellables);
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear();
        cancellables.removeAll();
    }

    @objc func scriptActivated(sender: NSMenuItem) {
        ScriptsManager.instance.contactScripts()?.first(where: { (item) -> Bool in
            return item.name == sender.title;
        })?.execute(account: self.account, jid: JID(self.jid));
    }

    override func viewWillDisappear() {
        super.viewWillDisappear();
        self.cancellables.removeAll();
        lastTextChangeTimer?.invalidate();
        lastTextChangeTimer = nil;
        change(chatState: .active);
    }

    fileprivate func change(chatState: ChatState) {
        guard let message = self.chat.changeChatState(state: chatState) else {
            return;
        }
        chat.context?.module(.message).write(stanza: message);
    }

    override func textDidChange(_ notification: Notification) {
        super.textDidChange(notification);
        lastTextChange = Date();
        self.change(chatState: .composing);
    }

    override func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int) {
        super.prepareConversationLogContextMenu(dataSource: dataSource, menu: menu, forRow: row);
        if let item = dataSource.getItem(at: row) {
            switch item.state.direction {
            case .outgoing:
                switch item.payload {
                case .message(_, _), .attachment(_, _):
                    if item.state.isError {
                        let resend = menu.addItem(withTitle: NSLocalizedString("Resend message", comment: "context menu item"), action: #selector(resendMessage), keyEquivalent: "");
                        resend.target = self;
                        resend.tag = item.id;
                        if #available(macOS 11.0, *) {
                            resend.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "resend")
                        }
                    } else {
                        if item.isMessage(), !dataSource.isAnyMatching({ $0.state.direction == .outgoing && $0.isMessage() }, in: 0..<row) {
                            let correct = menu.addItem(withTitle: NSLocalizedString("Correct message", comment: "context menu item"), action: #selector(correctMessage), keyEquivalent: "");
                            correct.target = self;
                            correct.tag = item.id;
                            if #available(macOS 11.0, *) {
                                correct.image = NSImage(systemSymbolName: "pencil.circle", accessibilityDescription: "correct")
                            }
                        }
                        
                        if XmppService.instance.getClient(for: item.conversation.account)?.isConnected ?? false {
                            let retract = menu.addItem(withTitle: NSLocalizedString("Retract message", comment: "context menu item"), action: #selector(retractMessage), keyEquivalent: "");
                            retract.target = self;
                            retract.tag = item.id;
                            if #available(macOS 11.0, *) {
                                retract.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "retract")
                            }
                        }
                    }
                case .location(_):
                    if item.state.isError {
                        let resend = menu.addItem(withTitle: NSLocalizedString("Resend message", comment: "context menu item"), action: #selector(resendMessage), keyEquivalent: "");
                        resend.target = self;
                        resend.tag = item.id;
                        if #available(macOS 11.0, *) {
                            resend.image = NSImage(systemSymbolName: "repeat", accessibilityDescription: "resend")
                        }
                    } else {
                        let showMap = menu.insertItem(withTitle: NSLocalizedString("Show map", comment: "context menu item"), action: #selector(showMap), keyEquivalent: "", at: 0);
                        showMap.target = self;
                        showMap.tag = item.id;
                        if #available(macOS 11.0, *) {
                            showMap.image = NSImage(systemSymbolName: "map", accessibilityDescription: "show map")
                        }
                        if XmppService.instance.getClient(for: item.conversation.account)?.isConnected ?? false {
                            let retract = menu.addItem(withTitle: NSLocalizedString("Retract message", comment: "context menu item"), action: #selector(retractMessage), keyEquivalent: "");
                            retract.target = self;
                            retract.tag = item.id;
                            if #available(macOS 11.0, *) {
                                retract.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "retract")
                            }
                        }
                    }
                default:
                    break;
                }
            case .incoming:
                switch item.payload {
                case .location(_), .attachment(_, _), .message(_, _):
                    if XmppService.instance.getClient(for: item.conversation.account)?.module(.blockingCommand).isReportingSupported ?? true {
                        let report = menu.addItem(withTitle: NSLocalizedString("Report", comment: "context menu item"), action: nil, keyEquivalent: "");
                        if #available(macOS 11.0, *) {
                            report.image = NSImage(systemSymbolName: "hand.raised", accessibilityDescription: nil);
                        }
                        let submenu = NSMenu(title: "");
                        submenu.addItem(withTitle: NSLocalizedString("Spam", comment: "context menu item"), action: #selector(reportSpam(_:)), keyEquivalent: "").target = self;
                        submenu.addItem(withTitle: NSLocalizedString("Abuse", comment: "context menu item"), action: #selector(reportAbuse(_:)), keyEquivalent: "").target = self;
                        menu.setSubmenu(submenu, for: report);
                    }
                default:
                    break;
                }
            }
        }
    }
    
    @objc func reportSpam(_ sender: NSMenuItem) {
        report(report: .init(cause: .spam))
    }
    
    @objc func reportAbuse(_ sender: NSMenuItem) {
        report(report: .init(cause: .abuse))
    }
    
    private func report(report: BlockingCommandModule.Report) {
        guard let blockingModule = XmppService.instance.getClient(for: conversation.account)?.module(.blockingCommand), blockingModule.isReportingSupported else {
            return;
        }
        
        blockingModule.block(jid: JID(conversation.jid), report: report, completionHandler: { _ in });
    }

    @objc func resendMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return;
        }

        guard let item = dataSource.getItem(withId: tag) else {
            return;
        }

        switch item.payload {
        case .message(let message, _):
            Task {
                try await chat.sendMessage(text: message, correctedMessageOriginId: nil);
                DBChatHistoryStore.instance.remove(item: item);
            }
        case .attachment(let url, let appendix):
            let oldLocalFile = DownloadStore.instance.url(for: "\(item.id)");
            Task {
                try await chat.sendAttachment(url: url, appendix: appendix, originalUrl: oldLocalFile);
                DBChatHistoryStore.instance.remove(item: item);
            }
        default:
            break;
        }
    }
    
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(correctLastMessage(_:)):
            return messageField.string.isEmpty;
        default:
            return true;
        }
    }
    
    @IBAction func correctLastMessage(_ sender: AnyObject) {
        for i in 0..<dataSource.count {
            if let item = dataSource.getItem(at: i), item.state.direction == .outgoing, case .message(let message, _) = item.payload, let originId = DBChatHistoryStore.instance.originId(for: self.conversation, id: item.id) {
                startMessageCorrection(message: message, originId: originId);
                return;
            }
        }
    }
    
    @objc func correctMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
     
        guard let item = dataSource.getItem(withId: tag), case .message(let message, _) = item.payload, let originId = DBChatHistoryStore.instance.originId(for: self.conversation, id: item.id) else {
            return;
        }
        
        startMessageCorrection(message: message, originId: originId);
    }

    @objc func retractMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
        
        guard let item = dataSource.getItem(withId: tag), item.sender != .none else {
            return;
        }
        
        let alert = NSAlert();
        alert.messageText = NSLocalizedString("Are you sure you want to retract that message?", comment: "alert window title")
        alert.informativeText = NSLocalizedString("That message will be removed immediately and it's receives will be asked to remove it as well.", comment: "alert window message");
        alert.addButton(withTitle: NSLocalizedString("Retract", comment: "Button"));
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
            switch result {
            case .alertFirstButtonReturn:
                Task {
                    do {
                        try await self.chat.retract(entry: item);
                    } catch {
                        self.showError(message: NSLocalizedString("Retraction failed!", comment: "message retraction failed alert title"), error: error)
                    }
                }
            default:
                break;
            }
        })
    }
        
    override func send(message: String, correctedMessageOriginId: String?) async throws {
        try await chat.sendMessage(text: message, correctedMessageOriginId: correctedMessageOriginId);
    }
            
//    fileprivate func updateCapabilities() {
//        let supported = JingleManager.instance.support(for: JID(jid), on: account);
//        DispatchQueue.main.async {
//            self.audioCall.isHidden = !(VideoCallController.hasAudioSupport && (supported.contains(.audio) || Settings.ignoreJingleSupportCheck));
//            self.videoCall.isHidden = !(VideoCallController.hasAudioSupport && VideoCallController.hasVideoSupport && (supported.contains(.video) || Settings.ignoreJingleSupportCheck));
//        }
//    }

    @IBAction func audioCallClicked(_ sender: Any) {
        call(jid: self.jid, from: self.account, media: [.audio])
    }

    @IBAction func videoCallClicked(_ sender: NSButton) {
        call(jid: self.jid, from: self.account, media: [.audio,.video])
    }
    
    func call(jid: BareJID, from account: BareJID, media: [Call.Media]) {
        Task {
            do {
                guard let client = XmppService.instance.getClient(for: account) else {
                    throw XMPPError(condition: .item_not_found);
                }
                
                let call = Call(client: client, with: jid, sid: UUID().uuidString, direction: .outgoing, media: media);
                try await CallManager.instance.reportOutgoingCall(call);
            } catch {
                await MainActor.run(body: {
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Call failed", comment: "alert window title");
                    alert.informativeText = NSLocalizedString("It was not possible to establish call", comment: "alert window message");
                    switch error {
                    case let e as XMPPError:
                        switch e.condition {
                        case .forbidden:
                            alert.informativeText = NSLocalizedString("It was not possible to access camera or microphone. Please check permissions in the system settings", comment: "alert window message");
                        default:
                            break;
                        }
                    default:
                        break;
                    }
                    guard let window = self.view.window else {
                        return;
                    }
                    _ = alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.beginSheetModal(for: window, completionHandler: nil);
                })
            }
        }
    }

    @objc func encryptionChanged(_ menuItem: NSMenuItem) {
        var encryption: ChatEncryption? = nil;
        let idx = encryptButton.menu?.items.firstIndex(where: { $0.title == menuItem.title }) ?? 0;
        switch idx {
        case 0:
            encryption = ChatEncryption.none;
        case 1:
            encryption = nil;
        case 2:
            encryption = ChatEncryption.omemo;
        default:
            encryption = nil;
        }

        chat.updateOptions({ (options) in
            options.encryption = encryption;
        });
        DispatchQueue.main.async {
            self.refreshEncryptionStatus(features: self.chat.features, defEncryption: Settings.messageEncryption);
        }
    }

    private func refreshEncryptionStatus(features: [ConversationFeature], defEncryption: ConversationEncryption) {
        self.encryptButton.isEnabled = features.contains(.omemo); 
        if !self.encryptButton.isEnabled {
            self.encryptButton.image = NSImage(named: "lock.open.fill");
        } else {
            let encryption = self.chat.options.encryption ?? defEncryption;
            let locked = encryption == ChatEncryption.omemo;
            self.encryptButton.image = NSImage(named: locked ? "lock.fill" : "lock.open.fill");
        }
    }

    @IBAction func showInfoClicked(_ sender: NSButton) {
        let storyboard = NSStoryboard(name: "ConversationDetails", bundle: nil);
        guard let viewController = storyboard.instantiateController(withIdentifier: "ContactDetailsViewController") as? ContactDetailsViewController else {
            return;
        }
        viewController.account = self.account;
        viewController.jid = self.jid;
        viewController.viewType = .chat;

        let popover = NSPopover();
        popover.contentViewController = viewController;
        popover.behavior = .semitransient;
        popover.animates = true;
        let rect = sender.convert(sender.bounds, to: self.view.window!.contentView!);
        popover.show(relativeTo: rect, of: self.view.window!.contentView!, preferredEdge: .minY);
    }
}

enum MessageSendError: Error {
    case internalError
    case unknownError(String)

    var stanzaId: String? {
        switch self {
        case .unknownError(let stanzaId):
            return stanzaId;
        default:
            return nil;
        }
    }
}

public enum PreviewError: String, Error {
    case NoData = "no_data";
    case Error = "error";
}

public enum MessageDirection: Int {
    case incoming = 0
    case outgoing = 1
}

class ChatViewTableView: NSTableView {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "ChatViewTableView");
    
    static let didScrollRowToVisible = Notification.Name("ChatViewTableView::didScrollRowToVisible");

    override var acceptsFirstResponder: Bool {
        return true;
    }
    
    weak var mouseDelegate: ChatViewTableViewMouseDelegate?;
    
    override open var isFlipped: Bool {
        return false;
    }
    
    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView);
    }
    
    override func scrollRowToVisible(_ row: Int) {
        let numberOfRows = self.dataSource?.numberOfRows?(in: self) ?? 0;
        guard numberOfRows > row else {
            logger.debug("cannot scroll to row: \(row) as data source has only \(numberOfRows) rows");
            return;
        }

//        guard row == 0 else {
//            let rect = self.rect(ofRow: row);
//            self.scrollToVisible(NSRect(origin: NSPoint(x: rect.origin.x, y: (rect.origin.y - max(0, self.visibleRect.height - rect.size.height))), size: rect.size));
//            return;
//        }

        super.scrollRowToVisible(row);
        let visibleRows = self.rows(in: self.visibleRect);
        if !visibleRows.contains(row) {
            logger.debug("visible rows: \(visibleRows), need: \(row)");
            DispatchQueue.main.async {
                self.scrollRowToVisible(row);
            }
        } else {
            logger.debug("scrollRowToVisible called!");
            NotificationCenter.default.post(name: ChatViewTableView.didScrollRowToVisible, object: self);
        }
    }
    
    override func mouseDown(with event: NSEvent) {
        if !(mouseDelegate?.handleMouse(event: event) ?? false) {
            super.mouseDown(with: event);
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        if !(mouseDelegate?.handleMouse(event: event) ?? false) {
            super.mouseUp(with: event);
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if !(mouseDelegate?.handleMouse(event: event) ?? false) {
            super.mouseDragged(with: event);
        }
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if !(mouseDelegate?.handleMouse(event: event) ?? false) {
            super.rightMouseDown(with: event);
        }
    }

    override func validateProposedFirstResponder(_ responder: NSResponder, for event: NSEvent?) -> Bool {
        if responder is NSTextView {
            return false;
        } else {
            return super.validateProposedFirstResponder(responder, for: event);
        }
    }
    
    override func prepareContent(in rect: NSRect) {
        // disable chat preloading
        super.prepareContent(in: self.visibleRect);
    }
}

protocol ChatViewTableViewMouseDelegate: AnyObject {
    func handleMouse(event: NSEvent) -> Bool;
}

class ChatViewStatusView: NSTextField {

}
