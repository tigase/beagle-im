//
// ConfigureRoomViewController.swift
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

class ConfigureRoomViewController: NSViewController {
 
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    var account: BareJID!;
    var mucComponent: BareJID!;
    var roomJid: BareJID?;
    
    @IBOutlet var formView: JabberDataFormView!;
    @IBOutlet var scrollView: NSScrollView!;
    
    var form: JabberDataElement? {
        didSet {
            formView.form = form;
        }
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        
        guard let mucModule: MucModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MucModule.ID) else {
            return;
        }
        
        progressIndicator.startAnimation(nil);
        mucModule.getRoomConfiguration(roomJid: JID(roomJid == nil ? mucComponent : roomJid!), onSuccess: { (form) in
            DispatchQueue.main.async {
                self.form = form;
                self.progressIndicator.stopAnimation(nil);
                DispatchQueue.main.async {
                    self.scrollView.contentView.scroll(to: NSPoint(x: 0, y: self.scrollView.documentView!.frame.size.height - self.scrollView.contentSize.height));
                }
            }
        }, onError: { errorCondition in
            // need to show alert here!
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil);
                let alert = NSAlert();
                alert.messageText = "Error occurred";
                alert.icon = NSImage(named: NSImage.cautionName);
                alert.informativeText = "Could not retrieve room configuration from the server. Got following error: \(errorCondition?.rawValue ?? "timeout")";
                alert.addButton(withTitle: "OK");
                alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
                    self.close(result: .cancel);
                });
            }
        });
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.close(result: .cancel);
    }
    
    @IBAction func acceptClicked(_ sender: NSButton) {
        guard form != nil else {
            return;
        }
        
        formView.synchronize();
        
        guard let mucModule: MucModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(MucModule.ID) else {
            return;
        }
        
        progressIndicator.stopAnimation(nil);
        mucModule.setRoomConfiguration(roomJid: JID(roomJid!), configuration: form!, onSuccess: {
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil);
                self.close();
            }
        }) { (errorCondition) in
            DispatchQueue.main.async {
                self.progressIndicator.stopAnimation(nil);
                let alert = NSAlert();
                alert.messageText = "Error occurred";
                alert.icon = NSImage(named: NSImage.cautionName);
                alert.informativeText = "Could not apply room configuration on the server. Got following error: \(errorCondition?.rawValue ?? "timeout")";
                alert.addButton(withTitle: "OK");
                alert.beginSheetModal(for: self.view.window!, completionHandler: { result in
                    self.close(result: .cancel);
                });
            }
        }
    }
    
    fileprivate func close(result: NSApplication.ModalResponse = .OK) {
        self.view.window?.sheetParent?.endSheet(self.view.window!, returnCode: result);
    }
    
}

