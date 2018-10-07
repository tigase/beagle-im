//
//  InviteToGroupchatController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 07/10/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class InviteToGroupchatController: NSViewController, NSTextFieldDelegate {
    
    @IBOutlet var contactsField: NSTextField!;
    
    var room: Room!;
    var allRosterItems: [RosterItem] = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        contactsField.delegate = self;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.allRosterItems = XmppService.instance.clients.values.flatMap { (client) -> [RosterItem] in
            (client.rosterStore as? DBRosterStoreWrapper)?.getAll() ?? [];
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let editor = obj.userInfo?["NSFieldEditor"] as? NSText {
            editor.complete(nil);
        }
    }
    
    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        let tmp = textView.string;
        let start = tmp.index(tmp.startIndex, offsetBy: charRange.lowerBound);
        let end = tmp.index(tmp.startIndex, offsetBy: charRange.upperBound);
        let query = textView.string[start..<end];
        index.initialize(to: -1);
        
        let suggestions = self.allRosterItems.filter { (item) -> Bool in
            if item.name?.contains(query) ?? false {
                return true;
            }
            return item.jid.stringValue.contains(query);
        }.map { (item) -> String in
            guard let name = item.name else {
                return item.jid.stringValue;
            }
            return "\(name) <\(item.jid.stringValue)>";
            }.sorted { (s1, s2) -> Bool in
                return s1.caseInsensitiveCompare(s2) == .orderedAscending;
        };
        return suggestions;
    }
    
    @IBAction func inviteClicked(_ sender: NSButton) {
        let jids = contactsField.stringValue.split(separator: ",").map { (str) -> String? in
            guard let start = str.firstIndex(of: "<"), let end = str.firstIndex(of: ">") else {
                return str.contains(">") || str.contains("<") ? nil : str.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines);
            }
            return String(str[str.index(after: start)..<end].trimmingCharacters(in: CharacterSet.whitespacesAndNewlines));
            }.map { (str) -> JID? in
                return JID(str);
            }.filter { (jid) -> Bool in
                return jid != nil
            }.map { jid -> JID in
                return jid!;
        }
        
        jids.forEach { jid in
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
