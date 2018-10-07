//
//  AppDelegate.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 24.03.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import Cocoa
import TigaseSwift

extension DBConnection {
    
    static var main: DBConnection = {
        let conn = try! DBConnection(dbFilename: "beagleim.sqlite");
        try! DBSchemaManager(dbConnection: conn).upgradeSchema();
        return conn;
    }();
    
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {

    fileprivate let stampFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.locale = Locale(identifier: "en_US_POSIX");
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ";
        f.timeZone = TimeZone(secondsFromGMT: 0);
        return f;
    })();
    
    fileprivate let stampWithMilisFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.locale = Locale(identifier: "en_US_POSIX");
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ";
        f.timeZone = TimeZone(secondsFromGMT: 0);
        return f;
    })();
    
    fileprivate(set) var mainWindowController: NSWindowController?;

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        if #available(OSX 10.14, *) {
            NSApp.appearance = NSAppearance(named: .aqua)
        };
        Settings.initialize();
        NotificationCenter.default.addObserver(self, selector: #selector(authenticationFailure), name: XmppService.AUTHENTICATION_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(serverCertificateError(_:)), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(newMessage), name: DBChatHistoryStore.MESSAGE_NEW, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(chatUpdated), name: DBChatStore.CHAT_UPDATED, object: nil);
        // Insert code here to initialize your application
//        let window = NSApplication.shared.windows[0];
//        let titleAccessoryView = NSTitlebarAccessoryViewController();
//        titleAccessoryView.view = window.contentView!;
//        titleAccessoryView.layoutAttribute = ;
//        window.addTitlebarAccessoryViewController(titleAccessoryView);
//        var mask = window.styleMask;
//        mask.insert(.fullSizeContentView)
//        window.styleMask = mask;// + [NSWindow.StyleMask.fullSizeContentView]
//        window.titlebarAppearsTransparent = true;
//        window.titleVisibility = .hidden;
        
        self.mainWindowController = NSApplication.shared.windows[0].windowController;
        
        NSUserNotificationCenter.default.delegate = self;
        
//        let storyboard = NSStoryboard(name: "Main", bundle: nil);
//        let rosterWindowController = storyboard.instantiateController(withIdentifier: "RosterWindowController") as! NSWindowController;
//        rosterWindowController.showWindow(self);
        _ = XmppService.instance;
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        XmppService.instance.disconnectClients();
    }

    func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        center.removeDeliveredNotification(notification);
        
        guard let id = notification.userInfo?["id"] as? String else {
            return;
        }
        
        switch id {
        case "authentication-failure":
            guard let _ = BareJID(notification.userInfo?["account"] as? String) else {
                return;
            }
            guard let windowController = NSApplication.shared.windows.map({ (window) -> NSWindowController? in
                return window.windowController;
            }).filter({ (controller) -> Bool in
                return controller != nil
            }).first(where: { (controller) -> Bool in
                return (controller?.contentViewController as? NSTabViewController) != nil
            }) ?? mainWindowController?.storyboard?.instantiateController(withIdentifier: "PreferencesWindowController") as? NSWindowController else {
                return;
            }
            (windowController.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 1;
            windowController.showWindow(self);
        case "room-join-error":
            guard let accountStr = notification.userInfo?["account"] as? String, let roomJidStr = notification.userInfo?["roomJid"] as? String, let nickname = notification.userInfo?["nickname"] as? String else {
                return;
            }
            let storyboard = NSStoryboard(name: "Main", bundle: nil);
            guard let windowController = storyboard.instantiateController(withIdentifier: "OpenGroupchatController") as? NSWindowController else {
                return;
            }
            guard let openRoomController = windowController.contentViewController as? OpenGroupchatController else {
                return;
            }
            let roomJid = BareJID(roomJidStr);
            openRoomController.searchField.stringValue = roomJidStr;
            openRoomController.mucJids = [BareJID(roomJid.domain)];
            openRoomController.account = BareJID(accountStr);
            openRoomController.nicknameField.stringValue = nickname;
            guard let window = self.mainWindowController?.window else {
                return;
            }
            window.windowController?.showWindow(self);
            window.beginSheet(windowController.window!, completionHandler: nil);
        case "message-new":
            guard let account = BareJID(notification.userInfo?["account"] as? String), let jid = BareJID(notification.userInfo?["jid"] as? String) else {
                return;
            }
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: nil, userInfo: ["account": account, "jid": jid]);
        default:
            break;
        }
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, shouldPresent notification: NSUserNotification) -> Bool {
        if let account = notification.userInfo?["account"] as? String, let jid = notification.userInfo?["jid"] as? String {
            guard let window = NSApp.windows.first(where: { w -> Bool in
                return w.windowController is ChatsWindowController
            }) else {
                return true;
            }
        
            guard let chatViewController = (window.contentViewController as? NSSplitViewController)?.splitViewItems.last?.viewController as? AbstractChatViewController else {
                return true;
            }
        
            return (chatViewController.account?.stringValue ?? "") != account || (chatViewController.chat?.jid.stringValue ?? "") != jid;
        }
        return true;
    }
    
    @objc func authenticationFailure(_ notification: Notification) {
        guard let accountName = notification.object as? BareJID, let error = notification.userInfo?["error"] as? SaslError else {
            return;
        }
     
        let id = "authenticationError.\(accountName.stringValue)";
        
        // invalidate old auth error notification if there is any
        NSUserNotificationCenter.default.deliveredNotifications.filter { (n) -> Bool in
            return n.identifier == id;
            }.forEach { (n) in
                NSUserNotificationCenter.default.removeDeliveredNotification(n);
        }
        
        let notification = NSUserNotification();
        notification.identifier = UUID().uuidString;
        notification.title = accountName.stringValue;
        notification.subtitle = "Authentication failure";
        switch error {
        case .aborted, .temporary_auth_failure:
            notification.informativeText = "Temporary authetnication failure, will retry..";
        case .invalid_mechanism:
            notification.informativeText = "Required authentication mechanism not supported";
        case .mechanism_too_weak:
            notification.informativeText = "Authentication mechanism is too weak for authentication";
        case .incorrect_encoding, .invalid_authzid, .not_authorized:
            notification.informativeText = "Invalid password for account";
        case .server_not_trusted:
            notification.informativeText = "It was not possible to verify that server is trusted";
        }
        notification.soundName = NSUserNotificationDefaultSoundName;
        notification.userInfo = ["account": accountName.stringValue, "id": "authentication-failure"];
        NSUserNotificationCenter.default.deliver(notification);
    }
    
    @objc func chatUpdated(_ notification: Notification) {
        guard let chat = notification.object as? DBChatProtocol, chat.unread == 0 else {
            return;
        }
        NSUserNotificationCenter.default.deliveredNotifications.forEach { (n) in
            guard let id = n.userInfo?["id"] as? String, id == "message-new" else {
                return;
            }
            guard let account = BareJID(n.userInfo?["account"] as? String), let jid = BareJID(n.userInfo?["jid"] as? String) else {
                return;
            }
            guard chat.account == account && chat.jid.bareJid == jid else {
                return;
            }
            NSUserNotificationCenter.default.removeDeliveredNotification(n);
        }
    }

    @objc func newMessage(_ notification: Notification) {
        guard let item = notification.object as? ChatMessage else {
            return;
        }
        
        guard item.state == .incoming_unread else {
            return;
        }
        
        if item.authorNickname != nil {
            guard let mucModule: MucModule = XmppService.instance.getClient(for: item.account)?.modulesManager.getModule(MucModule.ID), let room = mucModule.roomsManager.getRoom(for: item.jid) else {
                return;
            }
            guard item.message.contains(room.nickname) else {
                return;
            }

            let notification = NSUserNotification();
            notification.identifier = UUID().uuidString;
            notification.title = item.jid.stringValue;
            notification.subtitle = item.authorNickname;
//            notification.deliveryDate = item.timestamp;
            notification.informativeText = item.message;
            notification.soundName = NSUserNotificationDefaultSoundName;
            notification.userInfo = ["account": item.account.stringValue, "jid": item.jid.stringValue, "id": "message-new"];
            NSUserNotificationCenter.default.deliver(notification);
        } else {
            let notification = NSUserNotification();
            notification.identifier = UUID().uuidString;
            notification.title = XmppService.instance.getClient(for: item.account)?.rosterStore?.get(for: JID(item.jid))?.name ?? item.jid.stringValue;
//            notification.deliveryDate = item.timestamp;
            notification.informativeText = item.message;
            notification.soundName = NSUserNotificationDefaultSoundName;
            notification.userInfo = ["account": item.account.stringValue, "jid": item.jid.stringValue, "id": "message-new"];
            NSUserNotificationCenter.default.deliver(notification);
        }
    }
    
    @objc func serverCertificateError(_ notification: Notification) {
        guard let accountName = notification.object as? BareJID else {
            return;
        }
        
        let notification = NSUserNotification();
        notification.identifier = UUID().uuidString;
        notification.title = "Unknown SSL certificate";
        notification.subtitle = "SSL certificate could not be verified.";
        notification.informativeText = "Account \(accountName) was disabled.";
        notification.soundName = NSUserNotificationDefaultSoundName;
        NSUserNotificationCenter.default.deliver(notification);
        
        DispatchQueue.main.async {
            guard let windowController = NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ServerCertificateErrorWindowController") as? NSWindowController else {
                return;
            }
            
            guard let controller = windowController.contentViewController as? ServerCertificateErrorController else {
                return;
            }
            
            controller.account = accountName;
            
            windowController.showWindow(self);
        }
    }
}


