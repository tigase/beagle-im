//
// BaseChatCellView.swift
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

class BaseChatCellView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarView?
    @IBOutlet var senderName: NSTextField?
    @IBOutlet var timestamp: NSTextField?
    @IBOutlet var state: NSTextField?;

    var hasHeader: Bool {
        return avatar != nil;
    }
    
    func set(avatar: NSImage?) {
        self.avatar?.image = avatar;
    }
    
    func set(senderName: String, attributedSenderName: NSAttributedString? = nil) {
        if attributedSenderName == nil {
            self.senderName?.stringValue = senderName;
        } else {
            self.senderName?.attributedStringValue = attributedSenderName!;
        }
        self.avatar?.name = senderName;
    }
       
    func set(item: ChatEntry) {
        var timestampStr: NSMutableAttributedString? = nil;

        switch item.encryption {
        case .decrypted, .notForThisDevice, .decryptionFailed:
            let secured = NSMutableAttributedString(string: "\u{1F512}");
            if timestampStr != nil {
                timestampStr?.append(secured);
            } else {
                timestampStr = secured;
            }
        default:
            break;
        }
           
        if timestampStr != nil {
            timestampStr!.append(item.state == .outgoing_unsent ? NSAttributedString(string: " Unsent") : NSMutableAttributedString(string: " " + formatTimestamp(item.timestamp)));
            self.timestamp?.attributedStringValue = timestampStr!;
        } else {
            self.timestamp?.attributedStringValue = item.state == .outgoing_unsent ? NSAttributedString(string: "Unsent") : NSMutableAttributedString(string: formatTimestamp(item.timestamp));
        }
        
        switch item.state {
        case .incoming_error, .incoming_error_unread:
            self.state?.stringValue = "\u{203c}";
        case .outgoing_unsent:
            self.state?.stringValue = "\u{1f4e4}";
        case .outgoing_delivered:
            self.state?.stringValue = "\u{2713}";
        case .outgoing_error, .outgoing_error_unread:
            self.state?.stringValue = "\u{203c}";
        default:
            self.state?.stringValue = "";
        }
        self.state?.textColor = item.state.isError ? NSColor.systemRed : NSColor.secondaryLabelColor;
        
        self.toolTip = BaseChatCellView.tooltipFormatter.string(from: item.timestamp);
    }
    
    func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return BaseChatCellView.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return BaseChatCellView.fullFormatter.string(from: ts);
        } else {
            return BaseChatCellView.defaultFormatter.string(from: ts);
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

    fileprivate static let tooltipFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.locale = NSLocale.current;
        f.dateStyle = .medium
        f.timeStyle = .medium;
        return f;
    })();
}
