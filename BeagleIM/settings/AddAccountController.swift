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

class PortValueFormatter: NumberFormatter, @unchecked Sendable {
    
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
    
    var accountValidatorTask: Task<Void,Never>?;
    
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
        let password = passwordField.stringValue;
        self.showProgressIndicator();
        var endpoint: SocketConnectorNetwork.Endpoint?;
        if !(hostField.stringValue.isEmpty || portField.stringValue.isEmpty), let port = Int(portField.stringValue) {
            endpoint = .init(proto: useDirectTLSCheck.state == .on ? .XMPPS : .XMPP, host: hostField.stringValue, port: port);
        }
        let settings = ConnectitivySettings(disableTls13: disableTLS13Check.state == .on, serverEndpoint: endpoint);
        self.accountValidatorTask = Task {
            do {
                let acceptedCertificate = try await AccountValidatorTask.validate(controller: self, account: jid, password: password, connectivitySettings: settings);
                await MainActor.run(body: {
                    guard !Task.isCancelled else {
                        return;
                    }
                    do {
                        // save account
                        try AccountManager.modifyAccount(for: jid, { account in
                            account.credentials = .password(password);
                            account.disableTLS13 = settings.disableTls13;
                            account.serverEndpoint = settings.serverEndpoint;
                        })
                        self.view.window?.sheetParent?.endSheet(self.view.window!);
                    } catch {
                        let alert = NSAlert(error: error);
                        alert.beginSheetModal(for: self.view.window!, completionHandler: nil);
                    }
                })
            } catch {
                await MainActor.run(body: {
                    self.hideProgressIndicator()
                    let alert = NSAlert();
                    alert.alertStyle = .critical;
                    alert.messageText = NSLocalizedString("Authentication failed", comment: "alert window title");
                    switch (error as? XMPPError)?.condition {
                    case .not_authorized:
                        alert.informativeText = NSLocalizedString("Login and password do not match.", comment: "alert window message");
                    default:
                        alert.informativeText = NSLocalizedString("It was not possible to contact XMPP server and sign in.", comment: "alert window message");
                    }
                    alert.beginSheetModal(for: self.view.window!, completionHandler: { _ in
                        // nothing to do.. just wait for user interaction
                    })
                })
            }
        }
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
    
    struct ConnectitivySettings {
        var disableTls13: Bool = false
        var serverEndpoint: SocketConnectorNetwork.Endpoint? = nil
    }

    class AccountValidatorTask {
        
        public static func validate(controller: AddAccountController, account: BareJID, password: String, connectivitySettings: ConnectitivySettings) async throws -> SSLCertificateInfo? {
            let client = XMPPClient();
            _ = client.modulesManager.register(StreamFeaturesModule());
            _ = client.modulesManager.register(SaslModule());
            _ = client.modulesManager.register(AuthModule());
            _ = client.modulesManager.register(ResourceBinderModule());
            _ = client.modulesManager.register(SessionEstablishmentModule());
            
            client.connectionConfiguration.useSeeOtherHost = false;
            client.connectionConfiguration.userJid = account;
            client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                options.connectionDetails = connectivitySettings.serverEndpoint
                options.networkProcessorProviders.append(connectivitySettings.disableTls13 ? SSLProcessorProvider(supportedTlsVersions: TLSVersion.TLSv1_2...TLSVersion.TLSv1_2) : SSLProcessorProvider())
            });
            client.connectionConfiguration.credentials = .password(password);
            defer {
                Task {
                    try await client.disconnect();
                }
            }
            do {
                try await client.loginAndWait();
                return nil;
            } catch let error as XMPPClient.State.DisconnectionReason {
                print(error)
                guard case let .sslCertError(trust) = error else {
                    throw error;
                }
                let certData = SSLCertificateInfo(trust: trust)!;
                guard await showCertificateError(account: account, certData: certData, controller: controller) else {
                    throw error;
                }
                client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
                    options.networkProcessorProviders.append(SSLProcessorProvider());
                    options.sslCertificateValidation = .fingerprint(certData.subject.fingerprints.first!);
                });
                
                try await client.loginAndWait();
                return certData;
            }
        }
        
        static func showCertificateError(account: BareJID, certData: SSLCertificateInfo, controller: AddAccountController) async -> Bool {
            await withUnsafeContinuation { continuation in
                DispatchQueue.main.async {
                    let alert = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ServerCertificateErrorController") as! ServerCertificateErrorController;
                    _ = alert.view;
                    alert.account = account;
                    alert.certficateInfo = certData;
                    alert.completionHandler = { result in
                        continuation.resume(returning: result)
                    }
                    controller.presentAsSheet(alert);
                }
            }
        }
    }

}
