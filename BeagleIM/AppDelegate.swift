//
// AppDelegate.swift
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

import Cocoa
import TigaseSwift
import UserNotifications
import AVFoundation
import AVKit

extension DBConnection {
    
    static var main: DBConnection = {
        let conn = try! DBConnection(dbFilename: "beagleim.sqlite");
        try! DBSchemaManager(dbConnection: conn).upgradeSchema();
        return conn;
    }();
    
}

extension NSApplication {
    var isDarkMode: Bool {
        if #available(macOS 10.14, *) {
            return NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua;
        } else {
            return false;
        }
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, UNUserNotificationCenterDelegate {

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
    
    fileprivate var statusItem: NSStatusItem?;
    fileprivate(set) var mainWindowController: NSWindowController?;
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Settings.initialize();
        
        if #available(macOS 10.14, *) {
            updateAppearance();
        }
        
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
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: Settings.CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(updateStatusItem(_:)), name: XmppService.STATUS_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(unreadMessagesCountChanged), name: DBChatStore.UNREAD_MESSAGES_COUNT_CHANGED, object: nil);
        
        self.mainWindowController = NSApplication.shared.windows[0].windowController;
        
        if #available(OSX 10.14, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (result, error) in
                print("could not get authorization for notifications", result, error as Any);
            }
            UNUserNotificationCenter.current().delegate = self;
        } else {
            // Fallback on earlier versions
            NSUserNotificationCenter.default.delegate = self;
        }
        
//        let storyboard = NSStoryboard(name: "Main", bundle: nil);
//        let rosterWindowController = storyboard.instantiateController(withIdentifier: "RosterWindowController") as! NSWindowController;
//        rosterWindowController.showWindow(self);
        _ = XmppService.instance;
        
        if AccountManager.getAccounts().isEmpty {
            let alert = Alert();
            alert.messageText = "No account";
            alert.informativeText = "To use BeagleIM you need to have the XMPP account configured. Would you like to add one now?";
            alert.addButton(withTitle: "Yes");
            alert.addButton(withTitle: "Not now");
            
            alert.run { (response) in
                switch response {
                case .alertFirstButtonReturn:
                    // open settings window
                    guard let preferencesWindowController = self.preferencesWindowController else {
                        return;
                    }
                    (preferencesWindowController.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 1;
                    preferencesWindowController.showWindow(self);
                default:
                    // do nothing..
                    break;
                }
            };
        }
        
        if Settings.systemMenuIcon.bool() {
            self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength);
            self.updateStatusItem();
        }
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedSleepNotification), name: NSWorkspace.willSleepNotification, object: nil);
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedWakeNotification), name: NSWorkspace.didWakeNotification, object: nil);
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedScreensSleepNotification), name: NSWorkspace.screensDidSleepNotification, object: nil);
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedScreensWakeNotification), name: NSWorkspace.screensDidWakeNotification, object: nil);
        
        // TODO: maybe should be moved later on...
        if #available(OSX 10.14, *) {
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: { granted in
                print("permission granted: \(granted)");
                if granted {
                }
            })
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                print("permission granted: \(granted)");
                if granted {
                }
            })
        } else {
            // Fallback on earlier versions
        }
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        XmppService.instance.disconnectClients();
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.showWindow(self);
        return false;
    }
    
    @objc func updateStatusItem(_ notification: Notification) {
        updateStatusItem();
    }
    
    func updateStatusItem() {
        if let statusItem = self.statusItem {
            let connected = XmppService.instance.currentStatus.show != nil;
            let hasUnread = DBChatStore.instance.unreadMessagesCount > 0;
            let statusItemImage = NSImage(named: hasUnread ? NSImage.applicationIconName : (connected ? "MenuBarOnline" : "MenuBarOffline"));
            statusItemImage?.resizingMode = .tile;
            let size = min(statusItem.button!.frame.height, statusItem.button!.frame.height);
            statusItemImage?.size = NSSize(width: size, height: size);
            statusItem.button?.image = statusItemImage;
            statusItem.action = #selector(makeMainWindowKey);
        }
    }
    
    @objc func makeMainWindowKey() {
        self.mainWindowController?.showWindow(self);
    }
    
    @objc func unreadMessagesCountChanged(_ notification: Notification) {
        guard let value = notification.object as? Int else {
            return;
        }
        if value > 0 {
            NSApplication.shared.dockTile.badgeLabel = "\(value)";
        } else {
            NSApplication.shared.dockTile.badgeLabel = nil;
        }
        updateStatusItem();
    }
    
    @objc func settingsChanged(_ notification: Notification) {
        guard let setting = notification.object as? Settings else {
            return;
        }
        
        switch setting {
        case .systemMenuIcon:
            if (setting.bool()) {
                if (self.statusItem == nil) {
                    self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength);
                }
                updateStatusItem();
            } else {
                if let item = self.statusItem {
                    self.statusItem = nil;
                    NSStatusBar.system.removeStatusItem(item);
                }
            }
        case .appearance:
            if #available(macOS 10.14, *) {
                updateAppearance();
            }
        default:
            break;
        }
    }
    
    @available(OSX 10.14, *)
    fileprivate func updateAppearance() {
        let appearance: Appearance = Appearance(rawValue: Settings.appearance.string() ?? "") ??  .auto;
        switch appearance {
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua);
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua);
        default:
            NSApp.appearance = nil;
        }
    }
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didDeliver notification: NSUserNotification) {
        
    }
    
    var preferencesWindowController: NSWindowController? {
        return NSApplication.shared.windows.map({ (window) -> NSWindowController? in
            return window.windowController;
        }).filter({ (controller) -> Bool in
            return controller != nil
        }).first(where: { (controller) -> Bool in
            return (controller?.contentViewController as? NSTabViewController) != nil
        }) ?? mainWindowController?.storyboard?.instantiateController(withIdentifier: "PreferencesWindowController") as? NSWindowController;
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
            guard let windowController = preferencesWindowController else {
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
    
    @available(OSX 10.14, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [response.notification.request.identifier]);
        
        let userInfo = response.notification.request.content.userInfo;
        guard let id = userInfo["id"] as? String else {
            return;
        }
        
        switch id {
        case "authentication-failure":
            guard let _ = BareJID(userInfo["account"] as? String) else {
                break;
            }
            guard let windowController = preferencesWindowController else {
                break;
            }
            (windowController.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 1;
            windowController.showWindow(self);
        case "room-join-error":
            guard let accountStr = userInfo["account"] as? String, let roomJidStr = userInfo["roomJid"] as? String, let nickname = userInfo["nickname"] as? String else {
                break;
            }
            let storyboard = NSStoryboard(name: "Main", bundle: nil);
            guard let windowController = storyboard.instantiateController(withIdentifier: "OpenGroupchatController") as? NSWindowController else {
                break;
            }
            guard let openRoomController = windowController.contentViewController as? OpenGroupchatController else {
                break;
            }
            let roomJid = BareJID(roomJidStr);
            openRoomController.searchField.stringValue = roomJidStr;
            openRoomController.mucJids = [BareJID(roomJid.domain)];
            openRoomController.account = BareJID(accountStr);
            openRoomController.nicknameField.stringValue = nickname;
            guard let window = self.mainWindowController?.window else {
                break;
            }
            window.windowController?.showWindow(self);
            window.beginSheet(windowController.window!, completionHandler: nil);
        case "message-new":
            guard let account = BareJID(userInfo["account"] as? String), let jid = BareJID(userInfo["jid"] as? String) else {
                break;
            }
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: nil, userInfo: ["account": account, "jid": jid]);
        default:
            break;
        }
        
        completionHandler();
    }
    
    @available(OSX 10.14, *)
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        
        if let account = notification.request.content.userInfo["account"] as? String, let jid = notification.request.content.userInfo["jid"] as? String {
            guard let window = NSApp.windows.first(where: { w -> Bool in
                return w.windowController is ChatsWindowController
            }) else {
                completionHandler([.sound, .alert]);
                return;
            }
            
            guard let chatViewController = (window.contentViewController as? NSSplitViewController)?.splitViewItems.last?.viewController as? AbstractChatViewController else {
                completionHandler([.sound, .alert]);
                return;
            }
            
            if (chatViewController.account?.stringValue ?? "") != account || (chatViewController.chat?.jid.stringValue ?? "") != jid {
                completionHandler([.sound, .alert]);
                return;
            }
        } else {
            completionHandler([.sound, .alert]);
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
        
        if #available(OSX 10.14, *) {
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id]);
            
            let content = UNMutableNotificationContent();
            content.title = accountName.stringValue;
            content.subtitle = "Authentication failure";
            switch error {
            case .aborted, .temporary_auth_failure:
                content.body = "Temporary authetnication failure, will retry..";
            case .invalid_mechanism:
                content.body = "Required authentication mechanism not supported";
            case .mechanism_too_weak:
                content.body = "Authentication mechanism is too weak for authentication";
            case .incorrect_encoding, .invalid_authzid, .not_authorized:
                content.body = "Invalid password for account";
            case .server_not_trusted:
                content.body = "It was not possible to verify that server is trusted";
            }
            content.sound = UNNotificationSound.defaultCritical;
            content.userInfo = ["account": accountName.stringValue, "id": "authentication-failure"];
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
            UNUserNotificationCenter.current().add(request) { (error) in
                print("could not show notification:", error as Any);
            }
        } else {
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
    }
    
    @objc func chatUpdated(_ notification: Notification) {
        guard let chat = notification.object as? DBChatProtocol, chat.unread == 0 else {
            return;
        }
        
        if #available(OSX 10.14, *) {
            UNUserNotificationCenter.current().getDeliveredNotifications { (notifications) in
                let identifiers = notifications.filter({ (n) -> Bool in
                    let userInfo = n.request.content.userInfo;
                    guard let id = userInfo["id"] as? String, id == "message-new" else {
                        return false;
                    }
                    guard let account = BareJID(userInfo["account"] as? String), let jid = BareJID(userInfo["jid"] as?    String) else {
                        return false;
                    }
                    guard chat.account == account && chat.jid.bareJid == jid else {
                        return false;
                    }
                    return true;
                }).map({ (n) -> String in
                    return n.request.identifier;
                });
                UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers);
            }
        } else {
            NSUserNotificationCenter.default.deliveredNotifications.forEach { (n) in
                guard let id = n.userInfo?["id"] as? String, id == "message-new" else {
                    return;
                }
                guard let account = BareJID(n.userInfo?["account"] as? String), let jid = BareJID(n.userInfo?["jid"] as?    String) else {
                    return;
                }
                guard chat.account == account && chat.jid.bareJid == jid else {
                    return;
                }
                NSUserNotificationCenter.default.removeDeliveredNotification(n);
            }
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
            
            if #available(OSX 10.14, *) {
                let content = UNMutableNotificationContent();
                content.title = item.jid.stringValue;
                content.subtitle = item.authorNickname ?? "";
                content.body = item.message;
                content.sound = UNNotificationSound.default
                content.userInfo = ["account": item.account.stringValue, "jid": item.jid.stringValue, "id": "message-new"];
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
                UNUserNotificationCenter.current().add(request) { (error) in
                    print("could not show notification:", error as Any);
                }
            } else {
                let notification = NSUserNotification();
                notification.identifier = UUID().uuidString;
                notification.title = item.jid.stringValue;
                notification.subtitle = item.authorNickname;
                //            notification.deliveryDate = item.timestamp;
                notification.informativeText = item.message;
                notification.soundName = NSUserNotificationDefaultSoundName;
                notification.userInfo = ["account": item.account.stringValue, "jid": item.jid.stringValue, "id": "message-new"];
                NSUserNotificationCenter.default.deliver(notification);
            }
        } else {
            let rosterItem = XmppService.instance.getClient(for: item.account)?.rosterStore?.get(for: JID(item.jid));
            guard rosterItem != nil || Settings.notificationsFromUnknownSenders.bool() else {
                return;
            }
            
            if #available(OSX 10.14, *) {
                let content = UNMutableNotificationContent();
                content.title = rosterItem?.name ?? item.jid.stringValue;
                content.body = item.message;
                content.sound = UNNotificationSound.default
                content.userInfo = ["account": item.account.stringValue, "jid": item.jid.stringValue, "id": "message-new"];
                let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
                UNUserNotificationCenter.current().add(request) { (error) in
                    print("could not show notification:", error as Any);
                }
            } else {
                let notification = NSUserNotification();
                notification.identifier = UUID().uuidString;
                notification.title = rosterItem?.name ?? item.jid.stringValue;
                //            notification.deliveryDate = item.timestamp;
                notification.informativeText = item.message;
                notification.soundName = NSUserNotificationDefaultSoundName;
                notification.userInfo = ["account": item.account.stringValue, "jid": item.jid.stringValue, "id": "message-new"];
                NSUserNotificationCenter.default.deliver(notification);
                
                print("presented:", notification.isPresented);
            };
        }
    }
    
    @objc func receivedSleepNotification(_ notification: Notification) {
        print("####### Going to sleep.....", Date());
        XmppService.instance.isAwake = false;
    }
    
    @objc func receivedWakeNotification(_ notification: Notification) {
        print("####### Waking up from sleep.....", Date());
        XmppService.instance.isAwake = true;
    }
    
    @objc func receivedScreensSleepNotification(_ notification: Notification) {
        XmppService.instance.isIdle = true;
    }
    
    @objc func receivedScreensWakeNotification(_ notification: Notification) {
        XmppService.instance.isIdle = false;
    }
    
    @objc func serverCertificateError(_ notification: Notification) {
        guard let accountName = notification.object as? BareJID else {
            return;
        }
        
        if #available(OSX 10.14, *) {
            let content = UNMutableNotificationContent();
            content.title = "Unknown SSL certificate";
            content.subtitle = "SSL certificate could not be verified.";
            content.body = "Account \(accountName) was disabled.";
            content.sound = UNNotificationSound.defaultCritical;
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil);
            UNUserNotificationCenter.current().add(request) { (error) in
                print("could not show notification:", error as Any);
            }
        } else {
            let notification = NSUserNotification();
            notification.identifier = UUID().uuidString;
            notification.title = "Unknown SSL certificate";
            notification.subtitle = "SSL certificate could not be verified.";
            notification.informativeText = "Account \(accountName) was disabled.";
            notification.soundName = NSUserNotificationDefaultSoundName;
            NSUserNotificationCenter.default.deliver(notification);
        }
        
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
    
    
    @IBAction func closeChat(_ sender: Any) {
        NotificationCenter.default.post(name: ChatsListViewController.CLOSE_SELECTED_CHAT, object: nil);
    }
}


