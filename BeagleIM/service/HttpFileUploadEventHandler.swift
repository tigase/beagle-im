//
// HttpFileUploadEventHandler.swift
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

class HttpFileUploadEventHandler: XmppServiceEventHandler {
    
    static let UPLOAD_SUPPORT_CHANGED = Notification.Name("httpUploadSupportChanged");
    
    let events: [Event] = [ SocketConnector.DisconnectedEvent.TYPE, SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE ];
    
    func handle(event: Event) {
        switch event {
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            let account = e.sessionObject.userBareJid!;
            guard let uploadModule: HttpFileUploadModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(HttpFileUploadModule.ID) else {
                return;
            }
            uploadModule.findHttpUploadComponent(completionHandler: { result in
                switch result {
                case .success(let values):
                    uploadModule.availableComponents = values;
                    NotificationCenter.default.post(name: HttpFileUploadEventHandler.UPLOAD_SUPPORT_CHANGED, object: account);
                case .failure(let error):
                    print("an error occurred during HTTPFileUpload component discovery!", error);
                }
            });
        case let e as StreamManagementModule.ResumedEvent:
            let account = e.sessionObject.userBareJid!;
            NotificationCenter.default.post(name: HttpFileUploadEventHandler.UPLOAD_SUPPORT_CHANGED, object: account);
        case let e as SocketConnector.DisconnectedEvent:
            let account = e.sessionObject.userBareJid!;
//            if let uploadModule: HttpFileUploadModule = XmppService.instance.getClient(for: account)?.modulesManager.getModule(HttpFileUploadModule.ID) {
//                uploadModule.availableComponents = [];
//            }
            NotificationCenter.default.post(name: HttpFileUploadEventHandler.UPLOAD_SUPPORT_CHANGED, object: account);
        default:
            break;
        }
    }
    
}

extension HttpFileUploadModule {
    
    fileprivate static let COMPONENT_JIDS_KEY = "httpFileUploadJids";
    
    var availableComponents: [UploadComponent] {
        get {
            return context.sessionObject.getProperty(HttpFileUploadModule.COMPONENT_JIDS_KEY) ?? [];
        }
        set {
            context.sessionObject.setProperty(HttpFileUploadModule.COMPONENT_JIDS_KEY, value: newValue);
        }
    }
    
    var isAvailable: Bool {
        return !availableComponents.isEmpty;
    }
 
}
