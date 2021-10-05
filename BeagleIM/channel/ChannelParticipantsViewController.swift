//
// ChannelParticipantsViewController.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import Combine
import TigaseSQLite3
import TigaseLogging

class ChannelParticipantsViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, ChannelAwareProtocol, NSMenuDelegate {
    
    @IBOutlet var searchField: NSSearchField!;
    @IBOutlet var participantsTableView: NSTableView!
    
    @IBOutlet var participantsTableViewHeightConstraint: NSLayoutConstraint!;
    
    @IBOutlet var inviteParticipantsButton: NSButton!;
    @IBOutlet var manageParticipantsButton: NSButton!;
    private var manageParticipantsButtonHeightConstraint: NSLayoutConstraint!;
    
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "MIX");
        
    @Published
    private var query: String = "";
    private var inviteOnly: Bool = true {
        didSet {
            manageParticipantsButton.isEnabled = !inviteOnly;
            manageParticipantsButton.isHidden = inviteOnly;
            if inviteOnly {
                NSLayoutConstraint.activate([manageParticipantsButtonHeightConstraint]);
            } else {
                NSLayoutConstraint.deactivate([manageParticipantsButtonHeightConstraint]);
            }
        }
    }
    var channel: Channel!;
    weak var channelViewController: NSViewController?;
    
    struct ParticipantItem: Hashable {
        let participant: MixParticipant;
        let isAdmin: Bool;
        let isOwner: Bool;
        
        var jid: BareJID? {
            return participant.jid;
        }
        
        var id: String {
            return participant.id;
        }
        
        var nickname: String? {
            return participant.nickname;
        }
    }
    
    private var participants: [ParticipantItem] = [] {
        didSet {
            participantsTableViewHeightConstraint.constant = max(min(CGFloat(participants.count) * (24.0 + 4 + 3), 400.0), 0.0);
            let changes = participants.calculateChanges(from: oldValue);
            self.participantsTableView.beginUpdates();
            if !changes.removed.isEmpty {
                self.participantsTableView.removeRows(at: changes.removed, withAnimation: .effectFade);
            }
            if !changes.inserted.isEmpty {
                self.participantsTableView.insertRows(at: changes.inserted, withAnimation: .effectFade);
            }
            self.participantsTableView.endUpdates();
        }
    }
    
    private let participantsDispatcher = QueueDispatcher(label: "participantsQueue");
    
    private var cancellables: Set<AnyCancellable> = [];
    
    struct Roles {
        var admins: [BareJID] = [];
        var owners: [BareJID] = [];
    }
    
    @Published
    private var roles: Roles = Roles();
    
    override func viewDidLoad() {
        if #available(macOS 11.0, *) {
            self.participantsTableView.style = .fullWidth;
        }
        participantsTableView.target = self;
        participantsTableView.action = #selector(itemClicked);
        manageParticipantsButtonHeightConstraint = manageParticipantsButton.heightAnchor.constraint(equalToConstant: 0);
        inviteOnly = true;
    }
    
    override func viewWillAppear() {
        if let mixModule = channel.context?.module(.mix) {
            mixModule.checkAccessPolicy(of: channel.jid, completionHandler: { [weak self] result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let inviteOnly):
                        self?.inviteOnly = inviteOnly;
                    case .failure(_):
                        self?.inviteOnly = true;
                    }
                }
            });
            if channel.permissions?.contains(.changeConfig) ?? false {
                mixModule.retrieveConfig(for: channel.jid, completionHandler: { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let config):
                            self.update(fromConfig: config);
                        case .failure(_):
                            self.roles = Roles();
                        }
                    }
                });
            }
        }
        self.channel.participantsPublisher.receive(on: DispatchQueue.main).combineLatest($query, $roles).sink(receiveValue: { [weak self] (participants, query, roles) in
            guard let that = self else {
                return;
            }
            that.participants = participants.filter({ query.isEmpty || $0.nickname?.lowercased().contains(query.lowercased()) ?? false }).sorted(by: that.sortParticipants).map({ ParticipantItem(participant: $0, isAdmin: $0.jid != nil && roles.admins.contains($0.jid!), isOwner: $0.jid != nil && roles.owners.contains($0.jid!) )});
        }).store(in: &cancellables);
        
        inviteParticipantsButton.isHidden = !channel.has(permission: .changeConfig);

        let constraint = participantsTableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -10);
        constraint.priority = .required;
        self.channel.permissionsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] permissions in
            self?.manageParticipantsButton.isHidden = !permissions.contains(.changeConfig);
            constraint.isActive = !permissions.contains(.changeConfig);
        }).store(in: &cancellables);
        
        NotificationCenter.default.publisher(for: NSControl.textDidChangeNotification, object: searchField).map({ ($0.object as! NSSearchField).stringValue }).sink(receiveValue: { [weak self] query in self?.query = query }).store(in: &cancellables);
        participantsTableView.selectionHighlightStyle = .none;
    }
        
    func update(fromConfig config: JabberDataElement) {
        var roles = Roles();
        if let ownerField: JidMultiField = config.getField(named: "Owner") {
            roles.owners = ownerField.value.map({ $0.bareJid });
        }
        if let adminField: JidMultiField = config.getField(named: "Administrator") {
            roles.admins = adminField.value.map({ $0.bareJid });
        }
        self.roles = roles;
    }
    
    @objc func itemClicked() {
        guard let menu = participantsTableView.menu, let event = NSApp.currentEvent else {
            return;
        }
        NSMenu.popUpContextMenu(menu, with: event, for: participantsTableView);
    }
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.participants.count;
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MixParticipantView"), owner: nil) as? ChannelParticipantTableCellView {
            view.update(participant: self.participants[row], in: self.channel);
            return view;
        }
        return nil;
    }
        
    func sortParticipants(p1: MixParticipant, p2: MixParticipant) -> Bool {
        let v1 = p1.nickname?.lowercased() ?? p1.jid?.stringValue ?? p1.id;
        let v2 = p2.nickname?.lowercased() ?? p2.jid?.stringValue ?? p2.id;
        return v1 < v2;
    }
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let channelAware = segue.destinationController as? ChannelAwareProtocol {
            channelAware.channel = channel;
        }
    }
    
    @IBAction func showInviteWindow(_ sender: Any) {
        //self.dismiss(self);
        channelViewController?.performSegue(withIdentifier: "ShowInviteToChannelSheet", sender: sender);
    }
    
    @IBAction func showManageParticipantsWindow(_ sender: Any) {
        //self.dismiss(self);
        self.channelViewController?.performSegue(withIdentifier: "ChannelManageBlockedSegue", sender: sender);
    }
    
    func numberOfItems(in menu: NSMenu) -> Int {
        return menu.items.count;
    }
    
    func menu(_ menu: NSMenu, update item: NSMenuItem, at index: Int, shouldCancel: Bool) -> Bool {
        // hide unwanted items
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row, let action = item.action else {
            item.isEnabled = false;
            item.isHidden = true;
            return true;
        }
        
        let participant = participants[row];

        let canModifyConfig = self.channel.permissions?.contains(.changeConfig) ?? false;
        
        switch action {
        case #selector(startChatClicked(_:)):
            item.isEnabled = true;
            item.isHidden = participant.jid == nil;
        case #selector(banParticipant(_:)):
            item.title = inviteOnly ? NSLocalizedString("Kick out", comment: "action label") : NSLocalizedString("Ban", comment: "action label");
            item.isEnabled = canModifyConfig;
            item.isHidden = !canModifyConfig;
        case #selector(grantAdminPermissions(_:)):
            item.image = item.image?.tinted(with: NSColor.systemGray);
            item.isEnabled = canModifyConfig && !participant.isAdmin;
            item.isHidden = (!canModifyConfig) || participant.isAdmin;
        case #selector(revokeAdminPermissions(_:)):
            item.image = item.image?.tinted(with: NSColor.systemGray);
            item.isEnabled = canModifyConfig && participant.isAdmin;
            item.isHidden = (!canModifyConfig) || !participant.isAdmin;
        case #selector(grantOwnerPermissions(_:)):
            item.image = item.image?.tinted(with: NSColor.systemYellow);
            item.isEnabled = canModifyConfig && !participant.isOwner;
            item.isHidden = (!canModifyConfig) || participant.isOwner;
        case #selector(revokeOwnerPermissions(_:)):
            item.image = item.image?.tinted(with: NSColor.systemYellow);
            item.isEnabled = canModifyConfig && participant.isOwner;
            item.isHidden = (!canModifyConfig) || !participant.isOwner;
        default:
            item.isEnabled = false;
            item.isHidden = true;
        }
        if #available(macOS 11.0, *) {
        } else {
            item.image = item.image?.scaled(maxWidthOrHeight: 16)
        }
        return true;
    }
    
    @IBAction func startChatClicked(_ sender: Any) {
        defer {
            self.dismiss(self);
        }
        
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row else {
            return;
        }
        
        guard let client = channel.context, let jid = participants[row].participant.jid else {
            return;
        }
        
        if let chat = client.modulesManager.module(.message).chatManager.createChat(for: client, with: jid) {
            NotificationCenter.default.post(name: ChatsListViewController.CHAT_SELECTED, object: chat)
        }
    }
    
    @IBAction func banParticipant(_ sender: Any) {
        defer {
            self.dismiss(self);
        }
        
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row else {
            return;
        }

        guard let mixModule = channel.context?.module(.mix), let jid = participants[row].participant.jid else {
            return;
        }

        let channelJid = channel.jid;
        if inviteOnly {
            mixModule.allowAccess(to: channelJid, for: jid, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    break;
                case .failure(let err):
                    self?.logger.error("blocking access to channel \(channelJid) for user \(jid) failed, error: \(err.description, privacy: .public)");
                }
            });
        } else {
            mixModule.denyAccess(to: channelJid, for: jid, completionHandler: { [weak self] result in
                switch result {
                case .success(_):
                    break;
                case .failure(let err):
                    self?.logger.error("blocking access to channel \(channelJid) for user \(jid) failed, error: \(err.description, privacy: .public)");
                }
            })
        }
    }
    
    @IBAction func grantAdminPermissions(_ sender: Any) {
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row, let jid = participants[row].jid else {
            return;
        }

        modifyConfig({ config in
            guard let field: JidMultiField = config.getField(named: "Administrator"), !field.value.contains(JID(jid)) else {
                return nil;
            }
            field.value.append(JID(jid));
            return config;
        })
    }
    
    @IBAction func revokeAdminPermissions(_ sender: Any) {
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row, let jid = participants[row].jid else {
            return;
        }

        modifyConfig({ config in
            guard let field: JidMultiField = config.getField(named: "Administrator"), field.value.contains(JID(jid)) else {
                return nil;
            }
            field.value.removeAll(where: { $0.bareJid == jid });
            return config;
        })
    }
    
    @IBAction func grantOwnerPermissions(_ sender: Any) {
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row, let jid = participants[row].jid else {
            return;
        }

        modifyConfig({ config in
            guard let field: JidMultiField = config.getField(named: "Owner"), !field.value.contains(JID(jid)) else {
                return nil;
            }
            field.value.append(JID(jid));
            return config;
        })
    }
    
    @IBAction func revokeOwnerPermissions(_ sender: Any) {
        let row = participantsTableView.clickedRow;
        guard row >= 0 && participants.count > row, let jid = participants[row].jid else {
            return;
        }

        modifyConfig({ config in
            guard let field: JidMultiField = config.getField(named: "Owner"), field.value.contains(JID(jid)) else {
                return nil;
            }
            field.value.removeAll(where: { $0.bareJid == jid });
            guard !field.value.isEmpty else {
                return nil;
            }
            return config;
        })
    }

    private func modifyConfig(_ fn: @escaping (JabberDataElement)->JabberDataElement?) {
        guard let mixModule = channel.context?.module(.mix) else {
            return;
        }
        let channelJid = channel.jid;
        mixModule.retrieveConfig(for: channelJid, completionHandler: { [weak self] result in
            switch result {
            case .success(let config):
                guard let newConfig = fn(config) else {
                    return;
                }
                mixModule.updateConfig(for: channelJid, config: newConfig, completionHandler: { result in
                    switch result {
                    case .success(_):
                        DispatchQueue.main.async {
                            self?.update(fromConfig: newConfig);
                        }
                    case .failure(_):
                        break;
                    }
                })
            case .failure(_):
                break;
            }
        })
    }
}

class ChannelParticipantTableCellView: NSTableCellView {
    
    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var label: NSTextField!;
    @IBOutlet var roleView: NSImageView!;
    
    func update(participant: ChannelParticipantsViewController.ParticipantItem, in channel: Channel) {
        let name = participant.nickname ?? participant.jid?.stringValue ?? participant.id;
        self.avatarView.name = name;
        if let jid = participant.jid {
            self.avatarView.avatar = AvatarManager.instance.avatar(for: jid, on: channel.account);
        } else {
            self.avatarView.avatar = nil;
        }
        
        self.label.stringValue = name;
        if participant.isOwner {
            if #available(macOS 11.0, *) {
                self.roleView.image = NSImage(named: "star.fill")?.tinted(with: NSColor.systemYellow);
            } else {
                self.roleView.image = NSImage(named: "starFill")?.tinted(with: NSColor.systemYellow);
            }
        } else if participant.isAdmin {
            self.roleView.image = NSImage(named: "star")?.tinted(with: NSColor.systemGray);
        } else {
            self.roleView.image = nil;
        }
    }
    
}
