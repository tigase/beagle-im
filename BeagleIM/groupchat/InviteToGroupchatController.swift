//
// InviteToGroupchatController.swift
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

class InviteToGroupchatController: NSViewController, NSTextFieldDelegate {
    
    @IBOutlet var contactSelectionView: MultiContactSelectionView!;
    
    var room: Room!;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        contactSelectionView.closedSuggestionsList = false;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let editor = obj.userInfo?["NSFieldEditor"] as? NSText {
            editor.complete(nil);
        }
    }
    
    @IBAction func inviteClicked(_ sender: NSButton) {
        let jids = contactSelectionView.items.map({ JID($0.jid)});
        
        for jid in jids {
            room.invite(jid, reason: nil)
        }
        close();
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }
 
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }

}
