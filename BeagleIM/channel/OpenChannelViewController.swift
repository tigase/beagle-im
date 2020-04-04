//
// OpenChannelViewController.swift
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

class OpenChannelViewController: NSViewController, OpenChannelViewControllerTabViewDelegate {
 
    private var tabView: NSTabView? {
        didSet {
//            (tabView?.selectedTabViewItem?.view as? OpenChannelViewControllerTabView)?.delegate = self;
            showDisclosure(false);
            if let tabView = self.tabView {
                for viewItem in tabView.tabViewItems {
                    if let view = viewItem.view as? OpenChannelViewControllerTabView {
                        view.delegate = self;
                    }
                }
            }
        }
    }
    @IBOutlet var accountButton: NSPopUpButton!;
    @IBOutlet var componentDomainField: NSTextField!;
    @IBOutlet var progressIndication: NSProgressIndicator!;
    
    private var accountHeightConstraint: NSLayoutConstraint!;

    var account: BareJID? {
        didSet {
            if let tabView = self.tabView {
                for viewItem in tabView.tabViewItems {
                    if let view = viewItem.view as? OpenChannelViewControllerTabView {
                        view.account = self.account;
                    }
                }
            }
        }
    }
    
    @IBOutlet var submitButton: NSButton!;

    private var components: [Component] = [] {
        didSet {
            if let tabView = self.tabView {
                for viewItem in tabView.tabViewItems {
                    if let view = viewItem.view as? OpenChannelViewControllerTabView {
                        view.components = self.components;
                    }
                }
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad();
        accountHeightConstraint = accountButton.heightAnchor.constraint(equalToConstant: 0);
    }

    override func viewWillAppear() {
        self.submitButton.title = tabView?.selectedTabViewItem?.label ?? "";
        self.accountButton.addItem(withTitle: "");
        if let tabView = self.tabView {
            for viewItem in tabView.tabViewItems {
                if let view = viewItem.view as? OpenChannelViewControllerTabView {
                    view.delegate = self;
                }
            }
        }
        AccountManager.getAccounts().filter { account -> Bool in
            return XmppService.instance.getClient(for: account) != nil
            }.forEach { (account) in
            self.accountButton.addItem(withTitle: account.stringValue);
        }
        if self.account == nil {
            self.account = AccountManager.defaultAccount;
        }
        if let account = self.account {
            self.accountButton.selectItem(withTitle: account.stringValue);
            self.accountButton.title = account.stringValue;
        } else {
            self.accountButton.selectItem(at: 1);
            self.accountButton.title = self.accountButton.itemTitle(at: 1);
            self.account = BareJID(self.accountButton.itemTitle(at: 1));
        }
        if let account = self.account {
            findComponents();
        }
        self.updateSubmitState();
    }
    
//    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
//        submitButton.title = tabViewItem?.label ?? "";
////        (tabViewItem?.view as? OpenChannelViewControllerTabView)?.delegate = self;
//        (tabViewItem?.view as? OpenChannelViewControllerTabView)?.account = self.account;
//        (tabViewItem?.view as? OpenChannelViewControllerTabView)?.components = self.components;
//        (tabViewItem?.view as? OpenChannelViewControllerTabView)?.disclosureChanged(state: !accountHeightConstraint.isActive);
//        self.updateSubmitState();
//    }
    
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
        if let tabView = self.tabView {
            for viewItem in tabView.tabViewItems {
                if let view = viewItem.view as? OpenChannelViewControllerTabView {
                    view.disclosureChanged(state: state);
                }
            }
        }
    }

    @IBAction func cancelClicked(_ sender: NSButton) {
        guard let view = self.tabView?.selectedTabViewItem?.view as? OpenChannelViewControllerTabView else {
            close();
            return;
        }
        view.cancelClicked(completionHandler: {
            self.close()
        })
    }

    @IBAction func submitClicked(_ sender: NSButton) {
        guard let view = self.tabView?.selectedTabViewItem?.view as? OpenChannelViewControllerTabView else {
            close();
            return;
        }
        view.submitClicked(completionHandler: { result in
            if result {
                self.close()
            }
        })
    }
    
    func operationStarted() {
        progressIndication.startAnimation(self);
    }
    
    func operationFinished() {
        progressIndication.stopAnimation(self);
    }
    
    func updateSubmitState() {
        submitButton.isEnabled = (self.tabView?.selectedTabViewItem?.view as? OpenChannelViewControllerTabView)?.canSubmit() ?? false;
    }
    
    private func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
    
    func askForNickname(completionHandler: @escaping (String) -> Void) {
        OpenChannelViewController.askForNickname(for: self.account!, window: self.view.window!, completionHandler: completionHandler);
    }
    
    static func askForNickname(for account: BareJID, window: NSWindow, completionHandler: @escaping (String)->Void) {
        let alert = NSAlert();
        alert.alertStyle = .informational;
        alert.icon = NSImage(named: NSImage.userName);
        alert.messageText = "Nickname"
        alert.informativeText = "Enter a nickname which you want to use in this channel."
        let nicknameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 7 + NSFont.systemFontSize));
        nicknameField.stringValue = AccountManager.getAccount(for: account)?.nickname ?? ""
        alert.accessoryView = nicknameField;
        alert.addButton(withTitle: "Submit");
        alert.addButton(withTitle: "Cancel");
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
        guard let client = XmppService.instance.getClient(for: account), let discoModule: DiscoveryModule = client.modulesManager.getModule(DiscoveryModule.ID) else {
            return;
        }
        operationStarted();
        
        var components: [Component] = [];
        let group = DispatchGroup();
        group.enter();
        retrieveComponent(from: domainJid, name: nil, discoModule: discoModule, completionHandler: { result in
            switch result {
            case .success(let component):
                DispatchQueue.main.async {
                    components.append(component);
                }
                group.leave();
            case .failure(let error):
                discoModule.getItems(for: domainJid, completionHandler: { result in
                    switch result {
                    case .success(let node, let items):
                        // we need to do disco on all components to find out local mix/muc component..
                        // maybe this should be done once for all "views"?
                        for item in items {
                            group.enter();
                            self.retrieveComponent(from: item.jid, name: item.name, discoModule: discoModule, completionHandler: { result in
                                switch result {
                                case .success(let component):
                                    DispatchQueue.main.async {
                                        components.append(component);
                                    }
                                case .failure(let error):
                                    break;
                                }
                                group.leave();
                            });
                        }
                    case .failure(let errorCondition, let response):
                        break;
                    }
                    group.leave();
                });
            }
        })
        
        group.notify(queue: DispatchQueue.main, execute: {
            self.operationFinished();
            self.components = components;
        })
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let tabViewController = segue.destinationController as? OpenChannelViewTabViewController {
            tabViewController.delegate = self;
            self.tabView = tabViewController.tabView;
        }
    }
    
    private func retrieveComponent(from jid: JID, name: String?, discoModule: DiscoveryModule, completionHandler: @escaping (Result<Component,ErrorCondition>)->Void) {
        discoModule.getInfo(for: jid, completionHandler: { result in
            switch result {
            case .success(let node, let identities, let features):
                guard let component = Component(jid: jid, name: name, identities: identities, features: features) else {
                    completionHandler(.failure(.item_not_found));
                    return;
                }
                completionHandler(.success(component));
            case .failure(let errorCondition, let response):
                completionHandler(.failure(errorCondition));
            }
        })

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

protocol OpenChannelViewControllerTabView: class {
    
    var account: BareJID? { get set }
    var components: [OpenChannelViewController.Component] { get set }
    var delegate: OpenChannelViewControllerTabViewDelegate? { get set }
    
    func canSubmit() -> Bool;
    
    func disclosureChanged(state: Bool);
    
    func cancelClicked(completionHandler: (()->Void)?);
    func submitClicked(completionHandler: ((Bool)->Void)?);
    
    func viewWillAppear();
    func viewDidDisappear();
}

protocol OpenChannelViewControllerTabViewDelegate: class {
    
    func askForNickname(completionHandler: @escaping (String)->Void)
    func operationStarted();
    func operationFinished();
 
    func updateSubmitState();
}

class OpenChannelViewTabViewController: NSTabViewController {
    
    weak var delegate: OpenChannelViewController?;
    
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem);
        let newTabLabel = tabViewItem?.label ?? "";
        for view in tabView.tabViewItems {
            if !(view.label == newTabLabel) {
                (view.view as? OpenChannelViewControllerTabView)?.viewDidDisappear();
            }
        }
        (tabViewItem?.view as? OpenChannelViewControllerTabView)?.viewWillAppear();
    }
    
}
