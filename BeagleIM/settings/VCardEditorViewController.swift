//
// VCardEditorViewController.swift
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
import TigaseSwift

class VCardEditorViewController: NSViewController, AccountAware {
    
    var account: BareJID?;
    
    var vcard: VCard = VCard(vcard4: Element(name: "vcard", xmlns: "urn:ietf:params:xml:ns:vcard-4.0"))! {
        didSet {
            counter = 0;
            
            let uri = vcard.photos.first?.uri;
            avatarView.image = uri == nil ? NSImage(named: NSImage.userName) : NSImage(contentsOf: URL(string: uri!)!);
            givenNameField.stringValue = vcard.givenName ?? "";
            familyNameField.stringValue = vcard.surname ?? "";
            fullNameField.stringValue = vcard.fn ?? "";
            birthdayField.stringValue = vcard.bday ?? "";
            oragnizationField.stringValue = vcard.organizations.first?.name ?? "";
            organiaztionRoleField.stringValue = vcard.role ?? "";
            
            phonesStackView.views.forEach { (v) in
                v.removeFromSuperview();
            }
            vcard.telephones.forEach { p in
                self.addRow(phone: p);
            }
            emailsStackView.views.forEach { (v) in
                v.removeFromSuperview();
            }
            vcard.emails.forEach { (e) in
                self.addRow(email: e);
            }
            addressesStackView.views.forEach { (v) in
                v.removeFromSuperview();
            }
            vcard.addresses.forEach { (a) in
                self.addRow(address: a);
            }
        }
    }
    var isPrivate: Bool = false;
    
    @IBOutlet var avatarView: NSButton!;
    @IBOutlet var givenNameField: NSTextField!;
    @IBOutlet var familyNameField: NSTextField!;
    @IBOutlet var fullNameField: NSTextField!;
    @IBOutlet var birthdayField: NSTextField!;
    @IBOutlet var oragnizationField: NSTextField!;
    @IBOutlet var organiaztionRoleField: NSTextField!;
    
    @IBOutlet var addPhoneButton: NSButton!;
    @IBOutlet var phonesStackView: NSStackView!;
    @IBOutlet var addEmailButton: NSButton!;
    @IBOutlet var emailsStackView: NSStackView!;
    @IBOutlet var addAddressButton: NSButton!;
    @IBOutlet var addressesStackView: NSStackView!;
    
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    @IBOutlet var submitButton: NSButton!;
    
    var counter = 0;
    
    var isEnabled: Bool = false {
        didSet {
            [givenNameField, familyNameField, fullNameField, birthdayField, oragnizationField, organiaztionRoleField].forEach { (field) in
                self.setEnabled(field: field, value: isEnabled);
            }
            addPhoneButton.isHidden = !isEnabled;
            phonesStackView.views.map { (v) -> Row in
                return v as! Row
                }.forEach { (r) in
                    r.isEnabled = isEnabled;
            }
            addEmailButton.isHidden = !isEnabled;
            emailsStackView.views.map { (v) -> Row in
                return v as! Row
                }.forEach { (r) in
                    r.isEnabled = isEnabled;
            }
            addAddressButton.isHidden = !isEnabled;
            addressesStackView.views.map { (v) -> Row in
                return v as! Row
                }.forEach { (r) in
                    r.isEnabled = isEnabled;
            }
            submitButton.isEnabled = isEnabled;
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        if self.account != nil {
            refreshVCard();
        } else {
            self.vcard = VCard(vcard4: Element(name: "vcard", xmlns: "urn:ietf:params:xml:ns:vcard-4.0"))!;
        }
    }
        
    
    func refreshVCard() {
        if let account = self.account {
            if isPrivate {
                progressIndicator.startAnimation(self);
                self.isEnabled = false;
                PrivateVCard4Helper.retrieve(on: account, from: account, completionHandler: { res in
                    let result: Result<VCard,ErrorCondition> = res.flatMapError({ err in
                        if err == .item_not_found {
                            // there may be no node yet..
                            return .success(VCard());
                        } else {
                            return .failure(err);
                        }
                    });
                    DispatchQueue.main.async {
                        self.progressIndicator.stopAnimation(self);
                        switch result {
                        case .success(let vcard):
                            self.vcard = vcard;
                            self.isEnabled = true;
                        case .failure(let error):
                            self.handleError(title: NSLocalizedString("Could not retrive current version of a private VCard from the server.", comment: "vcard editor"), message: String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "vcard editor"), error.rawValue));
                        }
                    }
                });
            } else {
                progressIndicator.startAnimation(self);
                self.isEnabled = false;
                guard let client = XmppService.instance.getClient(for: account), client.state == .connected() else {
                    self.handleError(title: NSLocalizedString("Could not retrive current version from the server.", comment: "vcard editor"), message: NSLocalizedString("Account is not connected", comment: "vcard editor"));
                    progressIndicator.stopAnimation(self);
                    return;
                }
                client.module(.vcard4).retrieveVCard(completionHandler: { (result) in
                    switch result {
                    case .success(let vcard):
                        DBVCardStore.instance.updateVCard(for: account, on: account, vcard: vcard);
                        DispatchQueue.main.async {
                            self.vcard = vcard;
                            self.progressIndicator.stopAnimation(self);
                            self.isEnabled = true;
                        }
                    case .failure(let error):
                        self.progressIndicator.stopAnimation(self);
                        self.handleError(title: NSLocalizedString("Could not retrive current version from the server.", comment: "vcard editor"), message: String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "vcard editor"), error.description));
                    }
                })
            }
        }
    }
    
    func nextCounter() -> Int {
        counter = counter + 1;
        return counter;
    }
    
    fileprivate func setEnabled(field: NSTextField, value: Bool) {
        field.isEditable = value;
        field.isBezeled = value;
        field.isBordered = value;
        field.drawsBackground = value;
    }
    
    @IBAction func avatarClicked(_ sender: NSButton) {
        let openFile = NSOpenPanel();
        openFile.worksWhenModal = true;
        openFile.prompt = "Select avatar";
        openFile.canChooseDirectories = false;
        openFile.canChooseFiles = true;
        openFile.canSelectHiddenExtension = true;
        openFile.canCreateDirectories = false;
        openFile.allowsMultipleSelection = false;
        openFile.resolvesAliases = true;
        
        openFile.begin { (response) in
            guard response == .OK, let url = openFile.url, let image = NSImage(contentsOf: url) else {
                return;
            }

            let pngImage = image.scaled(maxWidthOrHeight: 48);
            guard let pngData = pngImage.pngData() else {
                return;
            }
            
            var avatar: [PEPUserAvatarModule.Avatar] = [.init(data: pngData, mimeType: "image/png", width: Int(pngImage.size.width), height: Int(pngImage.size.height))];
            
            let jpegImage = image.scaled(maxWidthOrHeight: 256);
            if let jpegData = jpegImage.jpegData(compressionQuality: 0.8) {
                avatar = [.init(data: jpegData, mimeType: "image/jpeg", width: Int(jpegImage.size.width), height: Int(jpegImage.size.height))] + avatar;
            }
            
            self.avatarView.image = jpegImage;
            if let data = avatar.first?.data {
                self.vcard.photos = [ VCard.Photo(uri: nil, type: "image/jpeg", binval: data.base64EncodedString(options: []), types: [.home]) ];
            }
            
            guard let account = self.account, let avatarModule = XmppService.instance.getClient(for: account)?.module(.pepUserAvatar), avatarModule.isPepAvailable else {
                return;
            }

            DispatchQueue.main.async {
                let alert = NSAlert();
                alert.messageText = NSLocalizedString("Should avatar be updated?", comment: "vcard editor - alert window title");
                alert.addButton(withTitle: NSLocalizedString("Yes", comment: "button"));
                alert.addButton(withTitle: NSLocalizedString("No", comment: "button"));
                alert.icon = NSImage(named: NSImage.userName);
                alert.beginSheetModal(for: self.view.window!, completionHandler: { (response) in
                    if response == NSApplication.ModalResponse.alertFirstButtonReturn {
                        self.publish(avatar: avatar);
                    }
                })
            }
        }
    }
    
    @IBAction func addPhone(_ sender: NSButton) {
        let item = VCard.Telephone(uri: nil, kinds: [.cell], types: [.home]);
        vcard.telephones.append(item);
        addRow(phone: item);
    }

    @IBAction func addEmail(_ sender: NSButton) {
        let item = VCard.Email(address: nil, types: [.home]);
        vcard.emails.append(item);
        addRow(email: item);
    }

    @IBAction func addAddress(_ sender: NSButton) {
        let item = VCard.Address(types: [.home]);
        vcard.addresses.append(item);
        addRow(address: item);
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.dismiss(self);
    }

    @IBAction func submitClicked(_ sender: NSButton) {
        self.view.window?.makeFirstResponder(sender);

        if isPrivate {
            if let account = self.account {
                self.isEnabled = false;
                self.progressIndicator.startAnimation(self);
                PrivateVCard4Helper.publish(on: account, vcard: vcard, completionHandler: { result in
                    DispatchQueue.main.async {
                        self.progressIndicator.stopAnimation(self);
                        self.isEnabled = true;
                        switch result {
                        case .success(_):
                            self.dismiss(self);
                        case .failure(let error):
                            self.handleError(title: NSLocalizedString("Publication of new version of private VCard failed", comment: "vcard editor"), message: String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "vcard editor"), error.error.message ?? error.description));
                        }
                    }
                })
            }
        } else {
            guard let account = self.account, let vcard4Module = XmppService.instance.getClient(for: account)?.module(.vcard4) else {
                self.handleError(title: NSLocalizedString("Publication of new version of VCard failed", comment: "vcard editor"), message: NSLocalizedString("Account is not connected", comment: "vcard editor"));
                return;
            }
            self.isEnabled = false;
            self.progressIndicator.startAnimation(self);
            vcard4Module.publishVCard(vcard, completionHandler: { result in
                switch result {
                case .success(_):
                    DBVCardStore.instance.updateVCard(for: account, on: account, vcard: self.vcard);
                    DispatchQueue.main.async {
                        self.progressIndicator.stopAnimation(self);
                        self.isEnabled = true;
                        self.dismiss(self);
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        self.progressIndicator.stopAnimation(self);
                        self.isEnabled = true;
                        self.handleError(title: NSLocalizedString("Publication of new version of VCard failed", comment: "vcard editor"), message: String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "vcard editor"), error.description));
                    }
                }
            });
        }
    }

    fileprivate func handleError(title: String, message msg: String) {
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.view.window else {
                return;
            }
            let alert = NSAlert();
            alert.messageText = title;
            alert.informativeText = msg;
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.beginSheetModal(for: window, completionHandler: nil);
        }
    }

    @objc func removePositionClicked(_ sender: NSButton) {
        if let found = phonesStackView.views.firstIndex(where: { (v) -> Bool in
            guard let btn = (v as? NSStackView)?.views.last as? NSButton else {
                return false;
            }
            return btn === sender;
        }) {
            phonesStackView.views[found].removeFromSuperview();
            vcard.telephones.remove(at: found);
        }
        if let found = emailsStackView.views.firstIndex(where: { (v) -> Bool in
            guard let btn = (v as? NSStackView)?.views.last as? NSButton else {
                return false;
            }
            return btn === sender;
        }) {
            emailsStackView.views[found].removeFromSuperview();
            vcard.emails.remove(at: found);
        }
        if let found = addressesStackView.views.firstIndex(where: { (v) -> Bool in
            guard let btn = (v as? NSStackView)?.views.last as? NSButton else {
                return false;
            }
            return btn === sender;
        }) {
            addressesStackView.views[found].removeFromSuperview();
            vcard.addresses.remove(at: found);
        }
    }
    
    fileprivate func addRow(address item: VCard.Address) {
        let tag = nextCounter();
        let streetField = NSTextField(string: item.street ?? "");
        streetField.placeholderString = NSLocalizedString("Street", comment: "vcard editor");
        connect(field: streetField, tag: tag, action: #selector(streetChanged(_:)));
        let zipCodeField = NSTextField(string: item.postalCode ?? "");
        zipCodeField.placeholderString = NSLocalizedString("Code", comment: "vcard editor");
        connect(field: zipCodeField, tag: tag, action: #selector(postalCodeChanged(_:)));
        let cityField = NSTextField(string: item.locality ?? "");
        cityField.placeholderString = NSLocalizedString("Locality", comment: "vcard editor");
        connect(field: cityField, tag: tag, action: #selector(localityChanged(_:)));
        let countryField = NSTextField(string: item.country ?? "");
        countryField.placeholderString = NSLocalizedString("Country", comment: "vcard editor");
        connect(field: countryField, tag: tag, action: #selector(countryChanged(_:)));

        let subdate = NSStackView(views: [zipCodeField, cityField]);
        subdate.orientation = .horizontal;
        zipCodeField.widthAnchor.constraint(equalTo: cityField.widthAnchor, multiplier: 0.4).isActive = true;
        
        let data = NSStackView(views: [streetField, subdate, countryField]);
        data.orientation = .vertical;
        data.spacing = 4;
        
        let stack = Row(views: [createTypeButton(for: item, tag: tag, action: #selector(addressTypeChanged(_:))), data, createRemoveButton(for: item)]);
        stack.id = tag;
        stack.orientation = .horizontal;
        stack.alignment = .top;
        stack.spacing = 4;
        addressesStackView.addView(stack, in: .bottom);
    }
    
    fileprivate func addRow(email item: VCard.Email) {
        let tag = nextCounter();
        let numberField = NSTextField(string: item.address ?? "");
        numberField.placeholderString = NSLocalizedString("Enter email address", comment: "vcard editor");
        connect(field: numberField, tag: tag, action: #selector(emailChanged(_:)));
        let stack = Row(views: [createTypeButton(for: item, tag: tag, action: #selector(emailTypeChanged(_:))), numberField, createRemoveButton(for: item)]);
        stack.id = tag;
        stack.orientation = .horizontal;
        stack.spacing = 4;
        emailsStackView.addView(stack, in: .bottom);
    }
    
    fileprivate func addRow(phone item: VCard.Telephone) {
        let tag = nextCounter();
        let numberField = NSTextField(string: item.number ?? "");
        numberField.placeholderString = NSLocalizedString("Enter phone number", comment: "vcard editor");
        connect(field: numberField, tag: tag, action: #selector(phoneNumberChanged(_:)));
        let stack = Row(views: [createTypeButton(for: item, tag: tag, action: #selector(phoneNumberTypeChanged(_:))), numberField, createRemoveButton(for: item)]);
        stack.id = tag;
        stack.orientation = .horizontal;
        stack.spacing = 4;
        phonesStackView.addView(stack, in: .bottom);
    }

    fileprivate func connect(field: NSTextField, tag: Int, action: Selector) {
        field.tag = tag;
        field.target = self;
        field.action = action;
        field.sendAction(on: .endGesture)
    }
    
    @IBAction func fieldChanged(_ sender: NSTextField) {
        switch sender {
        case givenNameField:
            vcard.givenName = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case familyNameField:
            vcard.surname = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case fullNameField:
            vcard.fn = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case birthdayField:
            vcard.bday = sender.stringValue.isEmpty ? nil : sender.stringValue;
        case oragnizationField:
            vcard.organizations = sender.stringValue.isEmpty ? [] : [VCard.Organization(name: sender.stringValue)];
        case organiaztionRoleField:
            vcard.role = sender.stringValue.isEmpty ? nil : sender.stringValue;
        default:
            break;
        }
    }
    
    @objc fileprivate func emailTypeChanged(_ sender: NSPopUpButton) {
        guard let idx = findPosition(in: emailsStackView, byId: sender.tag) else {
            return;
        }
        vcard.emails[idx].types = [ sender.indexOfSelectedItem == 0 ? .home : .work ];
    }
    
    @objc fileprivate func emailChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: emailsStackView, byId: sender.tag) else {
            return;
        }
        vcard.emails[idx].address = value;
    }
    
    @objc fileprivate func phoneNumberTypeChanged(_ sender: NSPopUpButton) {
        guard let idx = findPosition(in: phonesStackView, byId: sender.tag) else {
            return;
        }
        vcard.telephones[idx].types = [ sender.indexOfSelectedItem == 0 ? .home : .work ];
    }
    
    @objc fileprivate func phoneNumberChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: phonesStackView, byId: sender.tag) else {
            return;
        }
        vcard.telephones[idx].number = value;
    }
    
    @objc fileprivate func addressTypeChanged(_ sender: NSPopUpButton) {
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].types = [ sender.indexOfSelectedItem == 0 ? .home : .work ];
    }
    
    @objc fileprivate func streetChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].street = value;
    }

    @objc fileprivate func postalCodeChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].postalCode = value;
    }

    @objc fileprivate func localityChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].locality = value;
    }

    @objc fileprivate func countryChanged(_ sender: NSTextField) {
        let value = sender.stringValue.isEmpty ? nil : sender.stringValue;
        guard let idx = findPosition(in: addressesStackView, byId: sender.tag) else {
            return;
        }
        vcard.addresses[idx].country = value;
    }

    fileprivate func findPosition(in stack: NSStackView, byId id: Int) -> Int? {
        return stack.views.firstIndex(where: {(v) -> Bool in
            return ((v as? Row)?.id ?? -1) == id;
        });
    }
    
    fileprivate func createRemoveButton(for item: VCard.VCardEntryItemTypeAware) -> NSButton {
        let removeButton = NSButton(image: NSImage(named: NSImage.removeTemplateName)!, target: self, action: #selector(removePositionClicked));
        removeButton.bezelStyle = .texturedRounded;
        return removeButton;
    }
 
    fileprivate func createTypeButton(for item: VCard.VCardEntryItemTypeAware, tag: Int, action: Selector) -> NSButton {
        let typeButton = NSPopUpButton(frame: .zero, pullsDown: false);
        typeButton.addItem(withTitle: NSLocalizedString("Home", comment: "vcard editor"));
        typeButton.addItem(withTitle: NSLocalizedString("Work", comment: "vcard editor"));
        typeButton.selectItem(at: item.types.contains(VCard.EntryType.home) ? 0 : 1);
        typeButton.tag = tag;
        typeButton.action = action;
        return typeButton;
    }
    
    private func publish(avatar: [PEPUserAvatarModule.Avatar]) {
        guard let account = self.account, let avatarModule = XmppService.instance.getClient(for: account)?.module(.pepUserAvatar) else {
            handleError(title: NSLocalizedString("Publication of avatar failed", comment: "vcard editor"), message: NSLocalizedString("Account is not connected", comment: "vcard editor"));
            return;
        }
        avatarModule.publishAvatar(avatar: avatar, completionHandler: { result in
            switch result {
            case .success(_):
                break;
            case .failure(let error):
                self.handleError(title: NSLocalizedString("Publication of avatar failed", comment: "vcard editor"), message: String.localizedStringWithFormat(NSLocalizedString("Server returned an error: %@", comment: "vcard editor"), error.error.message ?? error.description));
            }
        });
    }
    
    class Row: NSStackView {
        
        var id: Int = -1;
        
        var isEnabled: Bool = true {
            didSet {
                if let btn = views.first as? NSButton {
                    btn.isEnabled = isEnabled;
                    btn.isBordered = isEnabled;
                }
                setEnabled(views: self.views, value: isEnabled);
                if let btn = views.last as? NSButton {
                    btn.isHidden = !isEnabled;
                }

            }
        }
        
        fileprivate func setEnabled(views: [NSView], value isEnabled: Bool) {
            views.forEach { (v) in
                if let field = v as? NSTextField {
                    self.setEnabled(field: field, value: isEnabled);
                }
                if let stack = v as? NSStackView {
                    setEnabled(views: stack.views, value: isEnabled);
                }
            }
        }
        
        fileprivate func setEnabled(field: NSTextField, value isEnabled: Bool) {
            field.isEditable = isEnabled;
            field.isBezeled = isEnabled;
            field.isBordered = isEnabled;
            field.drawsBackground = isEnabled;
        }
        
    }
}
