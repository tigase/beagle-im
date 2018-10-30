//
//  ChatCellView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 30.08.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit
import TigaseSwift

class ChatCellView: NSTableCellView {
    
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
    
    @IBOutlet weak var avatar: AvatarViewWithStatus!;
    @IBOutlet weak var label: NSTextField!;
    @IBOutlet weak var lastMessage: ChatCellViewMessage!;
    @IBOutlet weak var lastMessageTs: NSTextField!;
    @IBOutlet weak var unreadButton: NSButton!;
    @IBOutlet weak var closeButton: ChatsCellViewCloseButton!
    
    var closeFunction: (()->Void)?;
    
    @IBAction func closeClicked(_ sender: ChatsCellViewCloseButton) {
        closeFunction?();
    }
    
    func set(avatar: NSImage?) {
        self.avatar?.avatar = avatar;
    }
    
    func set(name: String?) {
        self.label?.stringValue = name ?? "";
    }
    
    func set(lastMessage: String?, ts: Date?) {
        if lastMessage == nil {
            self.lastMessage?.stringValue = "";
        } else {
            let msg = NSMutableAttributedString(string: lastMessage!);
            if Settings.enableMarkdownFormatting.bool() {
                Markdown.applyStyling(attributedString: msg);
            }
            self.lastMessage?.attributedStringValue = msg;
        }
        self.lastMessage?.maximumNumberOfLines = 3;
        //self.lastMessage?.preferredMaxLayoutWidth = self.lastMessage!.frame.width;
        self.lastMessageTs?.stringValue = ts != nil ? formatTimestamp(ts!) : "";
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
    
    fileprivate func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return ChatCellView.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return ChatCellView.fullFormatter.string(from: ts);
        } else {
            return ChatCellView.defaultFormatter.string(from: ts);
        }
        
    }
    
    func update(from item: ChatItemProtocol) {
        self.set(name: item.name);
        self.set(unread: item.unread);
        self.set(lastMessage: item.lastMessageText, ts: item.lastMessageTs);
//        self.set(avatar: AvatarManager.instance.avatar(for: item.chat.jid.bareJid, on: item.chat.account));
        if item.chat is Chat {
            self.avatar.update(for: item.chat.jid.bareJid, on: item.chat.account);
        } else if let room  = item.chat as? Room {
            self.avatar.avatar = NSImage(named: NSImage.userGroupName);
            self.avatar.status = room.state == .joined ? .online : (room.state == .requested ? .away : nil);
        }
    }

    override func layout() {
        super.layout();
        
        if let width = self.superview?.superview?.frame.width {
            self.lastMessage.preferredMaxLayoutWidth = width - 80;
        }
    }
    
    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize);
        if let width = self.superview?.superview?.frame.width {
            self.lastMessage.preferredMaxLayoutWidth = width - 80;
        }
    }
 
    func setMouseHovers(_ val: Bool) {
        self.lastMessage.blured = val;
        self.closeButton.isHidden = !val;
    }
}

