//
// SelectAdHocCommandController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import Martin

class SelectAdHocCommandController: NSViewController {
    
    @IBOutlet var commendSelector: NSPopUpButton!;
    @IBOutlet var executeButton: NSButton!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    
    var account: BareJID!;
    var jid: JID!;
    
    var items: [DiscoveryModule.Item] = [] {
        didSet {
            commendSelector.removeAllItems();
            items.forEach { item in
                commendSelector.addItem(withTitle: item.name ?? item.node ?? item.jid.description);
            }
            executeButton.isEnabled = !items.isEmpty;
        }
    }
    
    override func viewWillAppear() {
        executeButton.isEnabled = false;
        commendSelector.removeAllItems();
        guard let discoveryModule = XmppService.instance.getClient(for: account)?.module(.disco) else {
            return;
        }
        
        self.progressIndicator.startAnimation(self);
        Task {
            if let items = try? await discoveryModule.items(for: jid!, node: "http://jabber.org/protocol/commands") {
                await MainActor.run(body: {
                    self.items = items.items.sorted(by: { (i1, i2) -> Bool in
                        let s1 = i1.name ?? i1.node ?? i1.jid.description;
                        let s2 = i2.name ?? i2.node ?? i2.jid.description;
                        return (s1).compare(s2) == .orderedAscending;
                    });
                })
            }
            await MainActor.run(body: {
                self.progressIndicator.stopAnimation(self);
            })
        }
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.view.window?.close();
    }
    
    @IBAction func executeClicked(_ sender: NSButton) {
        let item = items[commendSelector.indexOfSelectedItem];
        
        guard let windowController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("ExecuteAdhocWindowController")) as? NSWindowController, let viewController = windowController.contentViewController as? ExecuteAdHocCommandController else {
            return;
        }
        
        viewController.account = self.account;
        viewController.jid = item.jid;
        viewController.commandId = item.node ?? "";
        
        self.view.window?.beginSheet(windowController.window!, completionHandler: { (result) in
            self.view.window?.close();
        })
    }
    
}
