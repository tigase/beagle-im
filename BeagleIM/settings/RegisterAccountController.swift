//
// RegisterAccountController.swift
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

class RegisterAccountController: NSViewController, NSTextFieldDelegate {
 
    @IBOutlet var domainField: NSTextField!;
    @IBOutlet var progressIndicator: NSProgressIndicator?;
    @IBOutlet var form: JabberDataFormView?;
    
    @IBOutlet var cancelButton: NSButton?;
    @IBOutlet var submitButton: NSButton?;
    
    fileprivate var trustedServers = ["sure.im", "tigase.im", "jabber.today"];
    
    fileprivate var domainFieldHeightConstraint: NSLayoutConstraint?;
    fileprivate var formHeightConstraint: NSLayoutConstraint?;
    fileprivate var task: InBandRegistrationModule.AccountRegistrationAsyncTask?;
    
    fileprivate var account: BareJID?;
    fileprivate var password: String?;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        
        progressIndicator?.isDisplayedWhenStopped = false;
        formHeightConstraint = form?.heightAnchor.constraint(equalToConstant: 0);
        formHeightConstraint?.isActive = true;
        
        domainField.delegate = self;
        domainField.isAutomaticTextCompletionEnabled = true;
        domainFieldHeightConstraint = domainField.heightAnchor.constraint(equalToConstant: 0);
        domainField.target = self;
        domainField.action = #selector(submitClicked(_:));
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        dismissView();
    }
    
    @IBAction func submitClicked(_ sender: Any) {
        guard task != nil && form?.form != nil else {
            guard domainField.stringValue.count > 0 && (self.submitButton?.isEnabled ?? false) else {
                return;
            }
            
            retrieveRegistrationForm(domain: domainField.stringValue, acceptedCertificate: nil);
            return
        }
        
        if let form = self.form {
            form.synchronize();
            account = BareJID(localPart: form.form!.value(for: "username", type: String.self), domain: domainField.stringValue);
            password = form.form!.value(for: "password", type: String.self);
            Task {
                progressIndicator?.startAnimation(self);
                submitButton?.isEnabled = false;
                do {
                    try await task?.submit(form: form.form!);
                    await MainActor.run(body: {
                        self.saveAccount(acceptedCertificate: task?.acceptedSslCertificate);
                        self.dismissView();
                    })
                } catch {
                    self.onRegistrationError(error as? XMPPError ?? .undefined_condition);
                }
                await MainActor.run(body: {
                    progressIndicator?.stopAnimation(self);
                    submitButton?.isEnabled = true;
                })
            }
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
        if let editor = obj.userInfo?["NSFieldEditor"] as? NSText {
            editor.complete(nil);
        }
        submitButton?.isEnabled = domainField.stringValue.count > 0;
    }
    
    func control(_ control: NSControl, textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String] {
        index.initialize(to: -1);
        return trustedServers.filter({ item -> Bool in
            return item.contains(textView.string);
        });
    }
    
    fileprivate func dismissView() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }
    
    fileprivate func saveAccount(acceptedCertificate: SSLCertificateInfo?) {
        guard let jid = account else {
            return;
        }
        do {
            try AccountManager.modifyAccount(for: jid, { account in
                if let certInfo = acceptedCertificate {
                    account.acceptedCertificate = AcceptableServerCertificate(certificate: certInfo, accepted: true);
                } else {
                    account.acceptedCertificate = nil;
                }
                account.password = self.password!;
            })
            dismissView();
        } catch {
            let alert = NSAlert(error: error);
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
        }
    }
    
    fileprivate func onRegistrationError(_ error: XMPPError) {
        DispatchQueue.main.async {
            self.submitButton?.isEnabled = true;
            self.progressIndicator?.stopAnimation(self);
        }

        var msg = error.message;

        if msg == nil || msg == "Unsuccessful registration attempt" {
            switch error.condition {
            case .feature_not_implemented:
                msg = NSLocalizedString("Registration is not supported by this server", comment: "register account error");
            case .not_acceptable, .not_allowed:
                msg = NSLocalizedString("Provided values are not acceptable", comment: "register account error");
            case .conflict:
                msg = NSLocalizedString("User with provided username already exists", comment: "register account error");
            case .service_unavailable:
                msg = NSLocalizedString("Service is not available at this time.", comment: "register account error")
            default:
                msg = String.localizedStringWithFormat(NSLocalizedString("Server returned error: %@", comment: "register account error"), error.localizedDescription);
            }
        }
        
        DispatchQueue.main.async {
            let alert = NSAlert();
            alert.messageText = NSLocalizedString("Registration failed!", comment: "register account error");
            alert.informativeText = msg!;
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
            alert.beginSheetModal(for: self.view.window!) { (response) in
                if error.condition == ErrorCondition.feature_not_implemented || error.condition == ErrorCondition.service_unavailable {
                    self.dismissView();
                }
            }
        }
    }
    
    fileprivate func onCertificateError(certData: SSLCertificateInfo, accepted: @escaping ()->Void) {
        DispatchQueue.main.async {
            guard let controller = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ServerCertificateErrorController") as? ServerCertificateErrorController else {
                return;
            }
            
            let window = NSWindow(contentViewController: controller);
            controller.certficateInfo = certData;
            controller.completionHandler = { result in
                if result == true {
                    accepted();
                } else {
                    self.dismissView();
                }
            };
            self.view.window?.beginSheet(window, completionHandler: nil);
        }
    }
    
    fileprivate func retrieveRegistrationForm(domain: String, acceptedCertificate: SSLCertificateInfo?) {
        self.task = InBandRegistrationModule.AccountRegistrationAsyncTask(domainName: domain, preauth: nil);
        task?.acceptedSslCertificate = acceptedCertificate;

        submitButton?.isEnabled = false;
        progressIndicator?.startAnimation(self);

        Task {
            do {
                let result = try await task!.retrieveForm();
                await MainActor.run(body: {
                    self.form?.xmppClient = self.task?.client;
                    self.form?.jid = JID(self.domainField.stringValue);
                    self.submitButton?.isEnabled = true;
                    self.progressIndicator?.stopAnimation(self);
                    self.form?.bob = result.bob;
                    self.form?.form = result.form;
                    self.formHeightConstraint?.isActive = true;
                    self.domainFieldHeightConstraint?.isActive = true;
                })
            } catch XMPPClient.State.DisconnectionReason.sslCertError(let secTrust) {
                let info = SSLCertificateInfo(trust: secTrust)!;
                self.onCertificateError(certData: info, accepted: {
                    self.retrieveRegistrationForm(domain: domain, acceptedCertificate: info);
                })
            } catch {
                self.onRegistrationError(error as? XMPPError ?? .undefined_condition);
            }
            
            await MainActor.run(body: {
                self.submitButton?.isEnabled = true;
                self.progressIndicator?.stopAnimation(self);
            })
        }
    }
}
