//
// CreateMeetingController.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import Combine
import TigaseSwift

class CreateMeetingController: NSViewController {

    @IBOutlet var accountSelection: NSPopUpButton!;
    @IBOutlet var contactSelectionView: MultiContactSelectionView!;
    @IBOutlet var createAndInviteButton: NSButton!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    private var cancellables: Set<AnyCancellable> = [];

    @Published
    private var operationInProgress: Bool = false;
    
    private var client: XMPPClient? {
        didSet {
            meetComponents = [];
            if let client = self.client {
                self.operationInProgress = true;
                client.module(.meet).findMeetComponent(completionHandler: { result in
                    DispatchQueue.main.async { [weak self] in
                        guard let that = self, client == self?.client else {
                            return;
                        }
                        switch result {
                        case .failure(let error):
                            that.meetComponents = [];
                            let alert = NSAlert();
                            alert.alertStyle = .warning;
                            alert.messageText = NSLocalizedString("Unable to create a meet", comment: "create meet controller")
                            alert.informativeText = error == .item_not_found ? NSLocalizedString("Selected account does not support creating a meeting. Please select a different account.", comment: "create meet controller") : String.localizedStringWithFormat(NSLocalizedString("While checking for support XMPP server returned an error: %@. Please select a different account or try again later.", comment: "create meet controller"), error.description);
                            alert.beginSheetModal(for: that.view.window!, completionHandler: { response in
                                // nothing to do except closing..
                                //that.close();
                            });
                        case .success(let components):
                            that.meetComponents = components;
                        }
                    }
                    self.operationInProgress = false;
                })
            }
        }
    }
    @Published
    private var meetComponents: [MeetModule.MeetComponent] = [];
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        accountSelection.removeAllItems();
        let accounts = AccountManager.getActiveAccounts().map({ $0.name.stringValue });
        for account in accounts.sorted() {
            accountSelection.addItem(withTitle: account);
        }
        
        accountSelection.target = self;
        accountSelection.action = #selector(accountSelectionChanged(_:));
        
        if let defAccount = AccountManager.defaultAccount, let idx = accounts.firstIndex(of: defAccount.stringValue) {
            accountSelection.selectItem(at: idx);
        } else if !accounts.isEmpty {
            accountSelection.selectItem(at: 0);
        }
                        
        $meetComponents.combineLatest(contactSelectionView.$items, { (components, items) in (!components.isEmpty) && !items.isEmpty }).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] available in
            self?.createAndInviteButton.isEnabled = available;
        }).store(in: &cancellables);
        
        $operationInProgress.map({ !$0 }).receive(on: DispatchQueue.main).assign(to: \.isEnabled, on: accountSelection).store(in: &cancellables);
        $operationInProgress.removeDuplicates().receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] inProgress in
            if inProgress {
                self?.progressIndicator.startAnimation(nil);
            } else {
                self?.progressIndicator.stopAnimation(nil);
            }
        }).store(in: &cancellables);
        
        accountSelectionChanged(self);
    }
    
    @objc func accountSelectionChanged(_ sender: Any) {
        client = XmppService.instance.getClient(for: BareJID(accountSelection.title));
    }
    
    @IBAction func createAndInviteClicked(_ sender: NSButton) {
        let participants = contactSelectionView.items.map({ $0.jid });
        guard let meetComponentJid = meetComponents.first?.jid, let client = self.client, !participants.isEmpty else {
            return;
        }
        self.operationInProgress = true;
        client.module(.meet).createMeet(at: meetComponentJid, media: [.audio,.video], participants: participants, completionHandler: { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let meetJid):
                    MeetManager.instance.registerMeet(at: meetJid, using: client)?.join();
                    for jid in participants {
                        client.module(.meet).sendMessageInitiation(action: .propose(id: UUID().uuidString, meetJid: meetJid, media: [.audio,.video]), to: JID(jid));
                    }
                    self.close();
                case .failure(let error):
                    let alert = NSAlert();
                    alert.alertStyle = .warning;
                    alert.messageText = NSLocalizedString("Meeting creation failed", comment: "create meet controller");
                    alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("It was not possible to create a meeting. Received an error: %@", comment: "create meet controller"), error.description);
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                        // nothing to do except closing..
                        self.close();
                    });
                }
            }
            self.operationInProgress = false;
        });
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }
 
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }

}

