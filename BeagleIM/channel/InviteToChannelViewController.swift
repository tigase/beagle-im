//
// InviteToChannelViewController.swift
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

class InviteToChannelViewControllerController: NSViewController, NSTextFieldDelegate, ChannelAwareProtocol {
    
    @IBOutlet var contactSelectionView: MultiContactSelectionView!;
    
    var channel: Channel!;
    
    override func viewDidLoad() {
        super.viewDidLoad();
        contactSelectionView.closedSuggestionsList = false;
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
    }
    
    @IBAction func inviteClicked(_ sender: NSButton) {
        let jids = contactSelectionView.items.map({ JID($0.jid) })
        
        if let channel = self.channel, let client = channel.context {
            let mixModule = client.module(.mix);
            mixModule.checkAccessPolicy(of: channel.channelJid, completionHandler: { [weak self] result in
                switch result {
                    case .success(let val):
                    if val {
                        for jid in jids {
                            mixModule.allowAccess(to: channel.channelJid, for: jid.bareJid, completionHandler: { result in
                                let body = "Invitation to channel \(channel.channelJid.stringValue)";
                                let mixInvitation = MixInvitation(inviter: channel.account, invitee: jid.bareJid, channel: channel.channelJid, token: nil);
                                let message = mixModule.createInvitation(mixInvitation, message: body);
                                message.messageDelivery = .request;
                                let conversationKey: ConversationKey = DBChatStore.instance.conversation(for: channel.account, with: jid.bareJid) ?? ConversationKeyItem(account: channel.account, jid: jid.bareJid);
                                let options = ConversationEntry.Options(recipient: .none, encryption: .none, isMarkable: false);
                                DBChatHistoryStore.instance.appendItem(for: conversationKey, state: .outgoing(.sent), sender: .me(conversation: conversationKey), type: .invitation, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: body, appendix: ChatInvitationAppendix(mixInvitation: mixInvitation), options: options, linkPreviewAction: .none, completionHandler: nil);
                                mixModule.write(message);
                            });
                        }
                    } else {
                        for jid in jids {
                            let body = "Invitation to channel \(channel.channelJid.stringValue)";
                            let mixInvitation = MixInvitation(inviter: channel.account, invitee: jid.bareJid, channel: channel.channelJid, token: nil);
                            let message = mixModule.createInvitation(mixInvitation, message: body);
                            message.messageDelivery = .request;
                            let conversationKey: ConversationKey = DBChatStore.instance.conversation(for: channel.account, with: jid.bareJid) ?? ConversationKeyItem(account: channel.account, jid: jid.bareJid);
                            let options = ConversationEntry.Options(recipient: .none, encryption: .none, isMarkable: false);
                            DBChatHistoryStore.instance.appendItem(for: conversationKey, state: .outgoing(.sent), sender: .me(conversation: conversationKey), type: .invitation, timestamp: Date(), stanzaId: message.id, serverMsgId: nil, remoteMsgId: nil, data: body, appendix: ChatInvitationAppendix(mixInvitation: mixInvitation), options: options, linkPreviewAction: .none, completionHandler: nil);
                            mixModule.write(message);
                        }
                    }
                    DispatchQueue.main.async {
                        self?.close();
                    }
                case .failure(let error):
                    DispatchQueue.main.async {
                        guard let window = self?.view.window else {
                            return;
                        }
                        let alert = NSAlert();
                        alert.messageText = NSLocalizedString("Error occurred", comment: "alert window title");
                        alert.icon = NSImage(named: NSImage.cautionName);
                        alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("Could not invite to channel on the server. Got following error: %@", comment: "alert window message"), error.localizedDescription);
                        alert.addButton(withTitle: NSLocalizedString("OK", comment: "Button"));
                        alert.beginSheetModal(for: window, completionHandler: nil);
                    }
                }
            })
        } else {
            close();
        }
    }
    
    @IBAction func cancelClicked(_ sender: NSButton) {
        close();
    }
 
    fileprivate func close() {
        self.view.window?.sheetParent?.endSheet(self.view.window!);
    }

}
