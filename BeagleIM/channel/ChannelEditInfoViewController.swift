//
// ChannelEditInfoViewController.swift
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
import Quartz

class ChannelEditInfoViewController: NSViewController, ChannelAwareProtocol {
    
    var channel: Channel!
    
    @IBOutlet var avatarButton: AvatarChangeButton!;
    @IBOutlet var nameField: NSTextField!
    @IBOutlet var descriptionField: NSTextField!
    
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var submitButton: NSButton!;
    
    private var info = ChannelInfo(name: nil, description: nil, contact: []) {
        didSet {
            nameField.stringValue = info.name ?? "";
            descriptionField.stringValue = info.description ?? "";
            avatarButton.name = channel.name ?? channel.channelJid.stringValue;
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        guard let client = channel.context else {
            return;
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(avatarChanged(_:)), name: AvatarManager.AVATAR_CHANGED, object: nil);
        
        avatarButton.name = channel.name ?? channel.channelJid.stringValue;
        avatarButton.image = AvatarManager.instance.avatar(for: channel.channelJid, on: channel.account);
        self.submitButton.isEnabled = false;
        progressIndicator.startAnimation(self);
        
        let group = DispatchGroup();
        group.enter();
        client.module(.mix).retrieveInfo(for: channel.channelJid, completionHandler: { [weak self] result in
            group.leave();
            switch result {
            case .success(let info):
                DispatchQueue.main.async {
                    self?.info = info;
                }
            case .failure(let errorCondition):
                guard errorCondition != .item_not_found, let that = self else {
                    return;
                }
                DispatchQueue.main.async {
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Could not retrieve details", comment: "alert window title")
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to retrieve channel details: %@", comment: "alert window message"), errorCondition.description);
                    alert.beginSheetModal(for: that.view.window!, completionHandler: { response in
                        that.dismiss(that);
                    })
                }
            }
        })
        if channel.has(permission: .changeAvatar) {
            group.enter();
            client.module(.pepUserAvatar).retrieveAvatarMetadata(from: channel.channelJid, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    DispatchQueue.main.async {
                        self?.avatarButton.isEnabled = true;
                        self?.avatarButton.changeLabel.isHidden = true;
                    }
                case .failure(_):
                    DispatchQueue.main.async {
                        self?.avatarButton.isEnabled = false;
                        self?.avatarButton.changeLabel.isHidden = true;
                    }
                }
                group.leave();
            })
        } else {
            self.avatarButton.isEnabled = false;
            self.avatarButton.changeLabel.isHidden = true;
        }
        group.notify(queue: DispatchQueue.main, execute: { [weak self] in
            DispatchQueue.main.async {
                self?.progressIndicator?.stopAnimation(nil);
                self?.submitButton.isEnabled = true;
            }
        })
    }
    
    override func viewWillDisappear() {
        NotificationCenter.default.removeObserver(self);
    }
    
    @IBAction func submitClicked(_ sender: NSButton) {
        let name = nameField.stringValue;
        let desc = descriptionField.stringValue;
        let info = ChannelInfo(name: name.isEmpty ? nil : name, description: desc.isEmpty ? nil : desc, contact: self.info.contact);
        guard let client = channel.context else {
            return;
        }
        
        progressIndicator.startAnimation(self);
        submitButton.isEnabled = false;
        
        client.module(.mix).publishInfo(for: channel.channelJid, info: info, completionHandler: { [weak self] result in
            guard let that = self else {
                return;
            }
            DispatchQueue.main.async {
                that.progressIndicator.stopAnimation(self);
                that.submitButton.isEnabled = true;
            }
            switch result {
            case .success(_):
                DispatchQueue.main.async {
                    that.dismiss(that);
                }
            case .failure(let errorCondition):
                DispatchQueue.main.async {
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Could not publish details", comment: "alert window title");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to publish channel details: %@", comment: "alert window message"), errorCondition.description);
                    alert.beginSheetModal(for: that.view.window!, completionHandler: { response in
                        //self.dismiss(self);
                    })
                }
            }
        })
        
        if avatarButton.isEnabled && avatarButton.image != AvatarManager.instance.avatar(for: channel.channelJid, on: channel.account) {
            if let binval = self.avatarButton.image?.scaled(maxWidthOrHeight: 512.0).jpegData(compressionQuality: 0.8) {
                client.module(.pepUserAvatar).publishAvatar(at: channel.channelJid, data: binval, mimeType: "image/jpeg", width: nil, height: nil, completionHandler: { result in
                    switch result {
                    case .success(_):
                        // new avatar published
                        break;
                    case .failure(_):
                        // avatar publication failed
                        break;
                    }
                })
            }
        }
    }
    
    @objc func avatarChanged(_ notification: Notification) {
        guard let account = notification.userInfo?["account"] as? BareJID, let jid = notification.userInfo?["jid"] as? BareJID else {
            return;
        }
        DispatchQueue.main.async {
            guard self.channel.account == account && self.channel.channelJid == jid else {
                return;
            }
            self.avatarButton.image = AvatarManager.instance.avatar(for: self.channel.channelJid, on: self.channel.account);
        }
    }
    
    @IBAction func avatarClicked(_ sender: Any) {
        let taker = IKPictureTaker.pictureTaker();
        if let image = avatarButton.image {
            taker?.setInputImage(image);
        }
        taker?.setValue(true, forKey: IKPictureTakerShowAddressBookPictureKey)
        taker?.setValue(true, forKey: IKPictureTakerShowEmptyPictureKey);
        taker?.beginSheet(for: self.view.window!, withDelegate: self, didEnd: #selector(avatarSelected), contextInfo: nil);
    }
    
    @objc func avatarSelected(_ pictureTaker: IKPictureTaker, code: Int, context: Any?) {
        guard code == NSApplication.ModalResponse.OK.rawValue  else {
            return;
        }
        avatarButton.image = pictureTaker.outputImage();
    }
}
