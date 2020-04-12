//
// XmppService.swift
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
import TigaseSwiftOMEMO

class XmppService: EventHandler {
    
    static let AUTHENTICATION_ERROR = Notification.Name("authenticationError");
    static let CONTACT_PRESENCE_CHANGED = Notification.Name("contactPresenceChanged");
    static let STATUS_CHANGED = Notification.Name("statusChanged");
    static let ACCOUNT_STATUS_CHANGED = Notification.Name("accountStatusChanged");
    static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    
    static let instance = XmppService();
 
    fileprivate let observedEvents: [Event] = [ SessionEstablishmentModule.SessionEstablishmentSuccessEvent.TYPE, SocketConnector.DisconnectedEvent.TYPE, StreamManagementModule.ResumedEvent.TYPE, SocketConnector.CertificateErrorEvent.TYPE, AuthModule.AuthFailedEvent.TYPE ];
    
    fileprivate let eventHandlers: [XmppServiceEventHandler] = [MucEventHandler.instance, PresenceRosterEventHandler(), AvatarEventHandler(), MessageEventHandler(), HttpFileUploadEventHandler(), JingleManager.instance, BlockedEventHandler.instance, MixEventHandler.instance];
    
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
    fileprivate let dnsCache: DNSSrvResolverCache = DNSSrvResolverWithCache.InMemoryCache(store: nil);
    var isAwake: Bool = true {
        didSet {
            if !isAwake {
                self.isNetworkAvailable = false;
            } else {
                self.isNetworkAvailable = self.reachability.isConnectedToNetwork();
            }
        }
    }

    fileprivate var nonIdleStatus: Status? = nil;
    var isIdle: Bool = false {
        didSet {
            if isIdle && Settings.enableAutomaticStatus.bool() {
                nonIdleStatus = status;
                status = status.with(show: .xa);
            } else if let restoreStatus = nonIdleStatus {
                status = restoreStatus;
            }
        }
    }
    
    fileprivate(set) var isNetworkAvailable: Bool = false {
        didSet {
            if isNetworkAvailable {
                if !oldValue {
                    connectClients();
                } else {
                    sendKeepAlive();
                }
            } else {
                disconnectClients(force: isAwake);
            }
        }
    }

    var status: Status = Status(show: nil, message: nil) {
        didSet {
            if Settings.rememberLastStatus.bool() {
                Settings.currentStatus.set(value: status);
            }
            guard isNetworkAvailable else {
                return;
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
            if oldValue != currentStatus {
                NotificationCenter.default.post(name: XmppService.STATUS_CHANGED, object: currentStatus);
            }
        }
    }
    
    let tasksQueue = KeyedTasksQueue();
    
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
        case let e as StreamManagementModule.ResumedEvent:
            updateCurrentStatus();
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATUS_CHANGED, object: e.sessionObject.userBareJid);
        case let e as SessionEstablishmentModule.SessionEstablishmentSuccessEvent:
            //test(e.sessionObject);
            print("account", e.sessionObject.userBareJid!, "is now connected!");
            self.updateCurrentStatus();
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATUS_CHANGED, object: e.sessionObject.userBareJid);
            break;
        case let e as AuthModule.AuthFailedEvent:
            guard let accountName = e.sessionObject.userBareJid else {
                return;
            }
            switch e.error! {
            case .aborted, .temporary_auth_failure:
                // those are temporary errors, we shoud retry
                return;
            default:
                break;
            }
            
            guard let account = AccountManager.getAccount(for: accountName) else {
                return;
            }
            account.active = false;
            _ = AccountManager.save(account: account);
            NotificationCenter.default.post(name: XmppService.AUTHENTICATION_ERROR, object: accountName, userInfo: ["error": e.error ?? SaslError.not_authorized]);
        case let e as SocketConnector.CertificateErrorEvent:
            let certData = ServerCertificateInfo(trust: e.trust);
            
            if let accountName = e.sessionObject.userBareJid, let account = AccountManager.getAccount(for: accountName) {
                account.active = false;
                account.serverCertificate = certData;
                _ = AccountManager.save(account: account);
                NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: accountName);
            }
        case let e as SocketConnector.DisconnectedEvent:
            print("##### \(e.sessionObject.userBareJid!.stringValue) - disconnected", Date());
            updateCurrentStatus();
            NotificationCenter.default.post(name: XmppService.ACCOUNT_STATUS_CHANGED, object: e.sessionObject.userBareJid);

            if let client = self.getClient(for: e.sessionObject.userBareJid!) {
                self.disconnected(client: client);
            }
        default:
            break;
        }
    }
    
    fileprivate func connect(client: XMPPClient) {
        guard let account = AccountManager.getAccount(for: client.sessionObject.userBareJid!), account.active, self.isNetworkAvailable, self.status.show != nil  else {
            return;
        }
        
        client.connectionConfiguration.setUserPassword(account.password);
        SslCertificateValidator.setAcceptedSslCertificate(client.sessionObject, fingerprint: (account.serverCertificate?.accepted ?? false) ? account.serverCertificate?.details.fingerprintSha1 : nil);

        switch account.resourceType {
        case .automatic:
            client.sessionObject.setUserProperty(SessionObject.RESOURCE, value: nil);
        case .hostname:
            client.sessionObject.setUserProperty(SessionObject.RESOURCE, value: Host.current().localizedName);
        case .custom:
            let val = account.resourceName;
            client.sessionObject.setUserProperty(SessionObject.RESOURCE, value: (val == nil || val!.isEmpty) ? nil : val)
        }
        
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
                let prevState = client.state;
                client.disconnect();
                if prevState == .disconnected && client.state == .disconnected {
                    self.unregisterClient(client);
                }
            }
            return;
        }
        
        dispatcher.sync {
            if let client = self._clients[account.name] {
                client.connectionConfiguration.setUserPassword(account.password);
                client.disconnect();
            } else {
                let client = self.register(client: self.initializeClient(jid: account.name)!, for: account.name);
                if self.isNetworkAvailable {
                    DispatchQueue.global().async {
                        self.connect(client: client);
                    }
                }
            }
        }
    }
    
    private func disconnected(client: XMPPClient) {
        let accountName = client.sessionObject.userBareJid!;
        self.dispatcher.sync {
            let active = AccountManager.getAccount(for: accountName)?.active
            if !(active ?? false) {
                self.unregisterClient(client, removed: active == nil);
            }
        }
        guard self.status.show != nil || !self.isNetworkAvailable else {
            return;
        }
        DBChatStore.instance.resetChatStates(for: accountName);
        let retry = client.retryNo;
        client.retryNo = retry + 1;
        var timeout = 2.0 * Double(retry) + 0.5;
        if timeout > 16 {
            timeout = 15;
        }
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + timeout) { [weak client] in
            if let c = client {
                self.connect(client: c);
            }
        }
    }
    
    private func unregisterClient(_ client: XMPPClient, removed: Bool = false) {
        dispatcher.sync {
            let accountName = client.sessionObject.userBareJid!;
            guard let client = self._clients.removeValue(forKey: accountName) else {
                return;
            }

            if let messageModule: MessageModule = client.modulesManager.getModule(MessageModule.ID) {
                ((messageModule.chatManager as! DefaultChatManager).chatStore as! DBChatStoreWrapper).deinitialize();
            }
            if let mucModule: MucModule = client.modulesManager.getModule(MucModule.ID) {
                (mucModule.roomsManager.store as! DBRoomStore).deinitialize();
            }
            if let mixModule: MixModule = client.modulesManager.getModule(MixModule.ID) {
                ((mixModule.channelManager as! DefaultChannelManager).store as! DBChannelStore).deinitialize();
            }
            
            if removed {
                DBRosterStore.instance.removeAll(for: accountName);
                DBChatStore.instance.closeAll(for: accountName);
                DBChatHistoryStore.instance.removeHistory(for: accountName, with: nil);
            }

            client.eventBus.unregister(handler: self, for: self.observedEvents);
            self.eventHandlers.forEach { handler in
                client.eventBus.unregister(handler: handler, for: handler.events);
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
        client.sessionObject.dnsSrvResolver = DNSSrvResolverWithCache(resolver: XMPPDNSSrvResolver(), cache: self.dnsCache);
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
        _ = client.modulesManager.register(PingModule());
        _ = client.modulesManager.register(BlockingCommandModule());
        
        client.modulesManager.register(CapabilitiesModule()).cache = DBCapabilitiesCache.instance;
        _ = client.modulesManager.register(PubSubModule());
        _ = client.modulesManager.register(PEPUserAvatarModule());
        _ = client.modulesManager.register(PEPBookmarksModule());
        
        let messageModule = MessageModule();
        let chatStoreWrapper = DBChatStoreWrapper(sessionObject: client.context.sessionObject);
        chatStoreWrapper.initialize();
        messageModule.chatManager = DefaultChatManager(context: client.context, chatStore: chatStoreWrapper);
        _ = client.modulesManager.register(messageModule);
        
        _ = client.modulesManager.register(MessageCarbonsModule());
        _ = client.modulesManager.register(MessageDeliveryReceiptsModule());
        _ = client.modulesManager.register(MessageArchiveManagementModule());
        
        _ = client.modulesManager.register(HttpFileUploadModule());
        
        let rosterStoreWrapper = DBRosterStoreWrapper(sessionObject: client.context.sessionObject);
        rosterStoreWrapper.initialize();
        client.context.sessionObject.setUserProperty(RosterModule.ROSTER_STORE_KEY, value: rosterStoreWrapper);
        _ = client.modulesManager.register(RosterModule());
        
        _ = client.modulesManager.register(PresenceModule());
        
        let roomStore = DBRoomStore(sessionObject: client.context.sessionObject);
        client.modulesManager.register(MucModule(roomsManager: DefaultRoomsManager(store: roomStore)));
        roomStore.initialize();
    
        let channelStore = DBChannelStore(sessionObject: client.context.sessionObject);
        client.modulesManager.register(MixModule(channelManager: DefaultChannelManager(context: client.context, store: channelStore)));
        channelStore.initialize();
        
        _ = client.modulesManager.register(AdHocCommandsModule());
        
        let jingleModule = client.modulesManager.register(JingleModule(sessionManager: JingleManager.instance));
        jingleModule.register(transport: Jingle.Transport.ICEUDPTransport.self, features: [Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:dtls:0"]);
        jingleModule.register(description: Jingle.RTP.Description.self, features: ["urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"]);
        
        _ = client.modulesManager.register(InBandRegistrationModule());
        
        let signalStorage = OMEMOStoreWrapper(context: client.context);
        let signalContext = SignalContext(withStorage: signalStorage)!;
        signalStorage.setup(withContext: signalContext);
        _ = client.modulesManager.register(OMEMOModule(aesGCMEngine: OpenSSL_AES_GCM_Engine(), signalContext: signalContext, signalStorage: signalStorage));
        
        client.modulesManager.initIfRequired();
        
        SslCertificateValidator.registerSslCertificateValidator(client.sessionObject);
        
        client.sessionObject.setUserProperty(SoftwareVersionModule.NAME_KEY, value: Bundle.main.infoDictionary!["CFBundleName"]);
        let version = "\(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String) b\(Bundle.main.infoDictionary!["CFBundleVersion"] as! String)";
        client.sessionObject.setUserProperty(SoftwareVersionModule.VERSION_KEY, value: version);
        client.sessionObject.setUserProperty(SoftwareVersionModule.OS_KEY, value: "macOS");
        
        XMLConsoleViewController.configureLogging(for: client);
        
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
    
    class Status: CustomDictionaryConvertible, Equatable {
        static func == (lhs: XmppService.Status, rhs: XmppService.Status) -> Bool {
            if (lhs.show == nil && rhs.show == nil) {
                return (lhs.message ?? "") == (rhs.message ?? "");
            } else if let ls = lhs.show, let rs = rhs.show {
                return ls == rs && (lhs.message ?? "") == (rhs.message ?? "");
            } else {
                return false;
            }
        }
        
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
