//
// BaseJoinChannelViewController.swift
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

class BaseJoinChannelViewController: NSViewController {
 
    @IBOutlet var accountButton: NSPopUpButton!;
    @IBOutlet var componentDomainField: NSTextField!;
    @IBOutlet var progressIndication: NSProgressIndicator!;
    @IBOutlet var submitButton: NSButton!;

    private var accountHeightConstraint: NSLayoutConstraint!;
    
    var account: BareJID?;
    var components: [Component] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        accountHeightConstraint = accountButton.heightAnchor.constraint(equalToConstant: 0);
    }

    override func viewWillAppear() {
        self.accountButton.addItem(withTitle: "");
        AccountManager.accountNames().filter { account -> Bool in
            return XmppService.instance.getClient(for: account) != nil
            }.forEach { (account) in
            self.accountButton.addItem(withTitle: account.description);
        }
        if self.account == nil {
            self.account = AccountManager.defaultAccount;
        }
        if let account = self.account {
            self.accountButton.selectItem(withTitle: account.description);
            self.accountButton.title = account.description;
        } else {
            self.accountButton.selectItem(at: 1);
            self.accountButton.title = self.accountButton.itemTitle(at: 1);
            self.account = BareJID(self.accountButton.itemTitle(at: 1));
        }
        showDisclosure(AccountManager.accounts.count != 1);
        findComponents();
        updateSubmitState();
    }
    
    @IBAction func accountSelectionChanged(_ sender: NSPopUpButton) {
        guard let title = sender.selectedItem?.title else {
            return;
        }
        self.accountButton.title = title;
        let account = BareJID(title);
        if self.account != account {
            self.account = account;
            self.findComponents();
        }
    }
    
    @IBAction func componentDomainChanged(_ sender: NSTextField) {
        findComponents();
    }
    
    private func findComponents() {
        let domain = componentDomainField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
        guard let account = self.account else {
            return;
        }
        self.findComponents(for: account, at: domain.isEmpty ? account.domain : domain);
    }

    @IBAction func disclosureChangedState(_ sender: NSButton) {
        showDisclosure(sender.state == .on);
    }
    
    func showDisclosure(_ state: Bool) {
        accountButton.isHidden = !state;
        accountHeightConstraint.isActive = !state;
    }

    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }

    @IBAction func submitClicked(_ sender: NSButton) {
        close();
    }
    
    func operationStarted() {
        progressIndication.startAnimation(self);
    }
    
    func operationFinished() {
        progressIndication.stopAnimation(self);
    }
    
    func updateSubmitState() {
        submitButton.isEnabled = canSubmit();
    }
    
    func canSubmit() -> Bool {
        return account != nil && !components.isEmpty;
    }
    
    func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
    
    static func askForNickname(for account: BareJID, suggestedNickname: String? = nil, window: NSWindow, completionHandler: @escaping (String)->Void) {
        let alert = NSAlert();
        alert.alertStyle = .informational;
        alert.icon = NSImage(named: NSImage.userName);
        alert.messageText = NSLocalizedString("Nickname", comment: "alert window title");
        alert.informativeText = NSLocalizedString("Enter a nickname which you want to use in this channel.", comment: "alert window message");
        let nicknameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 7 + NSFont.systemFontSize));
        nicknameField.stringValue = suggestedNickname ?? AccountManager.account(for: account)?.nickname ?? ""
        alert.accessoryView = nicknameField;
        alert.addButton(withTitle: NSLocalizedString("Submit", comment: "Button"));
        alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Button"));
        alert.beginSheetModal(for: window, completionHandler: { response in
            switch response {
            case .alertFirstButtonReturn:
                let nickname = nicknameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines);
                guard !nickname.isEmpty else {
                    return;
                }
                completionHandler(nickname);
            default:
                break;
            }
        })
    }

    func findComponents(for account: BareJID, at domain: String) {
        let domainJid = JID(domain);
        guard let discoModule = XmppService.instance.getClient(for: account)?.module(.disco) else {
            return;
        }
        operationStarted();
        
        Task {
            do {
                let components = try await retrieveComponents(from: domainJid, name: nil, discoModule: discoModule);
                await MainActor.run(body: {
                    self.components = components;
                })
            } catch {
                await MainActor.run(body: {
                    self.operationFinished();
                })
            }
        }
    }
    
    private func retrieveComponents(from domain: JID, name: String?, discoModule: DiscoveryModule) async throws -> [Component] {
        do {
            return [try await retrieveComponent(from: domain, name: nil, discoModule: discoModule)];
        } catch {
            let items = try await discoModule.items(for: domain);
            return await items.items.concurrentMap({ try? await self.retrieveComponent(from: $0.jid, name: $0.name, discoModule: discoModule) }).compactMap({ $0 });
        }
    }
    
    private func retrieveComponent(from jid: JID, name: String?, discoModule: DiscoveryModule) async throws -> Component {
        let info = try await discoModule.info(for: jid);
        guard let component = Component(jid: jid, name: name, identities: info.identities, features: info.features) else {
            throw XMPPError(condition: .item_not_found);
        }
        return component;
    }
    
    enum ComponentType {
        case muc
        case mix
        
        static func from(identities: [DiscoveryModule.Identity], features: [String]) -> ComponentType? {
            if identities.first(where: { $0.category == "conference" && $0.type == "mix" }) != nil && features.contains(MixModule.CORE_XMLNS) {
                return .mix;
            }
            if identities.first(where: { $0.category == "conference" }) != nil && features.contains("http://jabber.org/protocol/muc") {
                return .muc;
            }
            return nil;
        }
    }
    
    class Component {
        let jid: JID;
        let name: String?;
        let type: ComponentType;
        
        convenience init?(jid: JID, name: String?, identities: [DiscoveryModule.Identity], features: [String]) {
            guard let type = ComponentType.from(identities: identities, features: features) else {
                return nil;
            }
            self.init(jid: jid, name: name ?? identities.first(where: { $0.name != nil})?.name, type: type);
        }
        
        init(jid: JID, name: String?, type: ComponentType) {
            self.jid = jid;
            self.name = name;
            self.type = type;
        }
    }
}


