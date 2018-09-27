//
//  ServerCertificateErrorController.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 26/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ServerCertificateErrorController: NSViewController {
    
    @IBOutlet var message: NSTextField!;
    @IBOutlet var certificateName: NSTextField!;
    @IBOutlet var certificateFingerprint: NSTextField!;
    @IBOutlet var issuerName: NSTextField!;
    @IBOutlet var issuesFingerprint: NSTextField!;

    var account: BareJID? {
        didSet {
            guard let domain = account?.domain else {
                return;
            }
            message.stringValue = "It is not possible to automatically verify server certificate for \(domain). Please review certificate details:"
            self.certficateInfo = AccountManager.getAccount(for: account!)?.serverCertificate;
        }
    }
    var certficateInfo: ServerCertificateInfo? {
        didSet {
            guard let info = certficateInfo else {
                return;
            }
            certificateName.stringValue = info.details.name;
            certificateFingerprint.stringValue = info.details.fingerprintSha1;
            issuerName.stringValue = info.issuer?.name ?? "Self-Signed";
            issuesFingerprint.stringValue = info.issuer?.fingerprintSha1 ?? "";
        }
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        self.view.window?.close();
    }
    
    @IBAction func acceptCliecked(_ sender: NSButton) {
        let jid = account!;
        self.view.window?.close();
        
        guard let account = AccountManager.getAccount(for: jid) else {
            return;
        }
        account.serverCertificate?.accepted = true;
        account.active = true;
        _ = AccountManager.save(account: account);
    }
}
