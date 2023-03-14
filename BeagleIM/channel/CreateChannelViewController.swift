//
// CreateChannelViewController.swift
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
import Quartz
import AppKit
import Martin
import TigaseLogging

class CreateChannelViewController: BaseJoinChannelViewController, NSTextFieldDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CreateChannelView");
        
    @IBOutlet var avatarButton: AvatarChangeButton!;
    @IBOutlet var nameField: NSTextField!;
    @IBOutlet var descriptionField: NSTextField!;
    @IBOutlet var typeSelector: NSSegmentedControl! {
        didSet {
            if typeSelector != nil {
                self.updateTypeLabel(typeSelector: typeSelector);
            }
        }
    }
    @IBOutlet var typeDescription: NSTextField!;
    @IBOutlet var mixCheckbox: NSButton!;
    @IBOutlet var idLabel: NSTextField!;
    @IBOutlet var idField: NSTextField!;
    @IBOutlet var boxView: NSBox!;
    
    override var components: [BaseJoinChannelViewController.Component] {
        didSet {
            let hasMix = components.contains(where: { $0.type == .mix });
            let hasMuc = components.contains(where: { $0.type == .muc })
            self.mixCheckbox.isEnabled = (hasMix && hasMuc) ? true : false;
            if !mixCheckbox.isEnabled {
                self.mixCheckbox.state = hasMix ? .on : .off;
            }
            self.updateSubmitState();
        }
    }

    private var mixHeightConstraint: NSLayoutConstraint?;
        
    @IBAction func updateTypeLabel(typeSelector: NSSegmentedControl) {
        switch typeSelector.selectedSegment {
        case 0:
            typeDescription.stringValue = NSLocalizedString("Anyone will be able to join.", comment: "create channel view hine")
        case 1:
            typeDescription.stringValue = NSLocalizedString("Only people with valid invitations will be able to join.", comment: "create channel view hine")
        default:
            typeDescription.stringValue = NSLocalizedString("UNKNOWN", comment: "create channel view hine")
        }
    }

    override func showDisclosure(_ state: Bool) {
        super.showDisclosure(state);
        
        if mixHeightConstraint == nil {
            mixHeightConstraint = mixCheckbox.topAnchor.constraint(equalTo: self.boxView.bottomAnchor);//mixCheckbox.heightAnchor.constraint(equalToConstant: 0);
            mixHeightConstraint?.priority = .required;
        }
        mixHeightConstraint?.isActive = !state;
        mixCheckbox.isHidden = !state;
        idField.isHidden = !state;
        idLabel.isHidden = !state;
    }
    
    override func canSubmit() -> Bool {
        return super.canSubmit() && !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
    }
    
    override func submitClicked(_ sender: NSButton) {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        guard let account = self.account, !name.isEmpty, let window = self.view.window else {
            return;
        }
        
        let description = descriptionField.stringValue.isEmpty ? nil : descriptionField.stringValue;
        let type: BaseJoinChannelViewController.ComponentType = mixCheckbox.state == .on ? .mix : .muc;
        let isPrivate = typeSelector.indexOfSelectedItem == 1;
        var localPart: String? = idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        if localPart?.isEmpty ?? true {
            localPart = isPrivate ? nil : name.replacingOccurrences(of: " ", with: "-");
        }
        let avatar: NSImage? = self.avatarButton.image;
        
        self.create(account: account, channelLocalPart: localPart, channelName: name, channelDescription: description, type: type, private: isPrivate, avatar: avatar, completionHander: { result, wasCreated, completionHandler in
            DispatchQueue.main.async {
                switch result {
                case .success(let channelJid):
                    guard let controller = NSStoryboard(name: "MIX", bundle: nil).instantiateController(withIdentifier: "EnterChannelViewController") as? EnterChannelViewController else {
                        return;
                    }
                    
                    _ = controller.view;
                    controller.account = account;
                    controller.channelJid = channelJid;
                    controller.channelName = name;
                    controller.componentType = type;
                    controller.suggestedNickname = nil;
                    controller.password = nil;
                    controller.isCreation = !wasCreated;
                    if !wasCreated {
                        controller.info = DiscoveryModule.DiscoveryInfoResult(identities: [.init(category: "conference", type: "text", name: name)], features: [], form: nil);
                    }
                    
                    let windowController = NSWindowController(window: NSWindow(contentViewController: controller));
                    window.beginSheet(windowController.window!, completionHandler: { result in
                        switch result {
                        case .OK:
                            completionHandler?();
                            self.close();
                        default:
                            break;
                        }
                    });
                case .failure(let error):
                    guard let window = self.view.window else {
                        return;
                    }
                    let alert = NSAlert();
                    alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                    alert.icon = NSImage(named: NSImage.cautionName);
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not create channel on the server. Got following error: %@", comment: "alert window message"), error.localizedDescription);
                    alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                    alert.beginSheetModal(for: window, completionHandler: nil);
                }
            }
        });
    }
    
    func create(account: BareJID, channelLocalPart: String?, channelName: String, channelDescription: String?, type: BaseJoinChannelViewController.ComponentType, private priv: Bool, avatar: NSImage?, completionHander: @escaping (Result<BareJID,XMPPError>,Bool, (()->Void)?)->Void) {
        guard let client = XmppService.instance.getClient(for: account), let component = self.components.first(where: { $0.type == type }) else {
            return;
        }
        
        switch type {
        case .mix:
            self.operationStarted();
            
            let mixModule = client.module(.mix);
            mixModule.create(channel: channelLocalPart, at: component.jid.bareJid, completionHandler: { [weak self] result in
                switch result {
                case .success(let channelJid):
                    let info = ChannelInfo(name: channelName, description: channelDescription, contact: []);
                    mixModule.publishInfo(for: channelJid, info: info, completionHandler: { result in
                        switch result {
                        case .success(_):
                            if let context = mixModule.context, let channel =                             DBChatStore.instance.channel(for: context, with: channelJid) {
                                channel.update(info: info);
                            }
                        default:
                            break;
                        }
                    });
                    if let avatarData = avatar?.scaled(maxWidthOrHeight: 512.0).jpegData(compressionQuality: 0.8) {
                        client.module(.pepUserAvatar).publishAvatar(at: channelJid, avatar: [PEPUserAvatarModule.Avatar(data: avatarData, mimeType: "image/jpeg")], completionHandler: { result in
                            self?.logger.debug("avatar publication result: \(result)");
                        });
                    }
                    if priv {
                        mixModule.changeAccessPolicy(of: channelJid, isPrivate: priv, completionHandler: { result in
                            self?.logger.debug("changed channel access policy: \(result)");
                        })
                    }
                    completionHander(.success(channelJid), true, nil);
                case .failure(let error):
                    completionHander(.failure(error), false, nil);
                }
                DispatchQueue.main.async {
                    self?.operationFinished();
                }
            })
            break;
        case .muc:
            let mucModule = client.module(.muc);

            let roomName = channelLocalPart ?? UUID().uuidString;
            
            self.operationStarted();

            let form = JabberDataElement(type: .submit);
            form.addField(TextSingleField(name: "muc#roomconfig_roomname", value: channelName));
            form.addField(BooleanField(name: "muc#roomconfig_membersonly", value: priv));
            form.addField(BooleanField(name: "muc#roomconfig_publicroom", value: !priv));
            form.addField(TextSingleField(name: "muc#roomconfig_roomdesc", value: channelDescription));
            form.addField(TextSingleField(name: "muc#roomconfig_whois", value: priv ? "anyone" : "moderators"))
            let roomJid = BareJID(localPart: roomName, domain: component.jid.domain);
            mucModule.setRoomConfiguration(roomJid: JID(roomJid), configuration: form, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    let vcard = VCard();
                    if let binval = avatar?.scaled(maxWidthOrHeight: 512.0).jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                        vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
                    }
                    client.module(.vcardTemp).publishVCard(vcard, to: roomJid, completionHandler: nil);
                    completionHander(.success(roomJid), true, {
                        if channelDescription != nil {
                            mucModule.setRoomSubject(roomJid: roomJid, newSubject: channelDescription);
                        }
                    });
                    DispatchQueue.main.async {
                        self?.operationFinished();
                    }
                case .failure(let error):
                    guard error == .item_not_found else {
                        completionHander(.failure(error), false, nil);
                        DispatchQueue.main.async {
                            self?.operationFinished();
                        }
                        return;
                    }
                    // workaround for prosody sending item-not-found but allowing to create a room anyway..
                    let vcard = VCard();
                    if let binval = avatar?.scaled(maxWidthOrHeight: 512.0).jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                        vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
                    }
                    completionHander(.success(roomJid), false, {
                        client.module(.vcardTemp).publishVCard(vcard, to: roomJid, completionHandler: nil);
                        if channelDescription != nil {
                            mucModule.setRoomSubject(roomJid: roomJid, newSubject: channelDescription);
                        }
                    });
                    DispatchQueue.main.async {
                        self?.operationFinished();
                    }                }
            });
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
    
    func controlTextDidChange(_ obj: Notification) {
        guard let sender = obj.object as? NSTextField else {
            return;
        }
        if sender == idField {
            let val = idField.stringValue;
            if val.contains("@") || val.contains(" ") {
                idField.stringValue = val.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: " ", with: "");
            }
        }
        updateSubmitState();
    }
}
