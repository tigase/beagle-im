//
// XMLConsoleViewController.swift
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

class XMLConsoleViewController: NSViewController, StreamLogger {
    
    public static func configureLogging(for client: XMPPClient) {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { (window) -> Bool in
                (window.contentViewController as? XMLConsoleViewController)?.account == client.sessionObject.userBareJid!;
            }) else {
                client.streamLogger = nil;
                return;
            }
            client.streamLogger = window.contentViewController as? StreamLogger;
        }
    }
    
    public static func open(for account: BareJID) {
        guard let window = NSApp.windows.first(where: { (window) -> Bool in
            (window.contentViewController as? XMLConsoleViewController)?.account == account;
        }) else {
            guard let windowController = NSStoryboard(name: NSStoryboard.Name("XMLConsole"), bundle: nil).instantiateController(withIdentifier: "XMLConsoleWindowController") as? NSWindowController else {
                return;
            }
            
            guard let viewController = windowController.contentViewController as? XMLConsoleViewController else {
                return;
            }
            
            viewController.account = account;
            
            windowController.showWindow(self);
            return;
        }
        
        window.windowController?.showWindow(self);
    }
    
    fileprivate static let stampFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.locale = Locale(identifier: "en_US_POSIX");
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        f.timeZone = TimeZone(secondsFromGMT: 0);
        return f;
    })();
    
    @IBOutlet var logView: NSTextView!
    
    var account: BareJID!;
    
    override func viewWillAppear() {
        self.view.window?.title = "XML Console: \(account!)";
        
        XmppService.instance.getClient(for: account)?.streamLogger = self;
    }
    
    @objc func test() {
        let stanza = Message();
        stanza.body = "Some body \(UUID().uuidString)";
        let incoming = Bool.random();
        stanza.from = incoming ? JID("test1@example.com") : JID("test2@example.com");
        stanza.to = incoming ? JID("test2@example.com") : JID("test1@example.com");
        stanza.type = StanzaType.chat;
        self.add(timestamp: Date(), incoming: incoming, stanza: stanza);
    }
    
    @IBAction func clearClicked(_ sender: Any) {
        if let storage = self.logView.textStorage {
            storage.deleteCharacters(in: NSRange(location: 0, length: storage.length));
        }
    }
    
    @IBAction func closeClicked(_ sender: Any) {
        self.view.window?.close();
    }
    
    func incoming(_ value: StreamEvent) {
        DispatchQueue.main.async { [weak self] in
            switch value {
            case .stanza(let stanza):
                self?.add(timestamp: Date(), incoming: true, text: stanza.element.toPrettyString(secure: false));
            case .streamClose(_):
                self?.add(timestamp: Date(), incoming: true, text: "</stream:stream>");
            case .streamOpen(let attributes):
                let attributesString = attributes.map({ "\($0.key)='\($0.value)' "}).joined();
                let openString = "<stream:stream \(attributesString) version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>";
                self?.add(timestamp: Date(), incoming: true, text: openString);
            default:
                break;
            }
        }
    }

    func outgoing(_ value: StreamEvent) {
        DispatchQueue.main.async { [weak self] in
            switch value {
            case .stanza(let stanza):
                self?.add(timestamp: Date(), incoming: false, text: stanza.element.toPrettyString(secure: false));
            case .streamClose(_):
                self?.add(timestamp: Date(), incoming: false, text: "</stream:stream>");
            case .streamOpen(let attributes):
                let attributesString = attributes.map({ "\($0.key)='\($0.value)' "}).joined();
                let openString = "<stream:stream \(attributesString) version='1.0' xmlns='jabber:client' xmlns:stream='http://etherx.jabber.org/streams'>";
                self?.add(timestamp: Date(), incoming: false, text: openString);
            default:
                break;
            }
        }
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShowEnterXMLWindow" {
            if let controller = ((segue.destinationController as? NSWindowController)?.contentViewController as? XMLEntryViewController) {
                controller.account = self.account;
            }
        }
    }
    
    fileprivate func add(timestamp: Date, incoming: Bool, stanza: Stanza) {
        add(timestamp: timestamp, incoming: incoming, text: stanza.element.toPrettyString(secure: false));
    }
    
    fileprivate func add(timestamp: Date, incoming: Bool, text: String) {
        if let storage = self.logView.textStorage {
            let shouldScroll = logView.visibleRect.maxY == self.logView.bounds.maxY;
            let breakStr = storage.length == 0 ? "" : "\n\n";
            let str = NSMutableAttributedString(string: "\(breakStr)<!--   \(XMLConsoleViewController.stampFormatter.string(from: timestamp))   \(incoming ? "<<<<" : ">>>>")   -->\n", attributes: [NSAttributedString.Key.foregroundColor: NSColor.secondaryLabelColor ]);
//            let dark = (NSApp.appearance ?? NSAppearance.current)?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua;
            str.append(NSAttributedString(string: text, attributes: [.foregroundColor: incoming ? NSColor(calibratedHue: 240.0/360.0, saturation: 1.0, brightness: 0.70, alpha: 1.0) : NSColor(calibratedHue: 0, saturation: 1.0, brightness: 0.70, alpha: 1.0)]));
            str.addAttributes([.font : NSFont.systemFont(ofSize: NSFont.systemFontSize)], range: NSRange(location: 0, length: str.length));
            storage.append(str);
            if shouldScroll {
                logView.scrollToEndOfDocument(self);
            }
        }
    }
}
