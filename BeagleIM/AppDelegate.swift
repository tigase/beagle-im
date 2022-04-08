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
import Combine
import TigaseLogging

extension NSUserInterfaceItemIdentifier {
    
    static let createMeetingMenuItem = NSUserInterfaceItemIdentifier("createMeetingMenuItem");
    static let serviceDiscoveryMenuItem = NSUserInterfaceItemIdentifier("serviceDiscoveryMenuItem")
    static let xmlConsoleMenuItem = NSUserInterfaceItemIdentifier("xmlConsoleMenuItem");
}


extension NSApplication {
    var isDarkMode: Bool {
        return NSAppearance.current.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua;
    }
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate, NSMenuDelegate {
    
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
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AppDelegate");
    
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
        
        init(jid: JID, action: Action? = nil, dict: [String: String]? = nil) {
            self.jid = jid;
            self.action = action;
            self.dict = dict;
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
    
    private var cancellables: Set<AnyCancellable> = [];
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        Settings.$appearance.sink(receiveValue: { appearance in
            switch appearance {
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua);
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua);
            default:
                NSApp.appearance = nil;
            }
        }).store(in: &cancellables);
        
        _ = Database.main;
        NotificationCenter.default.addObserver(self, selector: #selector(authenticationFailure), name: XmppService.AUTHENTICATION_ERROR, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(serverCertificateError(_:)), name: XmppService.SERVER_CERTIFICATE_ERROR, object: nil);
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
        
        XmppService.instance.$currentStatus.combineLatest(DBChatStore.instance.$unreadMessagesCount, Settings.$systemMenuIcon).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (status, unread, show) in
            self?.updateStatusItem(status: status, unread: unread, show: show);
        }).store(in: &cancellables);
        DBChatStore.instance.$unreadMessagesCount.map({ $0 == 0 ? nil : "\($0)" }).receive(on: DispatchQueue.main).assign(to: \.badgeLabel,                                                                                                                            on: NSApplication.shared.dockTile).store(in: &cancellables);
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { (result, error) in
            self.logger.debug("could not get authorization for notifications: \(result), \(error as Any)");
        }
        UNUserNotificationCenter.current().delegate = self;
        
        DBChatHistoryStore.convertToAttachments();
//        let storyboard = NSStoryboard(name: "Main", bundle: nil);
//        let rosterWindowController = storyboard.instantiateController(withIdentifier: "RosterWindowController") as! NSWindowController;
//        rosterWindowController.showWindow(self);
        XmppService.instance.initialize();
        
        if AccountManager.getAccounts().isEmpty {
            let alert = Alert();
            alert.messageText = NSLocalizedString("No account", comment: "No account added to BeagleIM");
            alert.informativeText = NSLocalizedString("To use BeagleIM you need to have the XMPP account configured. Would you like to add one now?", comment: "Should we add one now?");
            alert.addButton(withTitle: NSLocalizedString("Yes", comment: "Yes, we should add account"));
            alert.addButton(withTitle: NSLocalizedString("Not now", comment: "Not now, we will ask later"));
            
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
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedSleepNotification), name: NSWorkspace.willSleepNotification, object: nil);
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedWakeNotification), name: NSWorkspace.didWakeNotification, object: nil);
        
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedScreensSleepNotification), name: NSWorkspace.screensDidSleepNotification, object: nil);
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(receivedScreensWakeNotification), name: NSWorkspace.screensDidWakeNotification, object: nil);
        
        CaptureDeviceManager.requestAccess(for: .audio, completionHandler: { granted in
            self.logger.debug("permission for audio granted: \(granted)");
        })
        CaptureDeviceManager.requestAccess(for: .video, completionHandler: { granted in
            self.logger.debug("permission for video granted: \(granted)");
        })
        
        if let items = NSApp.mainMenu?.items {
            items[items.count - 2].submenu?.delegate = self;
            items[1].submenu?.delegate = self;
        }
        
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
                let rosterWindow = self.rosterWindow;
                rosterWindow.makeKeyAndOrderFront(self);
                if let addContact = NSStoryboard(name: "Roster", bundle: nil).instantiateController(withIdentifier: "AddContactController") as? AddContactController {
                    _ = addContact.view;
                    addContact.jidField.stringValue = uri.jid.stringValue;
                    addContact.labelField.stringValue = uri.dict?["name"] ?? "";
                    addContact.preauthToken = uri.dict?["preauth"];
                    rosterWindow.contentViewController?.presentAsSheet(addContact);
                    addContact.verify();
                }
            }
        }
    }
        
    func menuNeedsUpdate(_ menu: NSMenu) {
        if let meetItem = menu.items.first(where: { $0.identifier == .createMeetingMenuItem }) {
            meetItem.isHidden = (!NSEvent.modifierFlags.contains(.option)) && (!Settings.showAdvancedXmppFeatures);
        }
        if let xmlConsoleItem = menu.items.first(where: { $0.identifier == .xmlConsoleMenuItem }) {
            xmlConsoleItem.isHidden = (!NSEvent.modifierFlags.contains(.option)) && (!Settings.showAdvancedXmppFeatures);
            let accountsMenu = NSMenu(title: "XML Console");
            
            AccountManager.getAccounts().sorted(by: { (a1, a2) -> Bool in
                return a1.stringValue.compare(a2.stringValue) == .orderedAscending;
            }).forEach { (accountJid) in
                accountsMenu.addItem(withTitle: accountJid.stringValue, action: #selector(showXmlConsole), keyEquivalent: "").target = self;
            }
            
            xmlConsoleItem.submenu = accountsMenu;
        }

        if let serviceDiscoveryItem = menu.items.first(where: { $0.identifier == .serviceDiscoveryMenuItem }) {
            serviceDiscoveryItem.isHidden = (!NSEvent.modifierFlags.contains(.option)) && (!Settings.showAdvancedXmppFeatures);
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
        
        XMLConsoleViewController.open(for: accountJid);
    }

    @objc func showServiceDiscovery(_ sender: NSMenuItem) {
        let accountJid = BareJID(sender.title);
        
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
    
    @IBAction func openAppWebsite(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://beagle.im")!);
    }
    
    @IBAction func openGitHub(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://github.com/tigase/beagle-im")!);
    }

    @IBAction func joinTigaseXmppChannel(_ sender: NSMenuItem) {
        makeMainWindowKey();
        let jid = JID("tigase@muc.tigase.org")!;
        guard let conversation = DBChatStore.instance.conversations.first(where: { $0.jid == jid.bareJid }) else {
            handle(action: .join, uri: XmppUri(jid: jid, action: .join, dict: nil));
            return;
        }
        
        NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: conversation);
    }
    
    @IBAction func openAboutUs(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://tigase.net")!);
    }

    @IBAction func openTwitter(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://twitter.com/tigase")!);
    }

    @IBAction func openMastodon(_ sender: NSMenuItem) {
        NSWorkspace.shared.open(URL(string: "https://mastodon.technology/@tigase")!);
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        NSAppleEventManager.shared().removeEventHandler(forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        XmppService.instance.status = XmppService.instance.status.with(show: nil);
        
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
        
        RTCCleanupSSL();
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindowController?.showWindow(self);
        return false;
    }
    
    func updateStatusItem(status: XmppService.Status, unread: Int, show: Bool) {
        if show {
            if self.statusItem == nil {
                self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength);
            }
        } else {
            if let item = self.statusItem {
                self.statusItem = nil;
                NSStatusBar.system.removeStatusItem(item);
            }
        }

        if let statusItem = self.statusItem {
            let connected = status.show != nil;
            let hasUnread = unread > 0;
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
        
    var preferencesWindowController: NSWindowController? {
        return NSApplication.shared.windows.map({ (window) -> NSWindowController? in
            return window.windowController;
        }).filter({ (controller) -> Bool in
            return controller != nil
        }).first(where: { (controller) -> Bool in
            return (controller?.contentViewController as? NSTabViewController) != nil
        }) ?? NSStoryboard(name: "Settings", bundle: nil).instantiateController(withIdentifier: "PreferencesWindowController") as? NSWindowController;
    }
    
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
            
            if (chatViewController.account?.stringValue ?? "") != account || (chatViewController.conversation?.jid.stringValue ?? "") != jid {
                completionHandler([.sound, .alert]);
                return;
            }
        } else {
            completionHandler([.sound, .alert]);
        }
    }
    
    @objc func authenticationFailure(_ notification: Notification) {
        guard let accountName = notification.object as? BareJID, let error = notification.userInfo?["error"] as? SaslError else {
            return;
        }
     
        DispatchQueue.main.async {
            let alert = Alert();
            alert.messageText = String.localizedStringWithFormat(NSLocalizedString("Authentication failure for %@", comment: "authorization failure title"), accountName.stringValue);
            switch error {
            case .aborted, .temporary_auth_failure:
                // those are temporary errors and we will retry, so there is no point in notifying user...
                return;
            case .invalid_mechanism:
                alert.informativeText = NSLocalizedString("Required authentication mechanism not supported", comment: "invalid auth mechanism");
            case .mechanism_too_weak:
                alert.informativeText = NSLocalizedString("Authentication mechanism is too weak for authentication", comment: "auth mechanism too weak");
            case .incorrect_encoding, .invalid_authzid, .not_authorized:
                alert.informativeText = NSLocalizedString("Invalid password for account", comment: "invalid password");
            case .server_not_trusted:
                alert.informativeText = NSLocalizedString("It was not possible to verify that server is trusted", comment: "server not trusted");
            }
            
            alert.icon = NSImage(named: NSImage.cautionName);
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "button label"));
            alert.run(completionHandler: { response in
                guard let windowController = (NSApplication.shared.delegate as? AppDelegate)?.preferencesWindowController else {
                    return;
                }
                (windowController.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = 1;
                windowController.showWindow(self);
            })
        }        
    }
    
    @objc func receivedSleepNotification(_ notification: Notification) {
        logger.debug("####### Going to sleep.....");
        XmppService.instance.isAwake = false;
    }
    
    @objc func receivedWakeNotification(_ notification: Notification) {
        logger.debug("####### Waking up from sleep.....");
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
    
}


