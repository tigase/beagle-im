//
// NetworkSettingsController.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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

class NetworkSettingsController: NSViewController {
    
    @IBOutlet var turnServerField: NSTextField!

    @IBOutlet var usernameTextField: NSTextField!
    @IBOutlet var passwordTextField: NSTextField!
    @IBOutlet var forceRelayCheckbox: NSButton!
    
    override func viewWillAppear() {
        if var urlComponents = URLComponents(string: Settings.turnServer.string() ?? "") {
            usernameTextField.stringValue = urlComponents.user ?? "";
            passwordTextField.stringValue = urlComponents.password ?? "";
            urlComponents.user = nil;
            urlComponents.password = nil;
            var server = "";
            if let scheme = urlComponents.scheme, let host = urlComponents.host {
                server = "\(scheme):\(host)";
                if let port = urlComponents.port {
                    server = "\(server):\(port)";
                }
            }
            turnServerField.stringValue = server;
            forceRelayCheckbox.state = urlComponents.queryItems?.filter({ item in
                item.name == "forceRelay" && item.value == "true"
                }) != nil ? .on : .off;
        }
    }
    
    override func viewWillDisappear() {
        let parts = turnServerField.stringValue.split(separator: ":");
        if parts.count >= 2 {
            var urlComponents = URLComponents();
            urlComponents.scheme = String(parts[0]);
            urlComponents.host = String(parts[1]);
            if parts.count > 2 {
                urlComponents.port = Int(String(parts[2]));
            }
            if forceRelayCheckbox.state == .on {
                urlComponents.queryItems = [URLQueryItem(name: "forceRelay", value: "true")]
            }
            print("url:", urlComponents.string as Any, "parts:", urlComponents)
            urlComponents.user = usernameTextField.stringValue.isEmpty ? nil :  usernameTextField.stringValue;
            urlComponents.password = passwordTextField.stringValue.isEmpty ? nil : passwordTextField.stringValue;
            print("url:", urlComponents.string as Any, "parts:", urlComponents)
            Settings.turnServer.set(value: urlComponents.string);
        }
    }
    
}
