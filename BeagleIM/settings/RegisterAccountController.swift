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
    fileprivate var task: InBandRegistrationModule.AccountRegistrationTask?;
    
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
            
            submitButton?.isEnabled = false;
            progressIndicator?.startAnimation(self);
            retrieveRegistrationForm(domain: domainField.stringValue, completion: { form, bob in
                self.form?.xmppClient = self.task?.client;
                self.form?.jid = JID(self.domainField.stringValue);
                self.submitButton?.isEnabled = true;
                self.progressIndicator?.stopAnimation(self);
                self.form?.bob = bob;
                self.form?.form = form;
                self.formHeightConstraint?.isActive = true;
                self.domainFieldHeightConstraint?.isActive = true;
            });
            return
        }
        
        if let form = self.form {
            form.synchronize();
            account = BareJID(localPart: (form.form!.getField(named: "username") as? TextSingleField)?.value, domain: domainField.stringValue);
            password = (form.form!.getField(named: "password") as? TextPrivateField)?.value;
            task?.submit(form: form.form!);
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
    
    fileprivate func saveAccount(acceptedCertificate: SslCertificateInfo?) {
        var account = AccountManager.Account(name: self.account!);
        account.password = password;
        if acceptedCertificate != nil {
            account.serverCertificate = ServerCertificateInfo(sslCertificateInfo: acceptedCertificate!, accepted: true);
        }
        
        do {
            try AccountManager.save(account: account);
            dismissView();
        } catch {
            let alert = NSAlert(error: error);
            alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
        }
    }
    
    fileprivate func onRegistrationError(errorCondition: ErrorCondition?, message: String?) {
        DispatchQueue.main.async {
            self.submitButton?.isEnabled = true;
            self.progressIndicator?.stopAnimation(self);
        }

        var msg = message;

        if errorCondition == nil {
            msg = NSLocalizedString("Server did not respond on registration request", comment: "register account error");
        } else {
            if msg == nil || msg == "Unsuccessful registration attempt" {
                switch errorCondition! {
                case .feature_not_implemented:
                    msg = NSLocalizedString("Registration is not supported by this server", comment: "register account error");
                case .not_acceptable, .not_allowed:
                    msg = NSLocalizedString("Provided values are not acceptable", comment: "register account error");
                case .conflict:
                    msg = NSLocalizedString("User with provided username already exists", comment: "register account error");
                case .service_unavailable:
                    msg = NSLocalizedString("Service is not available at this time.", comment: "register account error")
                default:
                    msg = String.localizedStringWithFormat(NSLocalizedString("Server returned error: %@", comment: "register account error"), errorCondition!.rawValue);
                }
            }
        }
        
        DispatchQueue.main.async {
            let alert = NSAlert();
            alert.messageText = NSLocalizedString("Registration failed!", comment: "register account error");
            alert.informativeText = msg!;
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
            alert.beginSheetModal(for: self.view.window!) { (response) in
                if errorCondition == ErrorCondition.feature_not_implemented || errorCondition == ErrorCondition.service_unavailable {
                    self.dismissView();
                }
            }
        }
    }
    
    fileprivate func onCertificateError(certData: SslCertificateInfo, accepted: @escaping ()->Void) {
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
    
    fileprivate func retrieveRegistrationForm(domain: String, completion: @escaping (JabberDataElement,[BobData])->Void) {
        let onForm = {(form: JabberDataElement, bob: [BobData], task: InBandRegistrationModule.AccountRegistrationTask)->Void in
            DispatchQueue.main.async {
                completion(form, bob);
            }
        };
        let client: XMPPClient? = nil;
        self.task = InBandRegistrationModule.AccountRegistrationTask(client: client, domainName: domain, onForm: onForm, sslCertificateValidator: nil, onCertificateValidationError: self.onCertificateError, completionHandler: { result in
            switch result {
            case .success:
                let certData: SslCertificateInfo? = self.task?.getAcceptedCertificate();
                DispatchQueue.main.async {
                    self.saveAccount(acceptedCertificate: certData);
                    self.dismissView();
                }
            case .failure(let error):
                self.onRegistrationError(errorCondition: error.errorCondition, message: error.message);
            }
        });
    }
}
