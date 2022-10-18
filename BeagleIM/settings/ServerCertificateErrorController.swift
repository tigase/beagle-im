//
// ServerCertificateErrorController.swift
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
import Martin

class ServerCertificateErrorController: NSViewController {
    
    @IBOutlet var windowTitle: NSTextField!
    @IBOutlet var message: NSTextField!;
    @IBOutlet var certificateName: NSTextField!;
    @IBOutlet var certificateValidPeriod: NSTextField!;
    @IBOutlet var certificateFingerprint: NSTextField!;
    @IBOutlet var issuerName: NSTextField!;
    @IBOutlet var issuesFingerprint: NSTextField!;

    let dateFormatter: DateFormatter = {
        let formatter = DateFormatter();
        formatter.dateStyle = .medium;
        formatter.timeStyle = .short;
        return formatter;
    }();
    
    var completionHandler: ((Bool)->Void)?;
    
    var account: BareJID? {
        didSet {
            guard let domain = account?.domain else {
                return;
            }
            windowTitle.stringValue = String.localizedStringWithFormat(NSLocalizedString("SSL certificate of %@ could not be verified", comment: "setting"), domain);
            message.stringValue = String.localizedStringWithFormat(NSLocalizedString("It is not possible to automatically verify server certificate for %@. Please review certificate details:", comment: "setting"), domain);
            self.certficateInfo = AccountManager.account(for: account!)?.acceptedCertificate?.certificate;
        }
    }
    var certficateInfo: SSLCertificateInfo? {
        didSet {
            guard let info = certficateInfo else {
                return;
            }
            certificateName.stringValue = info.subject.name;
            if info.subject.notBefore != nil && info.subject.notAfter != nil {
                let color: NSColor = ((Date() > info.subject.notAfter!) ? NSColor.systemRed : NSColor.textColor);
                certificateValidPeriod.attributedStringValue = NSAttributedString(string: String.localizedStringWithFormat(NSLocalizedString("From %@ until %@", comment: "setting"), dateFormatter.string(for: info.subject.notBefore!)!, dateFormatter.string(for: info.subject.notAfter!)!), attributes: [.foregroundColor: color]);
            } else {
                certificateValidPeriod.attributedStringValue = NSAttributedString(string: NSLocalizedString("Unknown", comment: "setting"), attributes: [.foregroundColor: NSColor.systemOrange]);
            }
            certificateFingerprint.stringValue = info.subject.fingerprints.first?.value ?? "Unknown";//.fingerprintSha1;
            issuerName.stringValue = info.issuer?.name ?? NSLocalizedString("Self-Signed", comment: "setting");
            issuesFingerprint.stringValue = info.issuer?.fingerprints.first?.value ?? "Unknown";
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
            guard let jid = self.account else {
                return;
            }
            
            try? AccountManager.modifyAccount(for: jid, { account in
                if let cert = account.acceptedCertificate?.certificate {
                    account.acceptedCertificate = AcceptableServerCertificate(certificate: cert, accepted: true);
                }
                account.enabled = true;
            })
        }
    }
}
