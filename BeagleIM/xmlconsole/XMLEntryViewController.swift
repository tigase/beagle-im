//
// XMLEntryViewController.swift
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
import TigaseSwift

class XMLEntryViewController: NSViewController, NSTextViewDelegate {
    
    @IBOutlet var xmlInput: NSTextView!
    @IBOutlet var sendButton: NSButton!
    
    var account: BareJID!;
    
    override func viewDidLoad() {
        self.xmlInput.delegate = self;
        self.xmlInput.isAutomaticQuoteSubstitutionEnabled = false;
    }
    
    func textDidChange(_ notification: Notification) {
        if let str = self.xmlInput.textStorage?.string {
            sendButton.isEnabled = !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty;
            return;
        }
        sendButton.isEnabled = false;
    }
    
    @IBAction func sendClicked(_ sender: Any) {
        guard let xml = xmlInput.textStorage?.string, !xml.isEmpty else {
            return;
        }
        
        class Holder: XMPPStreamDelegate {
            var parsed: [Element] = [];
            var isError: Bool = false;
            fileprivate func onError(msg: String?) {
                isError = true;
            }
            fileprivate func onStreamStart(attributes: [String : String]) {
            }
            fileprivate func onStreamTerminate() {
            }
            fileprivate func process(element packet: Element) {
                parsed.append(packet);
            }
        }
        
        let holder = Holder();
        let xmlDelegate = XMPPParserDelegate();
        xmlDelegate.delegate = holder;
        let parser = XMLParser(delegate: xmlDelegate);
        let data = xml.data(using: String.Encoding.utf8);
        try? parser.parse(data: data!);
        
        guard !holder.parsed.isEmpty && !holder.isError else {
            let alert = Alert();
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.messageText = "Error";
            alert.informativeText = "You have entered invalid XML. It is impossible to send invalid XML as it violates XMPP protocol specification!";
            alert.addButton(withTitle: "OK")
            alert.run { (response) in
            }
            return;
        }
        
        for elem in holder.parsed {
            let stanza = Stanza.from(element: elem);
            XmppService.instance.getClient(for: account)?.context.writer?.write(stanza);
        }
        self.view.window?.close();
    }
    
    @IBAction func cancelClicked(_ sender: Any) {
        self.view.window?.close();
    }
}
