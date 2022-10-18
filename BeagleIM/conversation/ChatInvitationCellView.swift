//
// ChatInvitationCellView.swift
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
import Martin

class ChatInvitationCellView: BaseChatCellView {
    
    @IBOutlet var message: MessageTextView!;
    @IBOutlet var acceptButton: NSButton!;
    
    @IBOutlet var defBottomButtonConstraint: NSLayoutConstraint?;
    
    private var account: BareJID?;
    private var appendix: ChatInvitationAppendix?;
    
    private var buttonBottomContraint: NSLayoutConstraint?;
    
    func set(item: ConversationEntry, message: String?, appendix: ChatInvitationAppendix) {
        super.set(item:  item);
        
        self.account = item.conversation.account;
        self.appendix = appendix;

        if item.state.direction == .incoming, let account = self.account, let channel = self.appendix?.channel {
            acceptButton.isHidden = DBChatStore.instance.conversation(for: account, with: channel) != nil;
        } else {
            acceptButton.isHidden = true;
        }
        if acceptButton.isHidden {
            if buttonBottomContraint == nil {
                buttonBottomContraint = self.state!.bottomAnchor.constraint(equalTo: self.message.bottomAnchor);
            }
            buttonBottomContraint?.priority = .required;
            defBottomButtonConstraint?.isActive = false;
            buttonBottomContraint?.isActive = true;
        } else {
            buttonBottomContraint?.isActive = false;
            defBottomButtonConstraint?.isActive = true;
        }
        
        let messageBody = message ?? String.localizedStringWithFormat(NSLocalizedString("Invitation to channel %@", comment: "Invitation to channel message"), appendix.channel.description);
        let msg = NSMutableAttributedString(string: messageBody);
        if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {
        
            let matches = detector.matches(in: messageBody, range: NSMakeRange(0, messageBody.utf16.count));

            matches.forEach { match in
                if let url = match.url {
                    msg.addAttribute(.link, value: url, range: match.range);
                }
                if let phoneNumber = match.phoneNumber {
                    msg.addAttribute(.link, value: URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "-"))")!, range: match.range);
                }
                if let address = match.components {
                    let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                    let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                    msg.addAttribute(.link, value: mapUrl, range: match.range);
                }
            }
        }
        msg.addAttribute(NSAttributedString.Key.font, value: self.message.font!, range: NSMakeRange(0, msg.length));
        self.message.attributedString = msg;
    }
    
    @IBAction func acceptClicked(_ sender: Any) {
        guard let account = self.account, let mixInvitation = appendix?.mixInvitation(), let window = self.window else {
            return;
        }

        guard let controller = NSStoryboard(name: "MIX", bundle: nil).instantiateController(withIdentifier: "EnterChannelViewController") as? EnterChannelViewController else {
            return;
        }
        
        _ = controller.view;
        controller.suggestedNickname = nil;
        controller.account = account;
        controller.channelJid = mixInvitation.channel;
        controller.componentType = .mix
        
        let windowController = NSWindowController(window: NSWindow(contentViewController: controller));
        window.beginSheet(windowController.window!, completionHandler: nil);
    }
}
