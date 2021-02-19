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
import Combine

extension Presence.Show: Codable {
    
}

extension XMPPClient: Hashable {
    
    public static func == (lhs: XMPPClient, rhs: XMPPClient) -> Bool {
        return lhs.connectionConfiguration.userJid == rhs.connectionConfiguration.userJid;
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(connectionConfiguration.userJid);
    }
    
}

class XmppService: EventHandler {
    
    static let AUTHENTICATION_ERROR = Notification.Name("authenticationError");
    static let CONTACT_PRESENCE_CHANGED = Notification.Name("contactPresenceChanged");
//    static let ACCOUNT_STATUS_CHANGED = Notification.Name("accountStatusChanged");
    static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    
    static let instance = XmppService();
 
    fileprivate let observedEvents: [Event] = [ AuthModule.AuthFailedEvent.TYPE ];
    
    fileprivate let eventHandlers: [XmppServiceEventHandler] = [MucEventHandler.instance, PresenceRosterEventHandler(), AvatarEventHandler(), MessageEventHandler(), JingleManager.instance, BlockedEventHandler.instance, MixEventHandler.instance];
    
    var clients: [BareJID: XMPPClient] {
        get {
            return dispatcher.sync {
                return _clients;
            }
        }
    }

    
    fileprivate var _clients = [BareJID: XMPPClient]();
    
    fileprivate let dispatcher = QueueDispatcher(label: "xmpp_service");
    fileprivate let dnsCache: DNSSrvResolverCache = DNSSrvResolverWithCache.InMemoryCache(store: nil);
    @Published
    var isAwake: Bool = true;

    @Published
    var isIdle: Bool = false
    
    @Published
    var status: Status = Status(show: .online, message: nil);
    
    public let expectedStatus = CurrentValueSubject<Status,Never>(Status(show: nil, message: nil));
    
    @Published
    fileprivate(set) var currentStatus: Status = Status(show: nil, message: nil);
    
    let tasksQueue = KeyedTasksQueue();
    
    @Published
    public private(set) var connectedClients: Set<XMPPClient> = [];
    
    private var cancellables: Set<AnyCancellable> = [];
    
    init() {
        expectedStatus.map({ status in
                            return status.show != nil
        }).removeDuplicates().sink(receiveValue: { [weak self] available in
            if available {
                self?.connectClients(ignoreCheck: true);
            } else {
                self?.disconnectClients(force: !NetworkMonitor.shared.isNetworkAvailable);
            }
        }).store(in: &cancellables);
        expectedStatus.receive(on: self.dispatcher.queue).sink(receiveValue: { [weak self] status in self?.statusUpdated(status) }).store(in: &cancellables);
        expectedStatus.combineLatest($connectedClients.map({ !$0.isEmpty })).map({ status, connected in
            if !connected {
                return status.with(show: nil);
            }
            return status;
        }).sink(receiveValue: { [weak self] status in self?.currentStatus = status }).store(in: &cancellables);
        
        AccountManager.accountEventsPublisher.receive(on: self.dispatcher.queue).sink(receiveValue: { [weak self] event in
            self?.accountChanged(event: event);
        }).store(in: &cancellables);
    }
    
    private func accountChanged(event: AccountManager.Event) {
        switch event {
        case .enabled(let account):
            if let client = self._clients[account.name] {
                // if client exists and is connected, then reconnect it..
                if client.state != .disconnected() {
                    client.disconnect();
                }
            } else {
                let client = self.initializeClient(for: account);
                _ = self.register(client: client, for: account);
                self.connect(client: client, for: account);
            }
        case .disabled(let account), .removed(let account):
            if let client = self._clients[account.name] {
                let prevState = client.state;
                client.disconnect();
                if prevState == .disconnected() && client.state == .disconnected() {
                    self.unregisterClient(client);
                }
            }
        }
    }

    
    func initialize() {
        for account in AccountManager.getActiveAccounts() {
            let client = self.initializeClient(for: account);
            _ = self.register(client: client, for: account);
        }
        self.$status.combineLatest($isIdle, { (status, idle) -> Status in
            if idle && status.show != nil {
                return status.with(show: .xa);
            }
            return status;
        }).combineLatest(NetworkMonitor.shared.$isNetworkAvailable, $isAwake, { (status, networkAvailble, isAwake) -> Status in
            if networkAvailble && isAwake {
                return status;
            } else {
                return status.with(show: nil);
            }
        }).assign(to: \.value, on: expectedStatus).store(in: &cancellables);
    }
 
    private func statusUpdated(_ status: Status) {
        if let show = status.show {
            self._clients.values.forEach { client in
                if client.state == .connected {
                    client.module(.presence).setPresence(show: show, status: status.message, priority: nil);
                }
            }
        }
    }
        
    func getClient(for account: BareJID) -> XMPPClient? {
        return dispatcher.sync {
            return _clients[account];
        }
    }
    
    private func connectClients(ignoreCheck: Bool) {
        dispatcher.async {
            self._clients.values.forEach { client in
                self.reconnect(client: client, ignoreCheck: ignoreCheck);
            }
        }
    }
    
    private func disconnectClients(force: Bool = false) {
        dispatcher.async {
            self._clients.values.forEach { client in
                client.disconnect(force);
            }
        }
    }
    
    fileprivate func sendKeepAlive() {
        dispatcher.async {
            self._clients.values.forEach { client in
                client.keepalive();
            }
        }
    }
    
    func handle(event: Event) {
        switch event {
        case let e as AuthModule.AuthFailedEvent:
            guard let accountName = e.sessionObject.userBareJid else {
                return;
            }
            if let error = e.error as? SaslError {
                switch error {
                case .aborted, .temporary_auth_failure:
                    // those are temporary errors, we shoud retry
                    return;
                default:
                    break;
                }
            }
            
            guard var account = AccountManager.getAccount(for: accountName) else {
                return;
            }
            account.active = false;
            _ = AccountManager.save(account: account);
            NotificationCenter.default.post(name: XmppService.AUTHENTICATION_ERROR, object: accountName, userInfo: ["error": e.error ?? SaslError.not_authorized]);
        default:
            break;
        }
    }
    
    private func reconnect(client: XMPPClient, ignoreCheck: Bool = false) {
        self.dispatcher.sync {
            guard client.state == .disconnected(), let account = AccountManager.getAccount(for: client.userBareJid), account.active, ignoreCheck || ( NetworkMonitor.shared.isNetworkAvailable && self.status.show != nil)  else {
                return;
            }
            
            self.connect(client: client, for: account);
        }
    }
    
    private func connect(client: XMPPClient, for account: AccountManager.Account) {
        client.connectionConfiguration.credentials = .password(password: account.password!, authenticationName: nil, cache: nil);
        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            if let serverCertificate = account.serverCertificate, serverCertificate.accepted {
                options.sslCertificateValidation = .fingerprint(serverCertificate.details.fingerprintSha1);
            } else {
                options.sslCertificateValidation = .default;
            }
        });

        switch account.resourceType {
        case .automatic:
            client.connectionConfiguration.resource = nil;
        case .hostname:
            client.connectionConfiguration.resource = Host.current().localizedName;
        case .custom:
            let val = account.resourceName;
            client.connectionConfiguration.resource = (val == nil || val!.isEmpty) ? nil : val;
        }
        
        client.login();
    }
    
    private class ClientCancellables {
        var cancellables: Set<AnyCancellable> = [];
    }

    private var clientCancellables: [BareJID:ClientCancellables] = [:] {
        didSet {
            print("updated client cancellables to:", clientCancellables);
        }
    }
    
    private func disconnected(client: XMPPClient) {
        let accountName = client.sessionObject.userBareJid!;
        defer {
            DBChatStore.instance.resetChatStates(for: accountName);
        }
        self.dispatcher.sync {
            let active = AccountManager.getAccount(for: accountName)?.active
            if !(active ?? false) {
                self.unregisterClient(client, removed: active == nil);
            }
        }
        
        
        guard self.status.show != nil || !NetworkMonitor.shared.isNetworkAvailable else {
            return;
        }
        let retry = client.retryNo;
        client.retryNo = retry + 1;
        var timeout = 2.0 * Double(retry) + 0.5;
        if timeout > 16 {
            timeout = 15;
        }
        DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + timeout) { [weak client] in
            if let c = client {
                self.reconnect(client: c);
            }
        }
    }
    
    private func unregisterClient(_ client: XMPPClient, removed: Bool = false) {
        dispatcher.sync {
            let accountName = client.sessionObject.userBareJid!;
            guard let client = self._clients.removeValue(forKey: accountName) else {
                return;
            }

            self.clientCancellables.removeValue(forKey: accountName);
            
            client.eventBus.unregister(handler: self, for: self.observedEvents);
            self.eventHandlers.forEach { handler in
                client.eventBus.unregister(handler: handler, for: handler.events);
            }
            dispatcher.async {
                if removed {
                    DBRosterStore.instance.clear(for: client)
                    DBChatStore.instance.closeAll(for: accountName);
                    DBChatHistoryStore.instance.removeHistory(for: accountName, with: nil);
                    _ = client;
                }
            }
        }
    }
    
    fileprivate func initializeClient(for account: AccountManager.Account) -> XMPPClient {
        let jid = account.name;
        let client = XMPPClient();
        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            options.dnsResolver = DNSSrvResolverWithCache(resolver: XMPPDNSSrvResolver(), cache: self.dnsCache);
            options.networkProcessorProviders.append(SSLProcessorProvider());
        })
        client.connectionConfiguration.userJid = jid;
        
        _ = client.modulesManager.register(StreamFeaturesModule());
        _ = client.modulesManager.register(StreamManagementModule());
        _ = client.modulesManager.register(SaslModule());
        _ = client.modulesManager.register(AuthModule());
        //_ = client.modulesManager.register(StreamFeaturesModuleWithPipelining(cache: streamFeaturesCache, enabled: false));
        // if you do not want Pipelining you may use StreamFeaturesModule instead StreamFeaturesModuleWithPipelining
        _ = client.modulesManager.register(ResourceBinderModule());
        _ = client.modulesManager.register(SessionEstablishmentModule());
        _ = client.modulesManager.register(DiscoveryModule(identity: DiscoveryModule.Identity(category: "client", type: "pc", name: Bundle.main.infoDictionary!["CFBundleName"] as! String)));
        _ = client.modulesManager.register(SoftwareVersionModule(version: SoftwareVersionModule.SoftwareVersion(name: Bundle.main.infoDictionary!["CFBundleName"] as! String, version: "\(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String) b\(Bundle.main.infoDictionary!["CFBundleVersion"] as! String)", os: "macOS")));
        _ = client.modulesManager.register(VCardTempModule());
        _ = client.modulesManager.register(VCard4Module());
        _ = client.modulesManager.register(PingModule());
        _ = client.modulesManager.register(BlockingCommandModule());
        
        _ = client.modulesManager.register(PubSubModule());
        _ = client.modulesManager.register(PEPUserAvatarModule());
        _ = client.modulesManager.register(PEPBookmarksModule());
        
        let messageModule = MessageModule(chatManager: ChatManagerBase(store: DBChatStore.instance));
        _ = client.modulesManager.register(messageModule);
        
        _ = client.modulesManager.register(MessageCarbonsModule());
        _ = client.modulesManager.register(MessageDeliveryReceiptsModule());
        _ = client.modulesManager.register(MessageArchiveManagementModule());
        
        _ = client.modulesManager.register(HttpFileUploadModule());
        
        _ = client.modulesManager.register(RosterModule(rosterManager: RosterManagerBase(store: DBRosterStore.instance)));
        
        _ = client.modulesManager.register(PresenceModule(store: PresenceStore.instance));
        client.modulesManager.register(CapabilitiesModule(cache: DBCapabilitiesCache.instance, additionalFeatures: [.lastMessageCorrection, .messageRetraction]));

        client.modulesManager.register(MucModule(roomManager: RoomManagerBase(store: DBChatStore.instance)));
                                           
        client.modulesManager.register(MixModule(channelManager: ChannelManagerBase(store: DBChatStore.instance)));
        
        _ = client.modulesManager.register(AdHocCommandsModule());
        
        let jingleModule = client.modulesManager.register(JingleModule(sessionManager: JingleManager.instance));
        jingleModule.register(transport: Jingle.Transport.ICEUDPTransport.self, features: [Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:dtls:0"]);
        jingleModule.register(description: Jingle.RTP.Description.self, features: ["urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"]);
        jingleModule.supportsMessageInitiation = true;
        _ = client.modulesManager.register(ExternalServiceDiscoveryModule());
        
        _ = client.modulesManager.register(InBandRegistrationModule());
        
        let signalStorage = OMEMOStoreWrapper(context: client.context);
        let signalContext = SignalContext(withStorage: signalStorage)!;
        signalStorage.setup(withContext: signalContext);
        _ = client.modulesManager.register(OMEMOModule(aesGCMEngine: OpenSSL_AES_GCM_Engine(), signalContext: signalContext, signalStorage: signalStorage));
        
        XMLConsoleViewController.configureLogging(for: client);
        
        return client;
    }

    fileprivate func register(client: XMPPClient, for account: AccountManager.Account) -> XMPPClient {
        return dispatcher.sync {
            let clientCancellables = ClientCancellables();
            self.clientCancellables[account.name] = clientCancellables;
            
            client.$state.subscribe(account.state).store(in: &clientCancellables.cancellables);
            client.$state.dropFirst().sink(receiveValue: { state in self.changedState(state, for: client) }).store(in: &clientCancellables.cancellables);

            client.eventBus.register(handler: self, for: observedEvents);
            
            MessageEventHandler.register(for: client, cancellables: &clientCancellables.cancellables)
            
            eventHandlers.forEach { handler in
                client.eventBus.register(handler: handler, for: handler.events);
            }
        
            self._clients[account.name] = client;
            return client;
        }
    }
    
    private func changedState(_ state: ConnectorState, for client: XMPPClient) {
        switch state {
        case .connected:
            self.dispatcher.async {
                self.connectedClients.insert(client);
            }
        case .disconnected(let reason):
            self.dispatcher.async {
                self.connectedClients.remove(client);
            }
            switch reason {
            case .sslCertError(let trust):
                let certData = ServerCertificateInfo(trust: trust);
                if var account = AccountManager.getAccount(for: client.userBareJid) {
                    account.active = false;
                    account.serverCertificate = certData;
                    _ = AccountManager.save(account: account);
                    NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: client.userBareJid);
                }
            default:
                break;
            }
            self.disconnected(client: client);
        default:
            break;
        }
    }
    
    struct Status: Codable, Equatable {
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
        
        
//        required convenience init(from dict: [String: Any?]) {
//            let message = dict["message"] as? String;
//            let showStr = dict["show"] as? String;
//            self.init(show: showStr != nil ? Presence.Show(rawValue: showStr!) : nil, message: message);
//        }
        
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
