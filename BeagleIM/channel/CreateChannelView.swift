//
// CreateChannelView.swift
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
import Quartz
import TigaseSwift
import TigaseLogging

class CreateChannelView: NSView, OpenChannelViewControllerTabView, NSTextFieldDelegate {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "CreateChannelView");
    
    weak var delegate: OpenChannelViewControllerTabViewDelegate?;
    
    var account: BareJID?;
    
    var components: [OpenChannelViewController.Component] = [] {
        didSet {
            let hasMix = components.contains(where: { $0.type == .mix });
            let hasMuc = components.contains(where: { $0.type == .muc })
            self.mixCheckbox.isEnabled = (hasMix && hasMuc) ? true : false;
            if !mixCheckbox.isEnabled {
                self.mixCheckbox.state = hasMix ? .on : .off;
            }
            self.useMixChanged();
            delegate?.updateSubmitState();
        }
    }
    
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
        useMixChanged();
    }
    
    func disclosureChanged(state: Bool) {
        if mixHeightConstraint == nil {
            mixHeightConstraint = mixCheckbox.topAnchor.constraint(equalTo: self.bottomAnchor);//mixCheckbox.heightAnchor.constraint(equalToConstant: 0);
            mixHeightConstraint?.priority = .required;
        }
        mixHeightConstraint?.isActive = !state;
        mixCheckbox.isHidden = !state;
        idField.isHidden = !state;
        idLabel.isHidden = !state;
    }
    
    func viewWillAppear() {
        delegate?.updateSubmitState();
    }
    
    func viewDidDisappear() {
        // nothing to do..
    }
    
    func cancelClicked(completionHandler: (() -> Void)?) {
        completionHandler?();
    }
    
    func submitClicked(completionHandler: ((Bool) -> Void)?) {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        guard let delegate = self.delegate, let account = self.account, !name.isEmpty else {
            completionHandler?(false);
            return;
        }
        let description = descriptionField.stringValue.isEmpty ? nil : descriptionField.stringValue;
        let type: OpenChannelViewController.ComponentType = mixCheckbox.state == .on ? .mix : .muc;
        let isPrivate = typeSelector.indexOfSelectedItem == 1;
        var localPart: String? = idField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        if localPart?.isEmpty ?? true {
            localPart = isPrivate ? nil : name.replacingOccurrences(of: " ", with: "-");
        }
        let avatar: NSImage? = self.avatarButton.image;
        delegate.askForNickname(completionHandler: { nickname in
            self.create(account: account, channelLocalPart: localPart, channelName: name, channelDescription: description, nickname: nickname, type: type, private: isPrivate, avatar: avatar, completionHandler: completionHandler!);
        })
    }

    func canSubmit() -> Bool {
        return account != nil && !components.isEmpty && !nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
    }

    func create(account: BareJID, channelLocalPart: String?, channelName: String, channelDescription: String?, nickname: String, type: OpenChannelViewController.ComponentType, private priv: Bool, avatar: NSImage?, completionHandler: @escaping (Bool)->Void) {
        guard let client = XmppService.instance.getClient(for: account), let component = self.components.first(where: { $0.type == type }) else {
            completionHandler(false);
            return;
        }
        
        switch type {
        case .mix:
            self.delegate?.operationStarted();
            
            let mixModule = client.module(.mix);
            mixModule.create(channel: channelLocalPart, at: component.jid.bareJid, completionHandler: { [weak self] result in
                switch result {
                case .success(let channelJid):
                    mixModule.join(channel: channelJid, withNick: nickname, completionHandler: { result in
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
                            DispatchQueue.main.async {
                                completionHandler(true);
                            }
                        case .failure(let error):
                            DispatchQueue.main.async {
                                completionHandler(false);
                                guard let window = self?.window else {
                                    return;
                                }
                                let alert = NSAlert();
                                alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                                alert.icon = NSImage(named: NSImage.cautionName);
                                alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not join newly created channel '%@' on the server. Got following error: %@", comment: "alert window message"), channelJid.description, error.message ?? error.description);
                                alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                                alert.beginSheetModal(for: window, completionHandler: { result in
                                    self?.delegate?.operationFinished();
                                });
                            }
                        }
                        DispatchQueue.main.async {
                            self?.delegate?.operationFinished();
                        }
                    })
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
                        client.module(.pepUserAvatar).publishAvatar(at: channelJid, data: avatarData, mimeType: "image/jpeg", completionHandler: { result in
                            self?.logger.debug("avatar publication result: \(result)");
                        });
                    }
                    if priv {
                        mixModule.changeAccessPolicy(of: channelJid, isPrivate: priv, completionHandler: { result in
                            self?.logger.debug("changed channel access policy: \(result)");
                        })
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        completionHandler(false);
                        guard let window = self?.window else {
                            return;
                        }
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not create channel on the server. Got following error: %@", comment: "alert window message"), error.message ?? error.description);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: { result in
                            self?.delegate?.operationFinished();
                        });
                    }
                }
            })
            break;
        case .muc:
            let mucModule = client.module(.muc);

            let roomName = channelLocalPart ?? UUID().uuidString;
            
            self.delegate?.operationStarted();

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
                    mucModule.join(roomName: roomName, mucServer: component.jid.domain, nickname: nickname).handle({ result in
                        switch result {
                        case .success(let r):
                            switch r {
                            case .created(let room), .joined(let room):
                                var features = Set<Room.Feature>();
                                features.insert(.nonAnonymous);
                                if priv {
                                    features.insert(.membersOnly);
                                }
                                (room as! Room).features = features;
                                let vcard = VCard();
                                if let binval = avatar?.scaled(maxWidthOrHeight: 512.0).jpegData(compressionQuality: 0.8)?.base64EncodedString(options: []) {
                                    vcard.photos = [VCard.Photo(uri: nil, type: "image/jpeg", binval: binval, types: [.home])];
                                }
                                client.module(.vcardTemp).publishVCard(vcard, to: room.jid, completionHandler: nil);
                                if channelDescription != nil {
                                    mucModule.setRoomSubject(roomJid: room.jid, newSubject: channelDescription);
                                }
                            }
                        case .failure(let error):
                            guard let room = DBChatStore.instance.room(for: client, with: roomJid) else {
                                return;
                            }
                            MucEventHandler.showJoinError(error, for: room);
                            break;
                        }
                    });
                    DispatchQueue.main.async {
                        self?.delegate?.operationFinished();
                        completionHandler(true);
                    }
                    break;
                case .failure(let error):
                    DispatchQueue.main.async {
                        completionHandler(false);
                        guard let window = self?.window else {
                            return;
                        }
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not apply room configuration on the server. Got following error: %@", comment: "alert window message"), error.message ?? error.description);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: { result in
                            self?.delegate?.operationFinished();
                        });
                    }
                    break;
                }
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
        taker?.beginSheet(for: self.window!, withDelegate: self, didEnd: #selector(avatarSelected), contextInfo: nil);
    }
    
    @objc func avatarSelected(_ pictureTaker: IKPictureTaker, code: Int, context: Any?) {
        guard code == NSApplication.ModalResponse.OK.rawValue  else {
            return;
        }
        avatarButton.image = pictureTaker.outputImage();
    }
    
    @IBAction func useMixChanged(_ sender: NSButton) {
        useMixChanged();
    }
    
    func useMixChanged() {
//        idField.isEnabled = mixCheckbox.state == .off || typeSelector.selectedSegment == 0;
//        if !idField.isEnabled {
//            idField.stringValue = "";
//        }
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
        delegate?.updateSubmitState();
    }
}
