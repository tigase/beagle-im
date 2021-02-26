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

class ChannelParticipantsViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, ChannelAwareProtocol {
    
    @IBOutlet var participantsTableView: NSTableView!
    
    @IBOutlet var participantsTableViewHeightConstraint: NSLayoutConstraint!;
    
    @IBOutlet var inviteParticipantsButton: NSButton!;
    @IBOutlet var manageParticipantsButton: NSButton!;
    
    var channel: Channel!;
    weak var channelViewController: NSViewController?;
    
    private var participants: [MixParticipant] = [] {
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
    
    override func viewWillAppear() {
        self.channel.participantsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] participants in
            guard let that = self else {
                return;
            }
            that.participants = participants.sorted(by: that.sortParticipants);
        }).store(in: &cancellables);
        
        inviteParticipantsButton.isHidden = !channel.has(permission: .changeConfig);

        let constraint = participantsTableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -10);
        constraint.priority = .required;
        self.channel.permissionsPublisher.receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] permissions in
            self?.manageParticipantsButton.isHidden = !permissions.contains(.changeConfig);
            constraint.isActive = !permissions.contains(.changeConfig);
        }).store(in: &cancellables);
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
        let v1 = p1.nickname ?? p1.jid?.stringValue ?? p1.id;
        let v2 = p2.nickname ?? p2.jid?.stringValue ?? p2.id;
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
        channelViewController?.performSegue(withIdentifier: "ShowManagerParticipantsSheet", sender: sender);
    }

}

class ChannelParticipantTableCellView: NSTableCellView {
    
    @IBOutlet var avatarView: AvatarView!;
    @IBOutlet var label: NSTextField!;
    
    func update(participant: MixParticipant, in channel: Channel) {
        let name = participant.nickname ?? participant.jid?.stringValue ?? participant.id;
        self.avatarView.name = name;
        if let jid = participant.jid {
            self.avatarView.image = AvatarManager.instance.avatar(for: jid, on: channel.account);
        } else {
            self.avatarView.image = nil;
        }
        self.label.stringValue = name;
    }
    
}
