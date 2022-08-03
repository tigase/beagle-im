//
// AddAccountController.swift
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
import Combine

class PortValueFormatter: NumberFormatter {
    
    override func isPartialStringValid(_ partialString: String, newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
        if partialString.isEmpty {
            return true;
        }
        
        guard let value = UInt(partialString) else {
            return false;
        }
        return value < 65536;
    }
    
}

class AddAccountController: NSViewController, NSTextFieldDelegate {
    
    @IBOutlet var logInButton: NSButton!;
    @IBOutlet var registerButton: NSButton!;
    @IBOutlet var progressIndicator: NSProgressIndicator!;
    
    @IBOutlet var usernameField: NSTextField!;
    @IBOutlet var passwordField: NSSecureTextField!;
    
    @IBOutlet var hostField: NSTextField!;
    @IBOutlet var portField: NSTextField!;
    @IBOutlet var useDirectTLSCheck: NSButton!;
    @IBOutlet var disableTLS13Check: NSButton!;
    
    @IBOutlet var disclosureButton: NSButton!;
    @IBOutlet var showAdvConstraint: NSLayoutConstraint!;
    @IBOutlet var hideAdvConstraint: NSLayoutConstraint!;
    @IBOutlet var advGrid: NSGridView!;
    
    var accountValidatorTask: AccountValidatorTask?;
    
    override func viewWillAppear() {
        super.viewWillAppear();
        portField.formatter = PortValueFormatter();
        disclosureButton.refusesFirstResponder = false;
        showDisclosure(false);
        view.window?.recalculateKeyViewLoop();
    }
    
    @IBAction func disclosureChanged(_ sender: Any?) {
        showDisclosure(disclosureButton.state == .on);
    }
    
    func showDisclosure(_ value: Bool) {
        disclosureButton.state = value ? .on : .off;
        advGrid.isHidden = !value;
        if value {
            NSLayoutConstraint.activate([showAdvConstraint]);
        } else {
            NSLayoutConstraint.deactivate([showAdvConstraint]);
        }
        view.window?.recalculateKeyViewLoop();
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard disclosureButton.state == .off else {
            return false;
        }
        
        if commandSelector == #selector(NSResponder.insertNewline(_:)) || commandSelector == #selector(NSResponder.insertTab(_:)) {
            control.resignFirstResponder();

            var responder: NSResponder = usernameField;
            switch textView {
            case usernameField.currentEditor():
                responder = passwordField;
            case passwordField.currentEditor():
                responder = logInButton;
            default:
                return false;
            }

            if responder == logInButton {
                if logInButton.isEnabled {
                    if commandSelector == #selector(NSResponder.insertNewline(_:)), let action = logInButton.action, let target = logInButton.target {
                        _ = target.perform(action, with: logInButton);
                        return true;
                    }
                } else {
                    responder = disclosureButton;
                }
            }

            self.view.window?.makeFirstResponder(responder);
            return true;
        }
        return false;
    }
    
    func controlTextDidChange(_ obj: Notification) {
        let hasCredentials = !(usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || passwordField.stringValue.isEmpty);
        let canConnect = hostField.stringValue.isEmpty == portField.stringValue.isEmpty;
        logInButton.isEnabled = hasCredentials && canConnect;
        useDirectTLSCheck.isEnabled = !(portField.stringValue.isEmpty || hostField.stringValue.isEmpty);
    }
    
    @IBAction func cancelClicked(_ button: NSButton) {
        self.view.window?.sheetParent?.endSheet(self.view.window!)
    }
    
    @IBAction func logInClicked(_ button: NSButton) {
        let jid = BareJID(usernameField.stringValue);
        var account = AccountManager.Account(name: jid);
        account.password = passwordField.stringValue;
        self.showProgressIndicator();
        self.accountValidatorTask = AccountValidatorTask(controller: self);
        var endpoint: SocketConnectorNetwork.Endpoint?;
        if !(hostField.stringValue.isEmpty || portField.stringValue.isEmpty), let port = Int(portField.stringValue) {
            endpoint = .init(proto: useDirectTLSCheck.state == .on ? .XMPPS : .XMPP, host: hostField.stringValue, port: port);
        }
        account.endpoint = endpoint;
        account.disableTLS13 = disableTLS13Check.state == .on;
        self.accountValidatorTask?.check(account: account.name, password: account.password!, endpoint: endpoint, disableTLS13: disableTLS13Check.state == .on, callback: { result in
            let certificateInfo = self.accountValidatorTask?.acceptedCertificate;
            DispatchQueue.main.async {
                self.accountValidatorTask?.finish();
                self.accountValidatorTask = nil;
                self.hideProgressIndicator();
                switch result {
                case .success(_):
                    if let certInfo = certificateInfo {
                        account.serverCertificate = ServerCertificateInfo(sslCertificateInfo: certInfo, accepted: true);
                    }
                    
                    do {
                        try AccountManager.save(account: account);
                        self.view.window?.sheetParent?.endSheet(self.view.window!);
                    } catch {
                        let alert = NSAlert(error: error);
                        alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    }
                case .failure(let error):
                    let alert = NSAlert();
                    alert.alertStyle = .critical;
                    alert.messageText = NSLocalizedString("Authentication failed", comment: "alert window title");
                    switch error {
                    case .not_authorized:
                        alert.informativeText = NSLocalizedString("Login and password do not match.", comment: "alert window message");
                    default:
                        alert.informativeText = NSLocalizedString("It was not possible to contact XMPP server and sign in.", comment: "alert window message");
                    }
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { _ in
                        // nothing to do.. just wait for user interaction
                    })
                    break;
                }
            }
        })
    }
    
    private func showProgressIndicator() {
        self.registerButton.isEnabled = false;
        self.logInButton.isEnabled = false;
        progressIndicator.startAnimation(self);
    }
    
    private func hideProgressIndicator() {
        self.logInButton.isEnabled = true;
        self.registerButton.isEnabled = true;
        progressIndicator.stopAnimation(self);
    }
    
    @IBAction func registerClicked(_ button: NSButton) {
        guard let registerAccountController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("RegisterAccountController")) as? RegisterAccountController else {
            self.view.window?.sheetParent?.endSheet(self.view.window!);
            return;
        }
        
        let window = NSWindow(contentViewController: registerAccountController);
        self.view.window?.beginSheet(window, completionHandler: { (reponse) in
            self.view.window?.sheetParent?.endSheet(self.view.window!);
        })
    }

    class AccountValidatorTask: EventHandler {
        
        private var cancellable: AnyCancellable?;
        var client: XMPPClient? {
            willSet {
                if newValue != nil {
                    newValue?.eventBus.register(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
                }
            }
            didSet {
                if oldValue != nil {
                    _ = oldValue?.disconnect(true);
                    oldValue?.eventBus.unregister(handler: self, for: SaslModule.SaslAuthSuccessEvent.TYPE, SaslModule.SaslAuthFailedEvent.TYPE);
                }
                cancellable = client?.$state.sink(receiveValue: { [weak self] state in self?.changedState(state) });
            }
        }
        
        var callback: ((Result<Void,ErrorCondition>)->Void)? = nil;
        weak var controller: AddAccountController?;
        var dispatchQueue = DispatchQueue(label: "accountValidatorSync");
        
        var acceptedCertificate: SslCertificateInfo? = nil;
        
        init(controller: AddAccountController) {
            self.controller = controller;
            initClient();
        }
        
        fileprivate func initClient() {
            self.client = XMPPClient();
            _ = client?.modulesManager.register(StreamFeaturesModule());
            _ = client?.modulesManager.register(SaslModule());
            _ = client?.modulesManager.register(AuthModule());
        }
        
        public func check(account: BareJID, password: String, endpoint: SocketConnectorNetwork.Endpoint?, disableTLS13: Bool, callback: @escaping (Result<Void,ErrorCondition>)->Void) {
            self.callback = callback;
            client?.connectionConfiguration.useSeeOtherHost = false;
            client?.connectionConfiguration.userJid = account;
            client?.connectionConfiguration.credentials = .password(password: password, authenticationName: nil, cache: nil);
            client?.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                if let endpoint = endpoint {
                    options.connectionDetails = endpoint;
                }
                options.networkProcessorProviders.append(disableTLS13 ? SSLProcessorProvider(supportedTlsVersions: TLSVersion.TLSv1_2...TLSVersion.TLSv1_2) : SSLProcessorProvider());
            })
            client?.login();
        }
        
        public func handle(event: Event) {
            dispatchQueue.sync {
                guard let callback = self.callback else {
                    return;
                }
                var param: ErrorCondition? = nil;
                switch event {
                case is SaslModule.SaslAuthSuccessEvent:
                    param = nil;
                case is SaslModule.SaslAuthFailedEvent:
                    param = ErrorCondition.not_authorized;
                default:
                    param = ErrorCondition.service_unavailable;
                }
                
                DispatchQueue.main.async {
                    if let error = param {
                        callback(.failure(error));
                    } else {
                        callback(.success(Void()));
                    }
                }
                self.finish();
            }
        }
        
        func changedState(_ state: XMPPClient.State) {
            dispatchQueue.sync {
                guard let callback = self.callback else {
                    return;
                }

                switch state {
                case .disconnected(let reason):
                    switch reason {
                    case .sslCertError(let trust):
                        self.callback = nil;
                        let certData = SslCertificateInfo(trust: trust);
                        DispatchQueue.main.async {
                            let alert = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ServerCertificateErrorController") as! ServerCertificateErrorController;
                            _ = alert.view;
                            alert.account = self.client?.sessionObject.userBareJid;
                            alert.certficateInfo = certData;
                            alert.completionHandler = { accepted in
                                self.acceptedCertificate = certData;
                                if (accepted) {
                                    self.client?.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                                        options.networkProcessorProviders.append(SSLProcessorProvider());
                                        options.sslCertificateValidation = .fingerprint(certData.details.fingerprintSha1);
                                    });
                                    self.callback = callback;
                                    self.client?.login();
                                } else {
                                    self.finish();
                                    DispatchQueue.main.async {
                                        callback(.failure(.service_unavailable));
                                    }
                                }
                            };
                            self.controller?.presentAsSheet(alert);
                        }
                        return;
                    default:
                        break;
                    }
                    DispatchQueue.main.async {
                        callback(.failure(.service_unavailable));
                    }
                    self.finish();
                default:
                    break;
                }
            }
        }
        
        public func finish() {
            self.callback = nil;
            self.client = nil;
            self.controller = nil;
        }
    }
}
