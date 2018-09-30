//
//  ChatMessageCellView.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 13.04.2018.
//  Copyright © 2018 HI-LOW. All rights reserved.
//

import AppKit

class ChatMessageCellView: NSTableCellView {

    @IBOutlet var avatar: AvatarView!
    @IBOutlet var senderName: NSTextField!
    @IBOutlet var timestamp: NSTextField!
    @IBOutlet var message: NSTextField!
    
    func set(avatar: NSImage?) {
        self.avatar?.image = avatar;
    }
 
    func set(senderName: String?) {
        self.senderName.stringValue = senderName!;
    }
    
    func set(message: String?, timestamp: Date?, state: MessageState) {
        if message != nil {
            let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue);
            let matches = detector.matches(in: message!, range: NSMakeRange(0, message!.utf16.count));
            if (matches.isEmpty) {
                self.message.stringValue = message!;
            } else {
                let msg = NSMutableAttributedString(string: message!);
                matches.forEach { match in
                    if let url = match.url {
                        msg.addAttribute(.link, value: url, range: match.range);
                    }
                    if let phoneNumber = match.phoneNumber {
                        msg.addAttribute(.link, value: URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "-"))")!, range: match.range);
                    }
                    if let address = match.components {
                        let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                        msg.addAttribute(.link, value: URL(string: "http://maps.apple.com/?q=\(query!)")!, range: match.range);
                    }
                }
                msg.addAttribute(NSAttributedString.Key.font, value: self.message.font!, range: NSMakeRange(0, message!.utf16.count));
                self.message.attributedStringValue = msg;
            }
        } else {
            self.message.stringValue = "";
        }
        
        var timestampStr: NSMutableAttributedString? = nil;

        self.message.textColor = NSColor.textColor;
        
        switch state {
        case .incoming_error, .incoming_error_unread:
            self.message.textColor = NSColor.red;
        case .outgoing_delivered:
            timestampStr = NSMutableAttributedString(string: "\u{2713} ");
        case .outgoing_error, .outgoing_error_unread:
            timestampStr = NSMutableAttributedString(string: "Not delivered\u{203c} ", attributes: [.foregroundColor: NSColor.red]);
        default:
            break;
        }
        if timestampStr != nil {
            timestampStr!.append(NSMutableAttributedString(string: timestamp != nil ? formatTimestamp(timestamp!) : ""))
            self.timestamp.attributedStringValue = timestampStr!;
        } else {
            self.timestamp.attributedStringValue = NSMutableAttributedString(string: timestamp != nil ? formatTimestamp(timestamp!) : "");
        }
    }

    fileprivate func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return ChatMessageCellView.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return ChatMessageCellView.fullFormatter.string(from: ts);
        } else {
            return ChatMessageCellView.defaultFormatter.string(from: ts);
        }
        
    }
    
    override func layout() {
//        print("tt", self, self.superview, self.superview?.superview)
//        print("tt", self.frame.width, self.superview?.frame.width, self.superview?.superview?.frame.width)
//        print("xx", self.message.intrinsicContentSize, self.frame.width)
        
        //self.lastMessage?.preferredMaxLayoutWidth = self.frame.width;
        //        self.lastMessage!.preferredMaxLayoutWidth = 0;
        super.layout();
        //        self.lastMessage!.preferredMaxLayoutWidth = self.lastMessage!.alignmentRect(forFrame: self.lastMessage.frame).width;
        //        super.layout();
        if let width = self.superview?.superview?.frame.width {
            self.message.preferredMaxLayoutWidth = width - 80;
        }
    }
    
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
}
