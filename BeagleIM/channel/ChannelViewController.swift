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

class ChannelViewController: AbstractChatViewControllerWithSharing, NSTableViewDelegate, ConversationLogContextMenuDelegate, NSMenuDelegate {

    @IBOutlet var channelAvatarView: AvatarViewWithStatus!
    @IBOutlet var channelNameLabel: NSTextFieldCell!
    @IBOutlet var channelJidLabel: NSTextFieldCell!
    @IBOutlet var channelDescriptionLabel: NSTextField!;

    @IBOutlet var infoButton: NSButton!;
    @IBOutlet var participantsButton: NSButton!;
    @IBOutlet var actionsButton: NSPopUpButton!;

    private var keywords: [String]? = Settings.markKeywords.stringArrays();

    var channel: DBChatStore.DBChannel! {
        return self.chat as? DBChatStore.DBChannel;
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
        channelNameLabel.title = channel.name ?? channel.channelJid.stringValue;
        channelJidLabel.title = jid.stringValue;
        
        channelAvatarView.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        channelAvatarView.name = channel.name ?? jid.stringValue;
        channelAvatarView.update(for: jid, on: account);
        channelAvatarView.status = (XmppService.instance.getClient(for: channel.account)?.state ?? .disconnected == .connected) && channel.state == .joined ? .online : nil;
        channelDescriptionLabel.stringValue = channel.description ?? "";
        channelDescriptionLabel.toolTip = channel.description;

        NotificationCenter.default.addObserver(self, selector: #selector(participantsChanged(_:)), name: MixEventHandler.PARTICIPANTS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(channelUpdated(_:)), name: DBChatStore.CHAT_UPDATED, object: channel);
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged(_:)), name: AvatarManager.AVATAR_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(permissionsChanged(_:)), name: MixEventHandler.PERMISSIONS_CHANGED, object: channel);
        
        self.participantsButton.title = "\(channel.participants.count)";
        updatePermissions();
        super.viewWillAppear();
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear();
        NotificationCenter.default.removeObserver(self, name: MixEventHandler.PARTICIPANTS_CHANGED, object: nil);
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let item = dataSource.getItem(at: row) else {
            return nil;
        }
        
        let prevItem = row >= 0 && (row + 1) < dataSource.count ? dataSource.getItem(at: row + 1) : nil;
        let continuation = prevItem != nil && item.isMergeable(with: prevItem!);

        switch item {
        case is SystemMessage:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatMessageSystemCellView"), owner: nil) as? ChatMessageSystemCellView {
                cell.message.attributedString = NSAttributedString(string: "Unread messages");
                return cell;
            }
            return nil;
        case let item as ChatMessage:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatMessageContinuationCellView" : "ChatMessageCellView"), owner: nil) as? ChatMessageCellView {

                cell.id = item.id;
                if cell.hasHeader {
                    if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                        cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                    } else if let participantId = item.participantId {
                        cell.set(avatar: AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(item.jid.localPart!)", domain: item.jid.domain), on: item.account));
                    } else {
                        cell.set(avatar: nil);
                    }
                    
                    cell.set(senderName: item.authorNickname ?? "Unknown");
                }
                cell.set(message: item, nickname: channel.nickname, keywords: keywords);

                return cell;
            }
            return nil;
        case let item as ChatLinkPreview:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatLinkPreviewCellView"), owner: nil) as? ChatLinkPreviewCellView {
                cell.set(item: item, fetchPreviewIfNeeded: true);
                return cell;
            }
            return nil;
        case let item as ChatAttachment:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: continuation ? "ChatAttachmentContinuationCellView" : "ChatAttachmentCellView"), owner: nil) as? ChatAttachmentCellView {
                if cell.hasHeader {
                    if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                        cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                    } else if let participantId = item.participantId {
                        cell.set(avatar: AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(item.jid.localPart!)", domain: item.jid.domain), on: item.account));
                    } else {
                        cell.set(avatar: nil);
                    }
                                    
                    cell.set(senderName: item.authorNickname ?? "Unknown");
                }
                cell.set(item: item);
                return cell;
            }
            return nil;
        case let item as ChatInvitation:
            if let cell = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "ChatInvitationCellView"), owner: nil) as? ChatInvitationCellView {
                if cell.hasHeader {
                    if let senderJid = item.state.direction == .incoming ? item.authorJid : item.account {
                        cell.set(avatar: AvatarManager.instance.avatar(for: senderJid, on: item.account));
                    } else if let participantId = item.participantId {
                        cell.set(avatar: AvatarManager.instance.avatar(for: BareJID(localPart: "\(participantId)#\(item.jid.localPart!)", domain: item.jid.domain), on: item.account));
                    } else {
                        cell.set(avatar: nil);
                    }
                                    
                    cell.set(senderName: item.authorNickname ?? "Unknown");
                }
                cell.set(invitation: item);
                return cell;
            }
            return nil;
        default:
            return nil;
        }
    }
    
    override func conversationTableViewDelegate() -> NSTableViewDelegate? {
        return self;
    }

    func prepareConversationLogContextMenu(dataSource: ChatViewDataSource, menu: NSMenu, forRow row: Int) {
        
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

    override func send(message: String) -> Bool {
        guard let client = XmppService.instance.getClient(for: account), client.state == .connected, channel.state == .joined else {
            return false;
        }
        let msg = channel.createMessage(message);
        client.context.writer?.write(msg);
        return true;
    }
    
    override func sendAttachment(originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?) -> Bool {
        guard let client = XmppService.instance.getClient(for: account), client.state == .connected, channel.state == .joined else {
            return false;
        }
        let msg = channel.createMessage(uploadedUrl.absoluteString);
        msg.oob = uploadedUrl.absoluteString;
        client.context.writer?.write(msg);
        return true;
    }
    
    @objc func avatarChanged(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
            return;
        }
        DispatchQueue.main.async {
            guard self.channel.account == account && self.channel.channelJid == jid else {
                return;
            }
            self.channelAvatarView.avatar = AvatarManager.instance.avatar(for: self.channel.channelJid, on: self.channel.account);
        }
    }

    @objc func channelUpdated(_ notification: Notification) {
        DispatchQueue.main.async {
            self.channelAvatarView.name = self.channel.name ?? self.channel.channelJid.stringValue;
            self.channelAvatarView.status = (XmppService.instance.getClient(for: self.channel.account)?.state ?? .disconnected == .connected) && self.channel.state == .joined ? .online : nil;
            self.channelNameLabel.title = self.channel.name ?? self.channel.channelJid.stringValue;
            self.channelDescriptionLabel.stringValue = self.channel.description ?? "";
            self.channelDescriptionLabel.toolTip = self.channel.description;
        }
    }
    
    @objc func participantsChanged(_ notification: Notification) {
        guard let e = notification.object as? MixModule.ParticipantsChangedEvent else {
            return;
        }
        DispatchQueue.main.async {
            guard self.channel.id == (e.channel as? DBChatStore.DBChannel)?.id else {
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
                        case .failure(let errorCondition):
                            let alert = NSAlert();
                            alert.alertStyle = .warning;
                            alert.icon = NSImage(named: NSImage.cautionName);
                            alert.messageText = "Channel destruction failed!";
                            alert.informativeText = "It was not possible to destroy channel \(channel.name ?? channel.channelJid.stringValue). Server returned an error: \(errorCondition.rawValue)";
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

}
