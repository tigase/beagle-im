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
import Martin
import MartinOMEMO
import Combine
import TigaseLogging

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

class XmppService {
    
    static let AUTHENTICATION_ERROR = Notification.Name("authenticationError");
    static let SERVER_CERTIFICATE_ERROR = Notification.Name("serverCertificateError");
    
    static let instance = XmppService();
 
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: String(describing: XmppService.self));
    
    let extensions: [XmppServiceExtension] = [MessageEventHandler.instance, BlockedEventHandler.instance, PresenceRosterEventHandler.instance, AvatarEventHandler.instance, MixEventHandler.instance, MucEventHandler.instance, MeetEventHandler.instance];
    
    var clients: [BareJID: XMPPClient] {
        get {
            return queue.sync {
                return _clients;
            }
        }
    }

    
    fileprivate var _clients = [BareJID: XMPPClient]();
    
    fileprivate let queue = DispatchQueue(label: "xmpp_service");
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
                self?.logger.debug("connecting all clients..")
                self?.connectClients(ignoreCheck: true);
            } else {
                self?.logger.debug("disconnecting all clients..")
                self?.disconnectClients(force: !NetworkMonitor.shared.isNetworkAvailable);
            }
        }).store(in: &cancellables);
        expectedStatus.receive(on: self.queue).sink(receiveValue: { [weak self] status in self?.statusUpdated(status) }).store(in: &cancellables);
        expectedStatus.combineLatest($connectedClients.map({ !$0.isEmpty })).map({ status, connected in
            if !connected {
                return status.with(show: nil);
            }
            return status;
        }).sink(receiveValue: { [weak self] status in self?.currentStatus = status }).store(in: &cancellables);
        
        AccountManager.accountEventsPublisher.receive(on: self.queue).sink(receiveValue: { [weak self] event in
            self?.accountChanged(event: event);
        }).store(in: &cancellables);
    }
    
    private func accountChanged(event: AccountManager.Event) {
        switch event {
        case .enabled(let account, let reconnect):
            guard reconnect else {
                return;
            }
            if let client = self._clients[account.name] {
                // if client exists and is connected, then reconnect it..
                if client.state != .disconnected() {
                    Task {
                        try await client.disconnect();
                    }
                }
            } else {
                let client = self.initializeClient(for: account);
                _ = self.register(client: client, for: account);
                self.connect(client: client, for: account);
            }
        case .disabled(let account), .removed(let account):
            if let client = self._clients[account.name] {
                let prevState = client.state;
                Task {
                    try await client.disconnect();
                }
                if prevState == .disconnected() && client.state == .disconnected() {
                    self.unregisterClient(client);
                }
            }
            self.dnsCache.store(for: account.name.domain, result: nil);
        }
    }

    
    func initialize() {
        for account in AccountManager.activeAccounts() {
            let client = self.initializeClient(for: account);
            self.queue.sync {
                _ = self.register(client: client, for: account);
            }
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
                if client.isConnected {
                    client.module(.presence).setPresence(show: show, status: status.message, priority: nil);
                }
            }
        }
    }
        
    func getClient(for account: BareJID) -> XMPPClient? {
        return queue.sync {
            return _clients[account];
        }
    }
    
    private func connectClients(ignoreCheck: Bool) {
        queue.async {
            self._clients.values.forEach { client in
                self.reconnect(client: client, ignoreCheck: ignoreCheck);
            }
        }
    }
    
    private func disconnectClients(force: Bool = false) {
        queue.async {
            self._clients.values.forEach { client in
                Task {
                    try await client.disconnect(force: force);
                }
            }
        }
    }
    
    fileprivate func sendKeepAlive() {
        queue.async {
            self._clients.values.forEach { client in
                client.keepalive();
            }
        }
    }
    
    private func reconnect(client: XMPPClient, ignoreCheck: Bool = false) {
        self.queue.sync {
            guard client.state == .disconnected(), let account = AccountManager.account(for: client.userBareJid), account.enabled, ignoreCheck || (self.expectedStatus.value.show != nil)  else {
                return;
            }
            
            self.connect(client: client, for: account);
        }
    }
    
    private func connect(client: XMPPClient, for account: Account) {
        client.configure(for: account);

        switch account.additional.resourceType {
        case .automatic:
            client.connectionConfiguration.resource = nil;
        case .hostname:
            client.connectionConfiguration.resource = Host.current().localizedName;
        case .manual(let resource):
            client.connectionConfiguration.resource = resource;
        }
        
        try! client.login(lastSeeOtherHost: account.lastEndpoint);
    }
    
    private class ClientCancellables {
        var cancellables: Set<AnyCancellable> = [];
    }

    private var clientCancellables: [BareJID:ClientCancellables] = [:];
    
    private func disconnected(client: XMPPClient) {
        let accountName = client.userBareJid;
        defer {
            DBChatStore.instance.resetChatStates(for: accountName);
        }
        self.queue.sync {
            let active = AccountManager.account(for: accountName)?.enabled
            if !(active ?? false) {
                self.unregisterClient(client, removed: active == nil);
            }
        }
        
        
        guard self.expectedStatus.value.show != nil else {
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
        let accountName = client.userBareJid;
        guard let client = self._clients.removeValue(forKey: accountName) else {
            return;
        }

        self.clientCancellables.removeValue(forKey: accountName);
            
        queue.async {
            if removed {
                DBRosterStore.instance.clear(for: client)
                DBChatStore.instance.closeAll(for: accountName);
                DBChatHistoryStore.instance.removeHistory(for: accountName, with: nil);
                _ = client;
            }
        }
    }
    
    fileprivate func initializeClient(for account: Account) -> XMPPClient {
        let jid = account.name;
        let client = XMPPClient();
        client.connectionConfiguration.modifyConnectorOptions(type: SocketConnectorNetwork.Options.self, { options in
            options.dnsResolver = DNSSrvResolverWithCache(resolver: XMPPDNSSrvResolver(directTlsEnabled: true), cache: self.dnsCache);
            options.networkProcessorProviders.append(SSLProcessorProvider());
            options.connectionTimeout = 15.0;
        })
        client.connectionConfiguration.userJid = jid;
        
        _ = client.modulesManager.register(AuthModule());
        _ = client.modulesManager.register(StreamFeaturesModule());
        _ = client.modulesManager.register(StreamManagementModule(mode: .resumption, maxResumptionTimeout: 90));
        _ = client.modulesManager.register(SaslModule());
        let sasl2 = client.modulesManager.register(Sasl2Module());
        sasl2.software = Bundle.main.infoDictionary!["CFBundleName"] as! String;
        //_ = client.modulesManager.register(StreamFeaturesModuleWithPipelining(cache: streamFeaturesCache, enabled: false));
        // if you do not want Pipelining you may use StreamFeaturesModule instead StreamFeaturesModuleWithPipelining
        _ = client.modulesManager.register(ResourceBinderModule());
        _ = client.modulesManager.register(SessionEstablishmentModule());
        _ = client.modulesManager.register(DiscoveryModule(identity: DiscoveryModule.Identity(category: "client", type: "pc", name: Bundle.main.infoDictionary!["CFBundleName"] as! String)));
        _ = client.modulesManager.register(SoftwareVersionModule(version: SoftwareVersionModule.SoftwareVersion(name: Bundle.main.infoDictionary!["CFBundleName"] as! String, version: "\(Bundle.main.infoDictionary!["CFBundleShortVersionString"] as! String) b\(Bundle.main.infoDictionary!["CFBundleVersion"] as! String)", os: "macOS")));
        
        _ = client.modulesManager.register(RosterModule(rosterManager: RosterManagerBase(store: DBRosterStore.instance)));

        _ = client.modulesManager.register(VCardTempModule());
        _ = client.modulesManager.register(VCard4Module());
        _ = client.modulesManager.register(PingModule());
        _ = client.modulesManager.register(BlockingCommandModule());
        
        _ = client.modulesManager.register(PubSubModule());
        _ = client.modulesManager.register(PEPUserAvatarModule());
        _ = client.modulesManager.register(PEPBookmarksModule());

        _ = client.modulesManager.register(HttpFileUploadModule());

        let messageModule = MessageModule(chatManager: ChatManagerBase(store: DBChatStore.instance));
        _ = client.modulesManager.register(messageModule);
        
        _ = client.modulesManager.register(MessageCarbonsModule());
        _ = client.modulesManager.register(MessageArchiveManagementModule());

        client.modulesManager.register(MessageDeliveryReceiptsModule()).sendReceived = false;
        _ = client.modulesManager.register(ChatMarkersModule());

        _ = client.modulesManager.register(MeetModule());
                
        _ = client.modulesManager.register(PresenceModule(store: PresenceStore.instance));
        client.modulesManager.register(CapabilitiesModule(cache: DBCapabilitiesCache.instance, additionalFeatures: [.lastMessageCorrection, .messageRetraction]));

        client.modulesManager.register(CustomMucModule(roomManager: RoomManagerBase(store: DBChatStore.instance)));
                                           
        client.modulesManager.register(MixModule(channelManager: ChannelManagerBase(store: DBChatStore.instance)));
        
        _ = client.modulesManager.register(AdHocCommandsModule());
        
        let jingleModule = client.modulesManager.register(JingleModule(sessionManager: JingleManager.instance, supportsMessageInitiation: true));
        jingleModule.register(transport: Jingle.Transport.ICEUDPTransport.self, features: [Jingle.Transport.ICEUDPTransport.XMLNS, "urn:xmpp:jingle:apps:dtls:0"]);
        jingleModule.register(description: Jingle.RTP.Description.self, features: ["urn:xmpp:jingle:apps:rtp:1", "urn:xmpp:jingle:apps:rtp:audio", "urn:xmpp:jingle:apps:rtp:video"]);
        _ = client.modulesManager.register(ExternalServiceDiscoveryModule());
        
        _ = client.modulesManager.register(InBandRegistrationModule());
        
        let signalStorage = OMEMOStoreWrapper(context: client.context);
        let signalContext = SignalContext(withStorage: signalStorage)!;
        _ = client.modulesManager.register(OMEMOModule(signalContext: signalContext, signalStorage: signalStorage));
        
        XMLConsoleViewController.configureLogging(for: client);
        
        return client;
    }

    fileprivate func register(client: XMPPClient, for account: Account) -> XMPPClient {
        let clientCancellables = ClientCancellables();
        self.clientCancellables[account.name] = clientCancellables;
            
        client.$state.subscribe(account.state).store(in: &clientCancellables.cancellables);
        client.$state.dropFirst().sink(receiveValue: { state in self.changedState(state, for: client) }).store(in: &clientCancellables.cancellables);
            
        MucEventHandler.instance.register(for: client, cancellables: &clientCancellables.cancellables);
            
        for ext in extensions {
            ext.register(for: client, cancellables: &clientCancellables.cancellables);
        }
            
        self._clients[account.name] = client;
        return client;
    }
    
    private func changedState(_ state: XMPPClient.State, for client: XMPPClient) {
        switch state {
        case .connected:
            self.queue.async {
                self.connectedClients.insert(client);
            }
        case .disconnected(let reason):
            self.queue.async {
                self.connectedClients.remove(client);
            }
            try? AccountManager.modifyAccount(for: client.userBareJid, { $0.lastEndpoint = nil })
            switch reason {
            case .sslCertError(let trust):
                if let certData = SSLCertificateInfo(trust: trust) {
                    try? AccountManager.modifyAccount(for: client.userBareJid, { account in
                        account.enabled = false;
                        account.acceptedCertificate = AcceptableServerCertificate(certificate: certData, accepted: false);
                    })
                    NotificationCenter.default.post(name: XmppService.SERVER_CERTIFICATE_ERROR, object: client.userBareJid);
                }
            case .authenticationFailure(let err):
                if let error = err as? SaslError {
                    switch error {
                    case .aborted, .temporary_auth_failure:
                        // those are temporary errors, we shoud retry
                        break;
                    default:
                        reportSaslError(on: client.userBareJid, error: error);
                    }
                } else {
                    reportSaslError(on: client.userBareJid, error: .not_authorized);
                }
            case .none:
                try? AccountManager.modifyAccount(for: client.userBareJid, {
                    $0.lastEndpoint = client.connector?.currentEndpoint as? SocketConnectorNetwork.Endpoint
                })
            default:
                break;
            }
            self.disconnected(client: client);
        default:
            break;
        }
    }
    
    private func reportSaslError(on accountJID: BareJID, error: SaslError) {
        try? AccountManager.modifyAccount(for: accountJID, { account in
            account.enabled = false;
        })
        NotificationCenter.default.post(name: XmppService.AUTHENTICATION_ERROR, object: accountJID, userInfo: ["error": error]);
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
