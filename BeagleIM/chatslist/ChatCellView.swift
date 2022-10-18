//
// ChatCellView.swift
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
import Combine

class ChatCellView: NSTableCellView {
    
    private static let throttlingQueue = DispatchQueue(label: "ChatCellViewThrottlingQueue");
    
    fileprivate static let todaysFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateStyle = .none;
        f.timeStyle = .short;
        return f;
    })();
    fileprivate static let defaultFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM", options: 0, locale: NSLocale.current);
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    fileprivate static let fullFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.dateFormat = DateFormatter.dateFormat(fromTemplate: "dd.MM.yyyy", options: 0, locale: NSLocale.current);
        //        f.timeStyle = .NoStyle;
        return f;
    })();
    
    @IBOutlet weak var avatar: AvatarViewWithStatus! {
        didSet {
            self.avatar?.avatarView?.appearance = NSAppearance(named: .darkAqua);
        }
    }
    @IBOutlet weak var label: NSTextField!;
    @IBOutlet weak var lastMessage: ChatCellViewMessage? {
        didSet {
            lastMessageHeightConstraint = lastMessage?.heightAnchor.constraint(equalToConstant: 0);
        }
    }
    @IBOutlet weak var lastMessageTs: NSTextField!;
    @IBOutlet weak var unreadButton: NSButton!;
    @IBOutlet weak var closeButton: ChatsCellViewCloseButton! {
        didSet {
            closeButton?.appearance = NSAppearance(named: .aqua);
        }
    }
    
    var lastMessageHeightConstraint: NSLayoutConstraint?;
    
    var closeFunction: (()->Bool)?;
    
    fileprivate var chatState: ChatState = .active;
    
    @IBAction func closeClicked(_ sender: ChatsCellViewCloseButton) {
        guard let fn = closeFunction, fn() else {
            return;
        }
        closeFunction = nil;
    }

    func set(lastActivity: LastChatActivity?, chatState: ChatState, account: BareJID) {
        self.unreadButton.appearance = NSAppearance(named: .darkAqua);
        self.chatState = chatState;
        if let lastMessageField = self.lastMessage {
            if chatState != .composing {
                lastMessageField.stopAnimating();
                self.lastMessageHeightConstraint?.isActive = false;
                if let activity = lastActivity {
                    switch activity.payload {
                    case .message(let lastMessage):
                        if lastMessage.starts(with: "/me ") {
                            let nick = activity.sender.nickname ?? NSLocalizedString("Me", comment: "/me replacement if no nickname found");
                            let msg = NSMutableAttributedString(string: "\(nick) ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask), .foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);
                            msg.append(NSAttributedString(string: "\(lastMessage.dropFirst(4))", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .regular), toHaveTrait: .italicFontMask), .foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]));
                            lastMessageField.attributedStringValue = msg;
                        } else {
                            let msg = NSMutableAttributedString(string: lastMessage);
                            if Settings.enableMarkdownFormatting {
                                Markdown.applyStyling(attributedString: msg, fontSize: NSFont.systemFontSize - 1, showEmoticons: Settings.showEmoticons);
                            }
                            switch activity.sender {
                            case .none, .buddy(_):
                                lastMessageField.attributedStringValue = msg;
                            case .me(_):
                                let nick = NSLocalizedString("You", comment: "you label for conversation log")
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)]);
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            default:
                                if let nick = activity.sender.nickname {
                                    let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)]);
                                    prefix.append(msg);
                                    lastMessageField.attributedStringValue = prefix;
                                } else {
                                    lastMessageField.attributedStringValue = msg;
                                }
                            }
                        }
                    case .attachment:
                        if let fieldfont = self.lastMessage?.font {
                            let msg = NSAttributedString(string: "📎 " + NSLocalizedString("Attachment", comment: "attachment name in chats list"), attributes: [.font:  NSFontManager.shared.convert(fieldfont, toHaveTrait: [.italicFontMask, .fixedPitchFontMask, .boldFontMask]), .foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);

                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        } else {
                            let msg = NSAttributedString(string: "📎 " + NSLocalizedString("Attachment", comment: "attachment name in chats list"), attributes: [.foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);
                        
                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        }
                    case .location:
                        if let fieldfont = lastMessageField.font {
                            let msg = NSAttributedString(string: "📍 " + NSLocalizedString("Location", comment: "location name in chats list"), attributes: [.font:  NSFontManager.shared.convert(fieldfont, toHaveTrait: [.italicFontMask, .fixedPitchFontMask, .boldFontMask]), .foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);

                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        } else {
                            let msg = NSAttributedString(string: "📍 " + NSLocalizedString("Location", comment: "location name in chats list"), attributes: [.foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);
                        
                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        }
                    case .invitation:
                        if let fieldfont = lastMessageField.font {
                            let msg = NSAttributedString(string: "📨 " + NSLocalizedString("Invitation", comment: "invitation name in chats list"), attributes: [.font:  NSFontManager.shared.convert(fieldfont, toHaveTrait: [.italicFontMask, .fixedPitchFontMask, .boldFontMask]), .foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);

                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        } else {
                            let msg = NSAttributedString(string: "📨 " + NSLocalizedString("Invitation", comment: "invitation name in chats list"), attributes: [.foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);
                        
                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        }
                    case .retraction:
                        if let fieldfont = lastMessageField.font {
                            let msg = NSAttributedString(string: "🗑️ " + NSLocalizedString("Retraction", comment: "retraction name in chats list"), attributes: [.font:  NSFontManager.shared.convert(fieldfont, toHaveTrait: [.italicFontMask, .fixedPitchFontMask, .boldFontMask]), .foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);

                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        } else {
                            let msg = NSAttributedString(string: "🗑️ " + NSLocalizedString("Retraction", comment: "retraction name in chats list"), attributes: [.foregroundColor: lastMessageField.textColor!.withAlphaComponent(0.8)]);
                        
                            if let nick = activity.sender.nickname {
                                let prefix = NSMutableAttributedString(string: "\(nick): ", attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium), toHaveTrait: .italicFontMask)])
                                prefix.append(msg);
                                lastMessageField.attributedStringValue = prefix;
                            } else {
                                lastMessageField.attributedStringValue = msg;
                            }
                        }
                    case .none:
                        lastMessageField.stringValue = "";
                    }
                } else {
                    lastMessageField.stringValue = "";
                }
                lastMessageField.maximumNumberOfLines = 2;
            } else {
                lastMessageHeightConstraint?.constant = lastMessageField.frame.height;
                lastMessageHeightConstraint?.isActive = true;
                lastMessageField.stringValue = "";
                lastMessageField.startAnimating();
            }
            lastMessageField.invalidateIntrinsicContentSize();
        }
    }
    
    func set(chatState: ChatState) {
        self.chatState = chatState;
        if chatState == .composing {
            self.lastMessage?.stringValue = "";
            self.lastMessage?.startAnimating();
        } else {
            self.lastMessage?.stringValue = "";
            self.lastMessage?.stopAnimating();
        }
    }
    
    func set(unread: Int) {
        if unread > 0 {
            self.unreadButton.title = "\(unread)"
            self.unreadButton.isHidden = false;
        } else {
            self.unreadButton.title = "0";
            self.unreadButton.isHidden = true;
        }
    }
    
    private static let relativeForamtter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter();
        formatter.dateTimeStyle = .named;
        formatter.unitsStyle = .short;
        return formatter;
    }();
    
    private static func formatTimestamp(_ ts: Date, _ now: Date) -> String {
        let flags: Set<Calendar.Component> = [.minute, .hour, .day, .year];
        var components = Calendar.current.dateComponents(flags, from: now, to: ts);
        if (components.day! >= -1) {
            components.second = 0;
            return relativeForamtter.localizedString(from: components);
        }
        if (components.year! != 0) {
            return ChatCellView.fullFormatter.string(from: ts);
        } else {
            return ChatCellView.defaultFormatter.string(from: ts);
        }
    }
    
    private var cancellables: Set<AnyCancellable> = [];
    private var conversation: Conversation? {
        didSet {
            unreadButton.isHidden = false;
            lastMessageTs.isHidden = false;
            avatar.statusView.isHidden = false;
            cancellables.removeAll();
            conversation?.displayNamePublisher.assign(to: \.stringValue, on: label).store(in: &cancellables);
            avatar.displayableId = conversation;
            conversation?.unreadPublisher.throttleFixed(for: 0.1, scheduler: ChatCellView.throttlingQueue, latest: true).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] value in
                self?.set(unread: value);
            }).store(in: &cancellables);
            conversation?.timestampPublisher.combineLatest(CurrentTimePublisher.publisher).throttleFixed(for: 0.1, scheduler: ChatCellView.throttlingQueue, latest: true).map({ (value, now) in ChatCellView.formatTimestamp(value,now)}).receive(on: DispatchQueue.main).assign(to: \.stringValue, on: lastMessageTs).store(in: &cancellables);
            if let account = conversation?.account {
                if let chat = conversation as? Chat {
                    conversation?.lastActivityPublisher.throttleFixed(for: 0.1, scheduler: ChatCellView.throttlingQueue, latest: true).combineLatest(chat.$remoteChatState.replaceNil(with: ChatState.active)).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] (activity, chatState) in
                        self?.set(lastActivity: activity, chatState: chatState, account: account);
                    }).store(in: &cancellables);
                } else {
                    conversation?.lastActivityPublisher.throttleFixed(for: 0.1, scheduler: ChatCellView.throttlingQueue, latest: true).receive(on: DispatchQueue.main).sink(receiveValue: { [weak self] value in
                        self?.set(lastActivity: value, chatState: .active, account: account);
                    }).store(in: &cancellables);
                }
            }
        }
    }
    
    func update(from item: ConversationItem) {
        closeFunction = nil;
        contact = nil;
        conversation = item.chat;
    }
    
    var contact: Contact? {
        didSet {
            cancellables.removeAll();
            unreadButton.isHidden = true;
            lastMessageTs.isHidden = true;
            avatar.statusView.isHidden = true;
            if let lastMessage = self.lastMessage {
                contact?.displayNamePublisher.assign(to: \.stringValue, on: lastMessage).store(in: &cancellables);
            }
            avatar.displayableId = contact;
        }
    }
    
    func update(from item: InvitationItem) {
        closeFunction = nil;
        conversation = nil;
        label.stringValue = item.name;
        contact = ContactManager.instance.contact(for: .init(account: item.account, jid: item.jid.bareJid, type: .buddy));
    }

//    override func layout() {
//        super.layout();
//
//        if let width = self.superview?.superview?.frame.width {
//            self.lastMessage.preferredMaxLayoutWidth = width - 66;
//        }
//    }
//
//    override func resize(withOldSuperviewSize oldSize: NSSize) {
//        super.resize(withOldSuperviewSize: oldSize);
//        if let width = self.superview?.superview?.frame.width {
//            self.lastMessage.preferredMaxLayoutWidth = width - 66;
//        }
//    }
 
    func setMouseHovers(_ val: Bool) {
        let visible = val && closeFunction != nil;
        self.lastMessage?.blured = visible;
        self.closeButton.isHidden = !visible;
    }
}

