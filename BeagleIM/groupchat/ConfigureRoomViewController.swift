//
//  ConfigureRoomViewController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 22.09.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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

