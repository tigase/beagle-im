//
//  HttpFileUploadEventHandler.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 28/09/2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
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
            uploadModule.findHttpUploadComponent(onSuccess: { (values) in
                uploadModule.availableComponents = values.map({ (k,v) -> HttpFileUploadModule.UploadComponent in
                    return HttpFileUploadModule.UploadComponent(jid: k, maxFileSize: v)
                });
                NotificationCenter.default.post(name: HttpFileUploadEventHandler.UPLOAD_SUPPORT_CHANGED, object: account);
            }, onError: { errorCondition in
                print("an error occurred during HTTPFileUpload component discovery!", errorCondition as Any);
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
 
    class UploadComponent {
        
        let jid: JID;
        let maxFileSize: Int;
        
        init(jid: JID, maxFileSize: Int?) {
            self.jid = jid;
            self.maxFileSize = maxFileSize ?? Int.max;
        }
        
    }
}
