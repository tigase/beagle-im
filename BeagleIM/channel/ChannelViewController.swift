//
// ChannelViewController.swift
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
import Combine

class ChannelViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate, ConversationLogContextMenuDelegate, NSMenuDelegate, NSMenuItemValidation {

    @IBOutlet var channelAvatarView: AvatarViewWithStatus!
    @IBOutlet var channelNameLabel: NSTextFieldCell!
    @IBOutlet var channelJidLabel: NSTextFieldCell!
    @IBOutlet var channelDescriptionLabel: NSTextField!;

    @IBOutlet var infoButton: NSButton!;
    @IBOutlet var participantsButton: NSButton!;
    @IBOutlet var actionsButton: NSPopUpButton!;

    private var cancellables: Set<AnyCancellable> = [];
    
    var channel: Channel! {
        return self.conversation as? Channel;
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        let cgRef = infoButton.image!.cgImage(forProposedRect: nil, context: nil, hints: nil);
        let representation = NSBitmapImageRep(cgImage: cgRef!);
        let newRep = representation.converting(to: .genericGray, renderingIntent: .default);
        infoButton.image = NSImage(cgImage: newRep!.cgImage!, size: infoButton.frame.size);
        buttonToGrayscale(button: infoButton, template: false);
        buttonToGrayscale(button: participantsButton, template: true);
        
    }
    
    override func viewWillAppear() {
        self.conversationLogController?.contextMenuDelegate = self;
        
        channel.displayNamePublisher.assign(to: \.title, on: channelNameLabel).store(in: &cancellables);
        channel.displayNamePublisher.map({ $0 as String? }).assign(to: \.name, on: channelAvatarView).store(in: &cancellables);
        channelAvatarView.displayableId = channel;
        channel.descriptionPublisher.map({ $0 ?? "" }).assign(to: \.stringValue, on: channelDescriptionLabel).store(in: &cancellables);
        channel.descriptionPublisher.assign(to: \.toolTip, on: channelDescriptionLabel).store(in: &cancellables);
        channelJidLabel.title = jid.stringValue;
        
        channelAvatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;

        NotificationCenter.default.addObserver(self, selector: #selector(participantsChanged(_:)), name: MixEventHandler.PARTICIPANTS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged(_:)), name: MixEventHandler.PERMISSIONS_CHANGED, object: channel);
        
        self.participantsButton.title = "\(channel.participants.count)";
        updatePermissions();
        super.viewWillAppear();
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear();
        NotificationCenter.default.removeObserver(self, name: MixEventHandler.PARTICIPANTS_CHANGED, object: nil);
    }
    
    override func viewDidDisappear() {
        super.viewDidDisappear();
        cancellables.removeAll();
    }
    
    override func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int) {
        super.prepareConversationLogContextMenu(dataSource: dataSource, menu: menu, forRow: row);
        if let item = dataSource.getItem(at: row) as? ConversationEntryWithSender, item.state.direction == .outgoing {
            if item.state.isError {
            } else {
                if item is ConversationMessage, !dataSource.isAnyMatching({ ($0 as? ConversationEntryWithSender)?.state.direction == .outgoing && $0 is ConversationMessage }, in: 0..<row) {
                    let correct = menu.addItem(withTitle: "Correct message", action: #selector(correctMessage), keyEquivalent: "");
                    correct.target = self;
                    correct.tag = item.id;
                }
                if (self.conversation as? Channel)?.state ?? .left == .joined && XmppService.instance.getClient(for: item.conversation.account)?.state ?? .disconnected() == .connected {
                    let retract = menu.addItem(withTitle: "Retract message", action: #selector(retractMessage), keyEquivalent: "");
                    retract.target = self;
                    retract.tag = item.id;
                }
            }
        }
    }
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        super.prepare(for: segue, sender: sender)
        if let channelAware = segue.destinationController as? ChannelAwareProtocol {
            channelAware.channel = self.channel;
        }
        if let controller = segue.destinationController as? ChannelParticipantsViewController {
            controller.channelViewController = self;
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
            if let item = dataSource.getItem(at: i) as? ConversationMessage, item.state.direction == .outgoing {
                DBChatHistoryStore.instance.originId(for: item.account, with: item.conversation.jid, id: item.id, completionHandler: { [weak self] originId in
                    self?.startMessageCorrection(message: item.message, originId: originId);
                })
                return;
            }
        }
    }

    @objc func correctMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
     
        guard let item = dataSource.getItem(withId: tag) as? ConversationMessage else {
            return;
        }
        
        DBChatHistoryStore.instance.originId(for: item.account, with: item.conversation.jid, id: item.id, completionHandler: { [weak self] originId in
            self?.startMessageCorrection(message: item.message, originId: originId);
        })
    }
    
    @objc func retractMessage(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
        
        guard let item = dataSource.getItem(withId: tag) as? ConversationEntryWithSender, let chat = self.conversation as? Channel else {
            return;
        }
        
        let alert = NSAlert();
        alert.messageText = "Are you sure you want to retract that message?"
        alert.informativeText = "That message will be removed immediately and it's receives will be asked to remove it as well.";
        alert.addButton(withTitle: "Retract");
        alert.addButton(withTitle: "Cancel");
        alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
            switch result {
            case .alertFirstButtonReturn:
                chat.retract(entry: item);
            default:
                break;
            }
        })
    }
    
    override func send(message: String, correctedMessageOriginId: String?) -> Bool {
        guard let client = XmppService.instance.getClient(for: account), client.state == .connected, channel.state == .joined else {
            return false;
        }
        channel.sendMessage(text: message, correctedMessageOriginId: correctedMessageOriginId);
        return true;
    }
    
    @objc func participantsChanged(_ notification: Notification) {
        guard let e = notification.object as? MixModule.ParticipantsChangedEvent else {
            return;
        }
        DispatchQueue.main.async {
            guard self.channel.id == (e.channel as? Channel)?.id else {
                return;
            }
            self.participantsButton.title = "\(self.channel.participants.count)";
        }
    }
    
    @objc func permissionsChanged(_ notification: Notification) {
        self.updatePermissions();
    }
    
    private func updatePermissions() {
        self.actionsButton.item(at: 1)?.isEnabled = channel.has(permission: .changeInfo);
        self.actionsButton.item(at: 2)?.isEnabled = channel.has(permission: .changeConfig);
        self.actionsButton.lastItem?.isEnabled = channel.has(permission: .changeConfig);
    }
    
    @IBAction func showInfoClicked(_ sender: NSButton) {
        let storyboard = NSStoryboard(name: "ConversationDetails", bundle: nil);
        guard let viewController = storyboard.instantiateController(withIdentifier: "ContactDetailsViewController") as? ContactDetailsViewController else {
            return;
        }
        viewController.account = self.account;
        viewController.jid = self.jid;
        viewController.viewType = .groupchat;

        let popover = NSPopover();
        popover.contentViewController = viewController;
        popover.behavior = .semitransient;
        popover.animates = true;
        let rect = sender.convert(sender.bounds, to: self.view.window!.contentView!);
        popover.show(relativeTo: rect, of: self.view.window!.contentView!, preferredEdge: .minY);
    }
    
    @IBAction func showEditChannelHeader(_ sender: NSMenuItem) {
        self.performSegue(withIdentifier: NSStoryboardSegue.Identifier("ShowEditChannelHeaderSheet"), sender: self);
    }

    @IBAction func showEditChannelConfig(_ sender: NSMenuItem) {
        self.performSegue(withIdentifier: NSStoryboardSegue.Identifier("ShowEditChannelConfigSheet"), sender: self);
    }
    
    @IBAction func showDestroyChannel(_ sender: NSMenuItem) {
        guard let channel = self.channel else {
            return;
        }

        let alert = NSAlert();
        alert.alertStyle = .warning;
        alert.icon = NSImage(named: NSImage.cautionName);
        alert.messageText = "Destroy channel?";
        alert.informativeText = "Are you sure that you want to leave and destroy channel \(channel.name ?? channel.channelJid.stringValue)?";
        alert.addButton(withTitle: "Yes");
        alert.addButton(withTitle: "No");
        alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
            if (response == .alertFirstButtonReturn) {
                guard let client = XmppService.instance.getClient(for: channel.account), client.state == .connected, let mixModule: MixModule = client.modulesManager.getModule(MixModule.ID), channel.state == .joined else {
                    return;
                }
                mixModule.destroy(channel: channel.channelJid, completionHandler: { result in
                    DispatchQueue.main.async {
                        guard let window = self.view.window else {
                            return;
                        }
                        switch result {
                        case .success(_):
                            break;
                        case .failure(let error):
                            let alert = NSAlert();
                            alert.alertStyle = .warning;
                            alert.icon = NSImage(named: NSImage.cautionName);
                            alert.messageText = "Channel destruction failed!";
                            alert.informativeText = "It was not possible to destroy channel \(channel.name ?? channel.channelJid.stringValue). Server returned an error: \(error.message ?? error.description)";
                            alert.addButton(withTitle: "OK");
                            alert.beginSheetModal(for: window, completionHandler: nil);
                        }
                    }
                })
            }
        });
    }

    private func buttonToGrayscale(button: NSButton, template: Bool) {
        let cgRef = button.image!.cgImage(forProposedRect: nil, context: nil, hints: nil);
        let representation = NSBitmapImageRep(cgImage: cgRef!);
        let newRep = representation.converting(to: .genericGray, renderingIntent: .default);
        let img = NSImage(cgImage: newRep!.cgImage!, size: NSSize(width: button.frame.size.height, height: button.frame.size.height));
        img.isTemplate = template;
        button.image = img;
    }

    private var skipNextSuggestion = false;
    private var forceSuggestion = false;

    override func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            self.skipNextSuggestion = true;
            return false;
            //return super.textView(textView, doCommandBy: commandSelector);
        case #selector(NSResponder.deleteForward(_:)), #selector(NSResponder.deleteBackward(_:)):
            self.skipNextSuggestion = true;
            return super.textView(textView, doCommandBy: commandSelector);
        default:
            return super.textView(textView, doCommandBy: commandSelector);
        }
    }
        
    override func textDidChange(_ obj: Notification) {
        super.textDidChange(obj);
        if !skipNextSuggestion {
            self.messageField.complete(nil);
        } else {
            skipNextSuggestion = false;
        }
    }
        
    func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        guard charRange.length != 0 && charRange.location != NSNotFound else {
            return [];
        }
        
        let tmp = textView.string;
        let utf16 = tmp.utf16;
        let start = utf16.index(utf16.startIndex, offsetBy: charRange.lowerBound);
        let end = utf16.index(utf16.startIndex, offsetBy: charRange.upperBound);
        guard let query = String(utf16[start..<end])?.uppercased() else {
            return [];
        }
                
        let participantNicknames: [String] = self.channel.participants.compactMap({ $0.nickname });
        let suggestions = participantNicknames.filter({ (key) -> Bool in
            return key.uppercased().starts(with: query);
        }).sorted();

        index?.initialize(to: -1);//suggestions.isEmpty ? -1 : 0);

        return suggestions.map({ name in "\(name) "});
    }
}
