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
import TigaseSwift
import Combine

class BaseChatCellView: NSTableCellView {
    
    @IBOutlet var avatar: AvatarView?
    @IBOutlet var senderName: NSTextField?
    @IBOutlet var timestamp: NSTextField?
    @IBOutlet var state: NSTextField?;

    @IBInspectable var ignoreAlternativeRowColoring: Bool = false;
    
    private var direction: MessageDirection? = nil;

    private var cancellables: Set<AnyCancellable> = [];
    
    var hasHeader: Bool {
        return avatar != nil;
    }
     
    func set(item: ConversationEntry) {
        cancellables.removeAll();
        //var timestampStr: NSMutableAttributedString? = nil;

        if let item = item as? ConversationEntryWithSender {
            if let avatar = self.avatar {
                item.avatar.$avatar.assign(to: \AvatarView.image, on: avatar).store(in: &cancellables);
            }
            
            if senderName != nil {
                switch item.recipient {
                case .none:
                    self.senderName?.stringValue = item.sender.nickname;
                case .occupant(let nickname):
                    let val = NSMutableAttributedString(string: item.state.direction == .incoming ? "From \(item.sender.nickname) " : "To \(nickname)  ");
                    let font = NSFontManager.shared.convert(NSFont.systemFont(ofSize: senderName!.font!.pointSize - 2), toHaveTrait: [.italicFontMask, .smallCapsFontMask, .unboldFontMask]);
                    val.append(NSAttributedString(string: " (private message)", attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]));
                    self.senderName?.attributedStringValue = val;
                }
            }
            
            var timestampPrefix: String?;
            switch item.encryption {
            case .decrypted, .notForThisDevice, .decryptionFailed:
                timestampPrefix = "\u{1F512} ";
            default:
                break;
            }
               
            if item.state == .outgoing_unsent {
                if let prefix = timestampPrefix {
                    timestampPrefix = "\(prefix) Unsent";
                } else {
                    timestampPrefix = "Unsent"
                }
            }
            if let timestampView = self.timestamp {
                let timestamp = item.timestamp;
                CurrentTimePublisher.publisher.map({ now in BaseChatCellView.formatTimestamp(timestamp, now, prefix: timestampPrefix) }).assign(to: \.stringValue, on: timestampView).store(in: &cancellables);
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
        } else {
            self.senderName?.stringValue = "";
            self.avatar?.image = nil;
            if let timestampView = self.timestamp {
                let timestamp = item.timestamp;
                CurrentTimePublisher.publisher.map({ now in BaseChatCellView.formatTimestamp(timestamp, now, prefix: nil) }).assign(to: \.stringValue, on: timestampView).store(in: &cancellables);
            }
            self.state?.stringValue = "";
        }
        
        
        self.toolTip = prepareTooltip(item: item);
        self.direction = (item as? ConversationEntryWithSender)?.state.direction ?? .incoming;
    }
    
    static func formatTimestamp(_ ts: Date, _ now: Date, prefix: String?) -> String {
        let timestamp = formatTimestamp(ts, now);
        if let prefix = prefix {
            return "\(prefix) \(timestamp)";
        } else {
            return timestamp;
        }
    }
    
    func prepareTooltip(item: ConversationEntry) -> String {
        return BaseChatCellView.tooltipFormatter.string(from: item.timestamp);
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
            return BaseChatCellView.fullFormatter.string(from: ts);
        } else {
            return BaseChatCellView.defaultFormatter.string(from: ts);
        }
    }

    override func layout() {
        if !ignoreAlternativeRowColoring && Settings.alternateMessageColoringBasedOnDirection {
            if let direction = self.direction {
                switch direction {
                case .incoming:
                    self.wantsLayer = true;
                    self.layer?.backgroundColor = NSColor(named: "chatBackgroundColor")!.cgColor;
                case .outgoing:
                    self.wantsLayer = true;
                    self.layer?.backgroundColor = NSColor(named: "chatOutgoingBackgroundColor")!.cgColor;
                }
            }
        }
    //        if let width = self.superview?.superview?.frame.width {
    //            if self.state != nil {
    //                self.message.preferredMaxLayoutWidth = width - 68;
    //            } else {
    //                self.message.preferredMaxLayoutWidth = width - 50;
    //            }
    //        }
        super.layout();
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

    static let tooltipFormatter = ({()-> DateFormatter in
        var f = DateFormatter();
        f.locale = NSLocale.current;
        f.dateStyle = .medium
        f.timeStyle = .medium;
        return f;
    })();
}
