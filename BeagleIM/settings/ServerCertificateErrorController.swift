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
import TigaseSwift

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
            windowTitle.stringValue = "SSL certificate of \(domain) could not be verified";
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
            if info.details.validFrom != nil && info.details.validTo != nil {
                let color: NSColor = ((Date() > info.details.validTo!) ? NSColor.systemRed : NSColor.textColor);
                certificateValidPeriod.attributedStringValue = NSAttributedString(string: "From \(dateFormatter.string(for: info.details.validFrom!)!) until \(dateFormatter.string(for: info.details.validTo!)!)", attributes: [.foregroundColor: color]);
            } else {
                certificateValidPeriod.attributedStringValue = NSAttributedString(string: "Unknown", attributes: [.foregroundColor: NSColor.systemOrange]);
            }
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
            guard let jid = self.account, let account = AccountManager.getAccount(for: jid) else {
                return;
            }
            account.serverCertificate?.accepted = true;
            account.active = true;
            _ = AccountManager.save(account: account);
        }
    }
}
