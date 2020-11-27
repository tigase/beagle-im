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
        }
    }
    
    private let participantsDispatcher = QueueDispatcher(label: "participantsQueue");
    
    override func viewWillAppear() {
        NotificationCenter.default.addObserver(self, selector: #selector(participantsChanged(_:)), name: MixEventHandler.PARTICIPANTS_CHANGED, object: nil);
        self.participants = self.channel!.participants.sorted(by: self.sortParticipants);
        self.participantsTableView.reloadData();
        inviteParticipantsButton.isHidden = !channel.has(permission: .changeConfig);
        if !channel.has(permission: .changeConfig) {
            manageParticipantsButton.isHidden = true;
            let constraint = participantsTableView.bottomAnchor.constraint(equalTo: self.view.bottomAnchor, constant: -10);
            constraint.priority = .required;
            constraint.isActive = true;
        }
    }
    
    override func viewWillDisappear() {
        NotificationCenter.default.removeObserver(self);
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
    
    @objc func participantsChanged(_ notification: Notification) {
        guard let e = notification.object as? MixModule.ParticipantsChangedEvent else {
            return;
        }
        self.participantsDispatcher.async {
            guard var store = DispatchQueue.main.sync(execute: { () -> [MixParticipant]? in
                guard self.channel.id == (e.channel as? Channel)?.id else {
                    return nil;
                }
                return self.participants;
            }) else {
                return;
            }
            
            let refresh = e.joined.filter({ p1 in store.first(where: { p2 in p2.id == p1.id }) != nil});
            
            let removeIds = e.left.map({ $0.id }) + refresh.map({ $0.id });
            let removedIdx = removeIds.map({ id in store.firstIndex(where: { $0.id == id }) }).filter({ $0 != nil}).map({ $0! });
            
            store = store.filter({!removeIds.contains($0.id)});
            
            let added = e.joined.sorted(by: self.sortParticipants(p1:p2:));
            var addedIdx: [Int] = [];
            for item in added {
                let idx = store.firstIndex(where: { p in !self.sortParticipants(p1: p, p2: item)}) ?? store.count;
                store.insert(item, at: idx);
                addedIdx.append(idx);
            }
            
            DispatchQueue.main.async {
                self.participants = store;
                self.participantsTableView.beginUpdates();
                if !removedIdx.isEmpty {
                    self.participantsTableView.removeRows(at: IndexSet(removedIdx), withAnimation: .effectFade);
                }
                if !addedIdx.isEmpty {
                    self.participantsTableView.insertRows(at: IndexSet(addedIdx), withAnimation: .effectFade);
                }
                self.participantsTableView.endUpdates();
            }
        }
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
