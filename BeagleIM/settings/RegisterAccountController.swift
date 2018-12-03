//
// RegisterAccountController.swift
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

class RegisterAccountController: NSViewController, NSTextFieldDelegate {
 
    @IBOutlet var domainField: NSTextField!;
    @IBOutlet var progressIndicator: NSProgressIndicator?;
    @IBOutlet var form: JabberDataFormView?;
    
    @IBOutlet var cancelButton: NSButton?;
    @IBOutlet var submitButton: NSButton?;
    
    fileprivate var trustedServers = ["sure.im", "tigase.im", "jabber.me"];
    
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
            retrieveRegistrationForm(domain: domainField.stringValue, completion: { form in
                self.submitButton?.isEnabled = true;
                self.progressIndicator?.stopAnimation(self);
                self.form?.form = form;
                self.formHeightConstraint?.isActive = form == nil;
                self.domainFieldHeightConstraint?.isActive = form != nil;
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
        let account = AccountManager.Account(name: self.account!);
        account.password = password;
        if acceptedCertificate != nil {
            account.serverCertificate = ServerCertificateInfo(sslCertificateInfo: acceptedCertificate!, accepted: true);
        }
        _ = AccountManager.save(account: account);
        dismissView();
    }
    
    fileprivate func onRegistrationError(errorCondition: ErrorCondition?, message: String?) {
        DispatchQueue.main.async {
            self.submitButton?.isEnabled = true;
            self.progressIndicator?.stopAnimation(self);
        }

        print("account registration failed", errorCondition?.rawValue ?? "nil", "with message =", message as Any);
        var msg = message;

        if errorCondition == nil {
            msg = "Server did not respond on registration request";
        } else {
            if msg == nil || msg == "Unsuccessful registration attempt" {
                switch errorCondition! {
                case .feature_not_implemented:
                    msg = "Registration is not supported by this server";
                case .not_acceptable, .not_allowed:
                    msg = "Provided values are not acceptable";
                case .conflict:
                    msg = "User with provided username already exists";
                case .service_unavailable:
                    msg = "Service is not available at this time."
                default:
                    msg = "Server returned error: \(errorCondition!.rawValue)";
                }
            }
        }
        
        DispatchQueue.main.async {
            let alert = NSAlert();
            alert.messageText = "Registration failed!";
            alert.informativeText = msg!;
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.addButton(withTitle: "OK");
            alert.beginSheetModal(for: self.view.window!) { (response) in
                print("error dismissed");
                if errorCondition == ErrorCondition.feature_not_implemented || errorCondition == ErrorCondition.service_unavailable {
                    self.dismissView();
                }
            }
        }
    }
    
    fileprivate func onCertificateError(certData: SslCertificateInfo, accepted: @escaping ()->Void) {
        DispatchQueue.main.async {
            guard let controller = self.storyboard?.instantiateController(withIdentifier: "ServerCertificateErrorController") as? ServerCertificateErrorController else {
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
    
    fileprivate func retrieveRegistrationForm(domain: String, completion: @escaping (JabberDataElement?)->Void) {
        let onForm = {(form: JabberDataElement, task: InBandRegistrationModule.AccountRegistrationTask)->Void in
            DispatchQueue.main.async {
                completion(form);
            }
        };
        let onSuccess = {()->Void in
            print("account registered!");
            let certData: SslCertificateInfo? = self.task?.getAcceptedCertificate();
            DispatchQueue.main.async {
                self.saveAccount(acceptedCertificate: certData);
                self.dismissView();
            }
        };
        let client: XMPPClient? = nil;
        self.task = InBandRegistrationModule.AccountRegistrationTask(client: client, domainName: domain, onForm: onForm, onSuccess: onSuccess, onError: self.onRegistrationError, sslCertificateValidator: SslCertificateValidator.validateSslCertificate, onCertificateValidationError: self.onCertificateError);
    }
}
