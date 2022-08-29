//
// EnterChannelViewController.swift
//
// BeagleIM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

import Foundation
import AppKit
import Martin

class EnterChannelViewController: NSViewController, NSTextFieldDelegate {
        
    @IBOutlet var titleLabel: NSTextField!;
    @IBOutlet var nicknameField: NSTextField!;
    @IBOutlet var passwordLabel: NSTextField!;
    @IBOutlet var passwordField: NSTextField!;
    @IBOutlet var bookmarkCreateButton: NSButton!;
    @IBOutlet var bookmarkAutojoinButton: NSButton!;
    
    @IBOutlet var passwordBox: NoSizeWhenHiddenView!;
    @IBOutlet var bookmarkBox: NoSizeWhenHiddenView!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var joinButton: NSButton!;

    var account: BareJID!;
    var channelJid: BareJID!;
    var channelName: String?;
    var suggestedNickname: String?;
    var password: String?;
    var componentType: BaseJoinChannelViewController.ComponentType = .mix;
    var info: DiscoveryModule.DiscoveryInfoResult?;

    var isPasswordVisible: Bool = true;
    var isBookmarkVisible: Bool = true;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        refreshTitle();
        nicknameField.stringValue = suggestedNickname ?? AccountManager.getAccount(for: account)?.nickname ?? "";
        passwordField.stringValue = password ?? "";
    
        refreshPasswordVisibility();
        refreshBookmarkVisibility();
        bookmarkCreateButton.isEnabled = isBookmarkVisible;
        bookmarkCreateButton.state = isBookmarkVisible && Settings.enableBookmarksSync ? .on : .off;
        bookmarkAutojoinButton.isEnabled = isBookmarkVisible && bookmarkCreateButton.state == .on;
        updateJoinButton();
        
        if let client = XmppService.instance.getClient(for: account) {
            self.progressIndicator.startAnimation(self);
            client.module(.disco).getInfo(for: JID(channelJid!), completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let info):
                        self?.info = info;
                        self?.refreshTitle();
                        self?.refreshPasswordVisibility();
                        self?.updateJoinButton();
                    case .failure(let error):
                        guard let window = self?.view.window else {
                            return;
                        }
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Could not join", comment: "alert window title");
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a room. The server returned an error: %@", comment: "alert window message"), error.localizedDescription);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: { (response) in
                            self?.close(returnCode: .cancel);
                        });
                    }
                    self?.progressIndicator.stopAnimation(self);
                }
            })
        } else {
            
        }
    }
    
    private func refreshTitle() {
        titleLabel.stringValue = String.localizedStringWithFormat(NSLocalizedString("Joining channel %@", comment: "window title"), channelName ?? info?.identities.first?.name ?? channelJid.stringValue)
    }
    
    func controlTextDidChange(_ obj: Notification) {
        updateJoinButton();
    }
    
    private func updateJoinButton() {
        joinButton.isEnabled = info != nil && !nicknameField.stringValue.isEmpty && (componentType == .mix || !info!.features.contains("muc_passwordprotected") || !passwordField.stringValue.isEmpty);
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close(returnCode: .cancel);
    }

    @IBAction func joinClicked(_ sender: NSButton) {
        guard let client = XmppService.instance.getClient(for: account) else {
            return;
        }

        let nickname = nicknameField.stringValue;
        let password = passwordField.stringValue.isEmpty ? nil : passwordField.stringValue;
        let channelJid = channelJid!;
     
        join(client: client, channelJid: channelJid, channelName: info?.identities.first?.name, nickname: nickname, password: password, features: info?.features ?? [])
    }
    
    @IBAction func createBookmarkChanged(_ sender: NSButton) {
        bookmarkAutojoinButton.isEnabled = isBookmarkVisible && sender.state == .on;
    }
    
    private func close(returnCode: NSApplication.ModalResponse) {
        guard let window = self.view.window, let parent = window.sheetParent else {
            self.dismiss(self);
            return;
        }
        parent.endSheet(window, returnCode: returnCode);
    }
    
    private func refreshPasswordVisibility() {
        if let box = passwordBox {
            box.isHidden = componentType == .mix || !isPasswordVisible || !(info?.features.contains("muc_passwordprotected") ?? false);
        }
    }
    
    private func refreshBookmarkVisibility() {
        if let box = bookmarkBox {
            box.isHidden = componentType == .mix || !isBookmarkVisible;
        }
    }
    
    private func join(client: XMPPClient, channelJid: BareJID, channelName: String?, nickname: String, password: String?, features: [String]) {
        self.progressIndicator.startAnimation(self);
        let createBookmark = bookmarkCreateButton.isEnabled && bookmarkCreateButton.state == .on;
        let autojoin = bookmarkAutojoinButton.isEnabled && bookmarkAutojoinButton.state == .on;
        switch componentType {
        case .muc:
            let room = channelJid;
            let result = client.module(.muc).join(roomName: room.localPart!, mucServer: room.domain, nickname: nickname, password: passwordField.stringValue);
            result.handle({ [weak self] r in
                switch r {
                case .success(let roomResult):
                    switch roomResult {
                    case .created(let room), .joined(let room):
                        (room as! Room).roomFeatures = Set(features.compactMap({ Room.Feature(rawValue: $0) }));
                    }
                    if createBookmark {
                        client.module(.pepBookmarks).addOrUpdate(bookmark: Bookmarks.Conference(name: channelName ?? room.localPart ?? room.stringValue, jid: JID(room), autojoin: autojoin, nick: nickname, password: password));
                    }
                    DispatchQueue.main.async {
                        self?.close(returnCode: .OK);
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        guard let window = self?.view.window else {
                            return;
                        }
                        
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Could not join", comment: "alert window title");
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert window title"), error.localizedDescription);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: nil);
                    }
                }
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(self);
                }
            })
        case .mix:
            client.module(.mix).join(channel: channelJid, withNick: nickname, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    if let channel = DBChatStore.instance.channel(for: client, with: channelJid) {
                        client.module(.disco).getItems(for: JID(channel.jid), completionHandler: { result in
                            switch result {
                            case .success(let info):
                                channel.updateOptions({ options in
                                    options.features = Set(info.items.compactMap({ $0.node }).compactMap({ Channel.Feature(rawValue: $0) }));
                                })
                            case .failure(_):
                                break;
                            }
                        });
                    }
                    // we have joined, so all what we need to do is close this window
                    DispatchQueue.main.async {
                        self?.close(returnCode: .OK);
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        guard let window = self?.view.window else {
                            return;
                        }
                        
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Could not join", comment: "alert window title");
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to join a channel. The server returned an error: %@", comment: "alert window title"), error.localizedDescription);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: nil);
                    }
                }
                DispatchQueue.main.async {
                    self?.progressIndicator.stopAnimation(self);
                }
            });
        }
    }

}

class NoSizeWhenHiddenView: NSView {
    
    private var heightConstraint: NSLayoutConstraint?;
    
    override var isHidden: Bool {
        didSet {
            if heightConstraint == nil {
                heightConstraint = heightAnchor.constraint(equalToConstant: 0);
            }
            heightConstraint?.isActive = isHidden;
        }
    }
    
}
