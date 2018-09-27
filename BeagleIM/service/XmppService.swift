//
//  XmppService.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 14.04.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class XmppService: EventHandler {
    
    static let CONTACT_PRESENCE_CHANGED = Notification.Name("contactPresenceChanged");
    static let STATUS_CHANGED = Notification.Name("statusChanged");
    static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    
    static let instance = XmppService();
 
    fileprivate let observedEvents: [Event] = [ SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE ];
    
    fileprivate let eventHandlers: [XmppServiceEventHandler] = [MucEventHandler(), PresenceRosterEventHandler(), AvatarEventHandler(), MessageEventHandler()];
    
    var clients: [BareJID: XMPPClient] {
        get {
            return dispatcher.sync {
                return _clients;
            }
        }
    }
    
    fileprivate var _clients = [BareJID: XMPPClient]();
    
    fileprivate let dispatcher = QueueDispatcher(label: "xmpp_service");
    fileprivate let reachability = Reachability();
    
    fileprivate(set) var isNetworkAvailable: Bool = false {
        didSet {
            if isNetworkAvailable {
                if !oldValue {
                    connectClients();
                } else {
                    sendKeepAlive();
                }
            } else {
                disconnectClients(force: true);
            }
        }
    }

    var status: Status = Status(show: nil, message: nil) {
        didSet {
            if Settings.rememberLastStatus.bool() {
                Settings.currentStatus.set(value: status);
            }
            if status.show == nil && oldValue.show != nil {
                self.disconnectClients();
            }
            else if status.show != nil && oldValue.show == nil {
                self.connectClients();
            }
            else if status.show != nil {
                self.clients.values.forEach { client in
                    guard let presenceModule: PresenceModule = client.modulesManager.getModule(PresenceModule.ID) else {
                        return;
                    }
                    
                    presenceModule.setPresence(show: status.show!, status: status.message, priority: nil);
                }
                self.currentStatus = status;
            }
        }
    }
    
    fileprivate(set) var currentStatus: Status = Status(show: nil, message: nil) {
        didSet {
            NotificationCenter.default.post(name: XmppService.STATUS_CHANGED, object: currentStatus);
        }
    }
    
    init() {
        let accountNames = AccountManager.getActiveAccounts();
        
        accountNames.forEach { accountName in
            if let client = self.initializeClient(jid: accountName) {
                print("XMPP client for account", accountName, "initialized!");
                //clients[accountName] = client;
                _ = self.register(client: client, for: accountName);
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(networkChanged), name: Reachability.NETWORK_CHANGED, object: nil);
        NotificationCenter.default.addObserver(self, selector: #selector(accountChanged), name: AccountManager.ACCOUNT_CHANGED, object: nil);
        initialize();
    }
    
    fileprivate func initialize() {
        self.isNetworkAvailable = reachability.isConnectedToNetwork();
        if Settings.automaticallyConnectAfterStart.bool() {
            if let status: Status = Settings.currentStatus.object() {
                self.status = status;
            } else {
                self.status = self.status.with(show: .online);
            }
        }
    }
    
    func getClient(for account: BareJID) -> XMPPClient? {
        return dispatcher.sync {
            return clients[account];
        }
    }
    
    func connectClients() {
        guard self.isNetworkAvailable && self.status.show != nil else {
            return;
        }
        dispatcher.async {
            self.clients.values.forEach { client in
                self.connect(client: client);
            }
        }
    }
    
    func disconnectClients(force: Bool = false) {
        dispatcher.async {
            self.clients.values.forEach { client in
                client.disconnect(force);
            }
        }
    }
    
    fileprivate func sendKeepAlive() {
        dispatcher.async {
            self.clients.values.forEach { client in
                client.keepalive();
            }
        }
    }
    
    func handle(event: Event) {
        switch event {
        case is StreamManagementModule.ResumedEvent:
            updateCurrentStatus();
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            //test(e.sessionObject);
            print("account", e.sessionObject.userBareJid!, "is now connected!");
            self.updateCurrentStatus();
            break;
        case let e as SocketConnector.CertificateErrorEvent:
            let certData = ServerCertificateInfo(trust: e.trust);
            
            if let accountName = e.sessionObject.userBareJid, let account = AccountManager.getAccount(for: accountName) {
                account.active = false;
                account.serverCertificate = certData;
                _ = AccountManager.save(account: account);
                NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: accountName);
            }
        case let e as SocketConnector.DisconnectedEvent:
            updateCurrentStatus();
            
            let accountName = e.sessionObject.userBareJid!;
            self.dispatcher.sync {
                let active = AccountManager.getAccount(for: accountName)?.active
                if !(active ?? false) {
                    guard let client = self._clients.removeValue(forKey: accountName) else {
                        return;
                    }
                    if active != nil {
                        if let messageModule: MessageModule = client.modulesManager.getModule(MessageModule.ID) {
                            ((messageModule.chatManager as! DefaultChatManager).chatStore as! DBChatStoreWrapper).deinitialize();
                        }
                    } else {
                        DBRosterStore.instance.removeAll(for: accountName);
                        DBChatStore.instance.closeAll(for: accountName);
                        DBChatHistoryStore.instance.removeHistory(for: accountName, with: nil);
                    }
                    DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + 0.5, execute: {
                        client.eventBus.unregister(handler: self, for: self.observedEvents);
                        self.eventHandlers.forEach { handler in
                            client.eventBus.unregister(handler: handler, for: handler.events);
                        }
                    })
                }
            }
            guard self.status.show != nil || !self.isNetworkAvailable else {
                return;
            }
            if let client = self.getClient(for: accountName) {
                let retry = client.retryNo;
                client.retryNo = retry + 1;
                var timeout = 2.0 * Double(retry) + 0.5;
                if timeout > 16 {
                    timeout = 15;
                }
                DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + timeout) {
                    self.connect(client: client);
                }
            }
        default:
            break;
        }
    }
    
    fileprivate func connect(client: XMPPClient) {
        guard let account = AccountManager.getAccount(for: client.sessionObject.userBareJid!), account.active else {
            return;
        }
        
        client.connectionConfiguration.setUserPassword(account.password);
            SslCertificateValidator.setAcceptedSslCertificate(client.sessionObject, fingerprint: (account.serverCertificate?.accepted ?? false) ? account.serverCertificate?.details.fingerprintSha1 : nil);

        client.login();
    }
    
    fileprivate func updateCurrentStatus() {
        dispatcher.async {
            guard self._clients.values.first(where: { (client) -> Bool in
                return client.state == .connected;
            }) != nil else {
                DispatchQueue.main.async { self.currentStatus = self.status.with(show: nil); }
                return;
            }
            DispatchQueue.main.async { self.currentStatus = self.status; }
        }
    }

    @objc func accountChanged(_ notification: Notification) {
        guard let account = notification.object as? AccountManager.Account else {
            return;
        }
    
        let active = AccountManager.getAccount(for: account.name)?.active;
        guard active ?? false else {
            dispatcher.sync {
                guard let client = self._clients[account.name] else {
                    return;
                }
                
                client.disconnect();
            }
            return;
        }
        
        dispatcher.sync {
            if let client = self._clients[account.name] {
                client.connectionConfiguration.setUserPassword(account.password!);
                client.disconnect();
            } else {
                let client = self.register(client: self.initializeClient(jid: account.name)!, for: account.name);
                if let messageModule: MessageModule = client.modulesManager.getModule(MessageModule.ID) {
                    ((messageModule.chatManager as! DefaultChatManager).chatStore as! DBChatStoreWrapper).initialize();
                }
                if self.isNetworkAvailable {
                    DispatchQueue.global().async {
                        self.connect(client: client);
                    }
                }
            }
        }
    }
    
    @objc func networkChanged(_ notification: Notification) {
        guard let reachability = notification.object as? Reachability else {
            return;
        }
        
        self.isNetworkAvailable = reachability.isConnectedToNetwork();
    }
    
    fileprivate func initializeClient(jid: BareJID) -> XMPPClient? {
        guard AccountManager.getAccount(for: jid)?.active ?? false else {
            return nil;
        }
        
        let client = XMPPClient();
        client.connectionConfiguration.setUserJID(jid);
        
        _ = client.modulesManager.register(StreamManagementModule());
        _ = client.modulesManager.register(AuthModule());
        //_ = client.modulesManager.register(StreamFeaturesModuleWithPipelining(cache: streamFeaturesCache, enabled: false));
        // if you do not want Pipelining you may use StreamFeaturesModule instead StreamFeaturesModuleWithPipelining
        _ = client.modulesManager.register(StreamFeaturesModule());
        _ = client.modulesManager.register(SaslModule());
        _ = client.modulesManager.register(ResourceBinderModule());
        _ = client.modulesManager.register(SessionEstablishmentModule());
        _ = client.modulesManager.register(DiscoveryModule());
        _ = client.modulesManager.register(SoftwareVersionModule());
        _ = client.modulesManager.register(VCardTempModule());
        _ = client.modulesManager.register(VCard4Module());
        
        client.modulesManager.register(CapabilitiesModule()).cache = DBCapabilitiesCache.instance;
        _ = client.modulesManager.register(PubSubModule());
        _ = client.modulesManager.register(PEPUserAvatarModule());
        
        let messageModule = MessageModule();
        let chatStoreWrapper = DBChatStoreWrapper(sessionObject: client.context.sessionObject);
        chatStoreWrapper.initialize();
        messageModule.chatManager = DefaultChatManager(context: client.context, chatStore: chatStoreWrapper);
        _ = client.modulesManager.register(messageModule);
        
        _ = client.modulesManager.register(MessageDeliveryReceiptsModule());
        
        let rosterStoreWrapper = DBRosterStoreWrapper(sessionObject: client.context.sessionObject);
        rosterStoreWrapper.initialize();
        client.context.sessionObject.setUserProperty(RosterModule.ROSTER_STORE_KEY, value: rosterStoreWrapper);
        _ = client.modulesManager.register(RosterModule());
        
        _ = client.modulesManager.register(PresenceModule());
        
        client.modulesManager.register(MucModule()).roomsManager = DBRoomsManager();
        
        client.modulesManager.initIfRequired();
        
        SslCertificateValidator.registerSslCertificateValidator(client.sessionObject);
        
        return client;
    }

    fileprivate func register(client: XMPPClient, for account: BareJID) -> XMPPClient {
        return dispatcher.sync {
            client.eventBus.register(handler: self, for: observedEvents);
            eventHandlers.forEach { handler in
                client.eventBus.register(handler: handler, for: handler.events);
            }
        
            self._clients[account] = client;
            return client;
        }
    }
    
    class Status: CustomDictionaryConvertible {
        let show: Presence.Show?;
        let message: String?;
        
        required convenience init(from dict: [String: Any?]) {
            let message = dict["message"] as? String;
            let showStr = dict["show"] as? String;
            self.init(show: showStr != nil ? Presence.Show(rawValue: showStr!) : nil, message: message);
        }
        
        init(show: Presence.Show?, message: String?) {
            self.show = show;
            self.message = message;
        }
        
        func with(show: Presence.Show?) -> Status {
            return Status(show: show, message: self.message);
        }
        
        func with(message: String?) -> Status {
            return Status(show: self.show, message: message);
        }

        func with(show: Presence.Show?, message: String?) -> Status {
            return Status(show: show, message: message);
        }

        func toDict() -> [String : Any?] {
            var dict: [String: Any?] = [:];
            if message != nil {
                dict["message"] = message;
            }
            if show != nil {
                dict["show"] = show?.rawValue;
            }
            return dict;
        }
    }
}
