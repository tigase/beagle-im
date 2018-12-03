//
// ServerCertificateErrorController.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import AppKit
import TigaseSwift

class ServerCertificateErrorController: NSViewController {
    
    @IBOutlet var message: NSTextField!;
    @IBOutlet var certificateName: NSTextField!;
    @IBOutlet var certificateFingerprint: NSTextField!;
    @IBOutlet var issuerName: NSTextField!;
    @IBOutlet var issuesFingerprint: NSTextField!;

    var completionHandler: ((Bool)->Void)?;
    
    var account: BareJID? {
        didSet {
            guard let domain = account?.domain else {
                return;
            }
            message.stringValue = "It is not possible to automatically verify server certificate for \(domain). Please review certificate details:"
            self.certficateInfo = AccountManager.getAccount(for: account!)?.serverCertificate;
        }
    }
    var certficateInfo: SslCertificateInfo? {
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
        if let handler = completionHandler {
            completionHandler = nil;
            handler(false);
        }
    }
    
    @IBAction func acceptCliecked(_ sender: NSButton) {
        self.view.window?.close();

        if let handler = completionHandler {
            completionHandler = nil;
            handler(true);
        } else {
            let jid = account!;
            guard let account = AccountManager.getAccount(for: jid) else {
                return;
            }
            account.serverCertificate?.accepted = true;
            account.active = true;
            _ = AccountManager.save(account: account);
        }
    }
}
