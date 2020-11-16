//
// AppDelegate.swift
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

import Cocoa
import WebRTC
import TigaseSwift
import UserNotifications
import AVFoundation
import AVKit


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
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    
    public static let HOUR_CHANGED = Notification.Name("hourChanged");

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
    lazy var mainWindowController: NSWindowController? = { NSStoryboard(name: "Main", bundle: nil).instantiateController(withIdentifier: "ChatsWindowController") as! NSWindowController }();
    
    var rosterWindow: NSWindow {
        get {
            if let rosterWindow = NSApplication.shared.windows.first(where: { (window) -> Bool in
                window.contentViewController is RosterViewController
            }) {
                return rosterWindow;
            }
            let rosterWindowController = NSStoryboard(name: "Roster", bundle: nil).instantiateController(withIdentifier: "RosterWindowController") as? NSWindowController;
            rosterWindowController!.showWindow(self);
            return rosterWindowController!.window!;
        }
    }
    
    struct XmppUri {
        
        let jid: JID;
        let action: Action?;
        let dict: [String: String]?;
        
        init?(url: URL?) {
            guard url != nil else {
                return nil;
            }
            
            guard let components = URLComponents(url: url!, resolvingAgainstBaseURL: false) else {
                return nil;
            }
            
            guard components.host == nil else {
                return nil;
            }
            self.jid = JID(components.path);
            
            if var pairs = components.query?.split(separator: ";").map({ (it: Substring) -> [Substring] in it.split(separator: "=") }) {
                if let first = pairs.first, first.count == 1 {
                    action = Action(rawValue: String(first.first!));
                    pairs = Array(pairs.dropFirst());
                } else {
                    action = nil;
                }
                var dict: [String: String] = [:];
                for pair in pairs {
                    dict[String(pair[0])] = pair.count == 1 ? "" : String(pair[1]);
                }
                self.dict = dict;
            } else {
                self.action = nil;
                self.dict = nil;
            }
        }
        
        enum Action: String {
            case message
            case join
            case roster
        }
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(self.handleAppleEvent(event:replyEvent:)), forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL));
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {        
        Settings.initialize();
        
        if #available(macOS 10.14, *) {
            updateAppearance();
        }
        
        _ = Database.main;
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
        
        if #available(OSX 10.14, *) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (result, error) in
                print("could not get authorization for notifications", result, error as Any);
            }
            UNUserNotificationCenter.current().delegate = self;
        } else {
            // Fallback on earlier versions
            NSUserNotificationCenter.default.delegate = self;
        }
        
        DBChatHistoryStore.convertToAttachments();
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
        
        NSApp.mainMenu?.item(withTitle: "Window")?.submenu?.delegate = self;
                
        scheduleHourlyTimer();
        for windowName in UserDefaults.standard.stringArray(forKey: "openedWindows") ?? ["chats"] {
            switch windowName {
            case "chats":
                self.mainWindowController?.showWindow(self);
            case "roster":
                self.rosterWindow.windowController?.showWindow(self);
            default:
                break;
            }
        }
    }
    
    @objc func handleAppleEvent(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let appleEventDescription = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject)) else {
            return
        }
        
        guard let appleEventURLString = appleEventDescription.stringValue else {
            return
        }
        
        guard let uri = XmppUri(url: URL(string: appleEventURLString)) else {
            return;
        }
       
        if let action = uri.action {
            handle(action: action, uri: uri);
        } else {
            DispatchQueue.main.async {
                let alert = Alert();
                alert.icon = NSImage(named: NSImage.infoName);
                alert.messageText = "Open URL";
                alert.informativeText = "What do you want to do with " + uri.jid.stringValue + "?";
                alert.addButton(withTitle: "Open chat");
                alert.addButton(withTitle: "Join room");
                alert.addButton(withTitle: "Add to contacts");
                alert.addButton(withTitle: "Ignore");
                alert.run(completionHandler: { (response) in
                    switch response {
                    case .alertFirstButtonReturn:
                        self.handle(action: .message, uri: uri);
                    case .alertSecondButtonReturn:
                        self.handle(action: .join, uri: uri);
                    case .alertThirdButtonReturn:
                        self.handle(action: .roster, uri: uri);
                    default:
                        break;
                    }
                })
            }
        }
    }
    
    fileprivate func handle(action: XmppUri.Action, uri: XmppUri) {
        switch action {
        case .join:
            DispatchQueue.main.async {
                guard let windowController = self.mainWindowController?.storyboard?.instantiateController(withIdentifier: "OpenGroupchatController") as? NSWindowController else {
                    return;
                }
                (windowController.contentViewController as? OpenGroupchatController)?.componentJidField.stringValue = uri.jid.domain;
                (windowController.contentViewController as? OpenGroupchatController)?.componentJid = BareJID(uri.jid.domain);
                (windowController.contentViewController as? OpenGroupchatController)?.searchField.stringValue = uri.jid.localPart ?? "";
                (windowController.contentViewController as? OpenGroupchatController)?.password = uri.dict?["password"];
                self.mainWindowController?.window?.beginSheet(windowController.window!, completionHandler: nil);
            }
        case .message:
            DispatchQueue.main.async {
                guard let windowController = self.mainWindowController?.storyboard?.instantiateController(withIdentifier: "Open1On1ChatController") as? NSWindowController else {
                    return;
                }
                (windowController.contentViewController as? Open1On1ChatController)?.searchField.stringValue = uri.jid.bareJid.stringValue;
                self.mainWindowController?.window?.beginSheet(windowController.window!, completionHandler: nil);
            }
        case .roster:
            DispatchQueue.main.async {
                print("uri:", uri.jid, "dict:", uri.dict as Any);
                let rosterWindow = self.rosterWindow;
                rosterWindow.makeKeyAndOrderFront(self);
                if let addContact = NSStoryboard(name: "Roster", bundle: nil).instantiateController(withIdentifier: "AddContactController") as? AddContactController {
                    _ = addContact.view;
                    addContact.jidField.stringValue = uri.jid.stringValue;
                    addContact.labelField.stringValue = uri.dict?["name"] ?? "";
                    addContact.preauthToken = uri.dict?["preauth"];
                    rosterWindow.contentViewController?.presentAsSheet(addContact);
                    addContact.verify();
                } else {
                    print("no add contact controller!");
                }
            }
        }
    }
    
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let xmlConsoleItem = menu.item(withTitle: "XML Console") {
            xmlConsoleItem.isHidden = (!NSEvent.modifierFlags.contains(.option)) && (!Settings.showAdvancedXmppFeatures.bool());
            let accountsMenu = NSMenu(title: "XML Console");
            
            AccountManager.getAccounts().sorted(by: { (a1, a2) -> Bool in
                return a1.stringValue.compare(a2.stringValue) == .orderedAscending;
            }).forEach { (accountJid) in
                accountsMenu.addItem(withTitle: accountJid.stringValue, action: #selector(showXmlConsole), keyEquivalent: "").target = self;
            }
            
            xmlConsoleItem.submenu = accountsMenu;
        }

        if let serviceDiscoveryItem = menu.item(withTitle: "Service Discovery") {
            serviceDiscoveryItem.isHidden = (!NSEvent.modifierFlags.contains(.option)) && (!Settings.showAdvancedXmppFeatures.bool());
            let accountsMenu = NSMenu(title: "Service Discovery");
            
            AccountManager.getAccounts().filter({ (a1) -> Bool in
                return XmppService.instance.getClient(for: a1) != nil;
            }).sorted(by: { (a1, a2) -> Bool in
                return a1.stringValue.compare(a2.stringValue) == .orderedAscending;
            }).forEach { (accountJid) in
                accountsMenu.addItem(withTitle: accountJid.stringValue, action: #selector(showServiceDiscovery), keyEquivalent: "").target = self;
            }
            
            serviceDiscoveryItem.submenu = accountsMenu;
        }
    }
    
    @objc func showXmlConsole(_ sender: NSMenuItem) {
        let accountJid = BareJID(sender.title);
        
        print("xml console for:", accountJid);
        XMLConsoleViewController.open(for: accountJid);
    }

    @objc func showServiceDiscovery(_ sender: NSMenuItem) {
        let accountJid = BareJID(sender.title);
        
        print("service discovery for:", accountJid);
        
        guard let windowController = NSStoryboard(name: "ServiceDiscovery", bundle: nil).instantiateController(withIdentifier: "ServiceDiscoveryWindowController") as? NSWindowController else {
            return;
        }
        
        guard let controller = windowController.contentViewController as? ServiceDiscoveryViewController else {
            return;
        }
        
        controller.account = accountJid;
        controller.jid = JID(accountJid.domain);
        
        windowController.showWindow(self);
    }
    
    @IBAction func showSeachHistory(_ sender: NSMenuItem) {
        mainWindowController?.showWindow(self);
        DispatchQueue.main.async {
            guard let windowController = NSStoryboard(name: "SearchHistory", bundle: nil).instantiateController(withIdentifier: "SearchHistoryWindowController") as? NSWindowController else {
                return;
            }
            self.mainWindowController?.window?.beginSheet(windowController.window!, completionHandler: nil);
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        XmppService.instance.disconnectClients();
        
        let openedWindows = NSApp.windows.map { (window) -> String? in
            guard let windowController = window.windowController else {
                guard let contentView = window.contentViewController else {
                    return nil;
                }
                return contentView is RosterViewController ? "roster" : nil;

            }
            switch windowController {
            case is ChatsWindowController:
                return "chats";
//            case is RosterWindowController:
//                return "roster";
            default:
                return nil;
            }
        }.filter({ $0 != nil }).map({ $0! });
        UserDefaults.standard.set(openedWindows, forKey: "openedWindows");
        
        descheduleHourlyTimer();
        RTCCleanupSSL();
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
            statusItem.button?.action = #selector(makeMainWindowKey);
        }
    }
    
    @objc func makeMainWindowKey() {
        NSApp.unhide(self);
        self.mainWindowController?.showWindow(self);
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true);
        }
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
        }) ?? NSStoryboard(name: "Settings", bundle: nil).instantiateController(withIdentifier: "PreferencesWindowController") as? NSWindowController;
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
            openRoomController.componentJids = [BareJID(roomJid.domain)];
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
        
        // TODO: remove in the next version
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
            openRoomController.componentJids = [BareJID(roomJid.domain)];
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
        case "presence-subscription-request", "muc-invitation":
            self.makeMainWindowKey();
            InvitationManager.instance.handle(invitationWithId: response.notification.request.identifier, window: self.mainWindowController!.window!);
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
     
        DispatchQueue.main.async {
            let alert = Alert();
            alert.messageText = "Authentication failure for \(accountName.stringValue)";
            switch error {
            case .aborted, .temporary_auth_failure:
                // those are temporary errors and we will retry, so there is no point in notifying user...
                return;
            case .invalid_mechanism:
                alert.informativeText = "Required authentication mechanism not supported";
            case .mechanism_too_weak:
                alert.informativeText = "Authentication mechanism is too weak for authentication";
            case .incorrect_encoding, .invalid_authzid, .not_authorized:
                alert.informativeText = "Invalid password for account";
            case .server_not_trusted:
                alert.informativeText = "It was not possible to verify that server is trusted";
            }
            
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.addButton(withTitle: "OK");
            alert.run(completionHandler: { response in
                guard let windowController = (NSApplication.shared.delegate as? AppDelegate)?.preferencesWindowController else {
                    return;
                }
                (windowController.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 1;
                windowController.showWindow(self);
            })
        }        
    }
    
    @objc func chatUpdated(_ notification: Notification) {
        guard let chat = notification.object as? Conversation, chat.unread == 0 else {
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
        
        let conversation = DBChatStore.instance.conversation(for: item.account, with: item.jid);
        let notifications = conversation?.notifications ?? .none;

        switch notifications {
        case .none:
            return;
        case .mention:
            if let nickname = (conversation as? Room)?.nickname ?? (conversation as? Channel)?.nickname {
                if !item.message.contains(nickname) {
                    if let keywords = Settings.markKeywords.stringArrays(), !keywords.isEmpty {
                        if  keywords.first(where: { item.message.contains($0) }) == nil {
                            return;
                        }
                    } else {
                        return;
                    }
                }
            } else {
                return;
            }
        case .always:
            break;
        }
        
        if item.authorNickname != nil {
            if #available(OSX 10.14, *) {
                let content = UNMutableNotificationContent();
                content.title = item.jid.stringValue;
                content.subtitle = item.authorNickname ?? "";
                content.body = (item.message.contains("`") || !Settings.enableMarkdownFormatting.bool() || !Settings.showEmoticons.bool()) ? item.message : item.message.emojify();
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
                notification.informativeText = (item.message.contains("`") || !Settings.enableMarkdownFormatting.bool() || !Settings.showEmoticons.bool()) ? item.message : item.message.emojify();
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
                content.body = (item.message.contains("`") || !Settings.enableMarkdownFormatting.bool() || !Settings.showEmoticons.bool()) ? item.message : item.message.emojify();
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
                notification.informativeText = (item.message.contains("`") || !Settings.enableMarkdownFormatting.bool() || !Settings.showEmoticons.bool()) ? item.message : item.message.emojify();
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
    
    fileprivate var hourlyTimer: Foundation.Timer? = nil;
    
    func descheduleHourlyTimer() {
        if let timer = self.hourlyTimer {
            self.hourlyTimer = nil;
            timer.invalidate();
        }
    }
    
    @objc func hourlyTimerTriggered() {
        NotificationCenter.default.post(name: AppDelegate.HOUR_CHANGED, object: self);
    }
    
    func scheduleHourlyTimer() {
        guard hourlyTimer == nil else {
            return;
        }
        let next = Calendar.current.date(bySetting: .second, value: 1, of: Calendar.current.date(bySetting: .minute, value: 0, of: Date())!)!;

        print("scheduling hourly timer for:", next, "current:", Date());
        
        self.hourlyTimer = Foundation.Timer(fireAt: next, interval: 3600.0, target: self, selector: #selector(hourlyTimerTriggered), userInfo: nil, repeats: true);
        RunLoop.current.add(self.hourlyTimer!, forMode: .common);
    }
}


