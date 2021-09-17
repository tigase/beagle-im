//
// ScriptsManager.swift
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

import Foundation
import TigaseSwift
import Carbon

class ScriptsManager {
    
    static let instance = ScriptsManager();
    
    let scriptsDirectory: URL?;
    
    fileprivate var _contactsScripts: [ContactScriptItem] = [];
    
    init() {
        scriptsDirectory = try? FileManager.default.url(for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: true);
        if let scriptsDirectory = self.scriptsDirectory, let contactScriptsUrls = try? FileManager.default.contentsOfDirectory(at: scriptsDirectory.appendingPathComponent("contact", isDirectory: true), includingPropertiesForKeys: [.localizedNameKey], options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]) {
            _contactsScripts = contactScriptsUrls.map({ (url) -> ContactScriptItem in
                return ContactScriptItem(url);
            }).sorted(by: { (i1, i2) -> Bool in
                return i1.name < i2.name;
            });
        }
    }
    
    func contactScripts() -> [ContactScriptItem]? {
        guard !_contactsScripts.isEmpty else {
            return nil;
        }
        
        return _contactsScripts;
    }
    
    class ScriptItem {
        let name: String;
        let url: URL;
        
        init(_ url: URL) {
            self.url = url;
            self.name = (try? url.resourceValues(forKeys: [.localizedNameKey]))?.localizedName ?? url.lastPathComponent;
        }
    }
    
    class ContactScriptItem: ScriptItem {
        
        func execute(account: BareJID, jid: JID) {
            if let task = try? NSUserAppleScriptTask(url: self.url) {
                let jidParam = NSAppleEventDescriptor(string: jid.stringValue);
                let params = NSAppleEventDescriptor(listDescriptor: ());
                params.insert(jidParam, at: 1);
                if let name = DBRosterStore.instance.item(for: account, jid: jid.withoutResource)?.name {
                    params.insert(NSAppleEventDescriptor(string: name), at: 2);
                } else {
                    params.insert(NSAppleEventDescriptor.null(), at: 2);
                }
                
                //var psn = ProcessSerialNumber(highLongOfPSN: UInt32(0), lowLongOfPSN: UInt32(kCurrentProcess))
                //let target = NSAppleEventDescriptor(descriptorType: DescType(typeProcessSerialNumber), bytes: &psn, length: MemoryLayout<ProcessSerialNumber>.size);
                let function = NSAppleEventDescriptor(string: "executeScript");
                
                let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent), targetDescriptor: NSAppleEventDescriptor.null(), returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID));
                event.setDescriptor(function, forKeyword: AEKeyword(keyASSubroutineName));
                event.setDescriptor(params, forKeyword: AEKeyword(keyDirectObject));
                task.execute(withAppleEvent: event) { (desc, error) in
                }
            }
            
        }
        
    }
}
