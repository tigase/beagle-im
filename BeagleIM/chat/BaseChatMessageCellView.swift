//
// BaseChatMessageCellView.swift
//
// BeagleIM
// Copyright (C) 2019 "Tigase, Inc." <office@tigase.com>
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
import LinkPresentation
import TigaseSwift

class BaseChatMessageCellView: NSTableCellView {

    fileprivate static let imageLoadingQueue = DispatchQueue(label: "image_loading_queue");

    fileprivate static let allowedUrlPreviewSchemas = [ "https://", "http://", "file://" ];

    var id: Int = 0;

    @IBOutlet var message: NSTextField!
    @IBOutlet var state: NSTextField?;
    fileprivate var direction: MessageDirection? = nil;

    func set(message item: ChatMessage, nickname: String? = nil, keywords: [String]? = nil) {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue);

        let messageBody = self.messageBody(item: item);
        let matches = detector.matches(in: messageBody, range: NSMakeRange(0, messageBody.utf16.count));
        let msg = NSMutableAttributedString(string: messageBody);

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
        msg.addAttribute(NSAttributedString.Key.font, value: self.message.font!, range: NSMakeRange(0, msg.length));

        if Settings.enableMarkdownFormatting.bool() {
            Markdown.applyStyling(attributedString: msg, showEmoticons: Settings.showEmoticons.bool());
        }
        if let nick = nickname {
            msg.markMention(of: nick, withColor: NSColor.systemBlue, bold: Settings.boldKeywords.bool());
        }
        if let keys = keywords {
            msg.mark(keywords: keys, withColor: NSColor.systemRed, bold: Settings.boldKeywords.bool());
        }
        if let errorMessage = item.error {
            msg.append(NSAttributedString(string: "\n------\n\(errorMessage)", attributes: [.foregroundColor : NSColor.systemRed]));
        }

        switch item.state {
        case .incoming_error, .incoming_error_unread:
            self.message.textColor = NSColor.systemRed;
            self.state?.stringValue = "\u{203c}";
        case .outgoing_unsent:
            self.message.textColor = NSColor.secondaryLabelColor;
            self.state?.stringValue = "\u{1f4e4}";
        case .outgoing_delivered:
            self.message.textColor = nil;
            self.state?.stringValue = "\u{2713}";
        case .outgoing_error, .outgoing_error_unread:
            self.message.textColor = nil;
            self.state?.stringValue = "\u{203c}";
        default:
            self.state?.stringValue = "";
            self.message.textColor = nil;//NSColor.textColor;
        }
        self.state?.textColor = item.state.isError ? NSColor.systemRed : NSColor.secondaryLabelColor;
        self.direction = item.state.direction;

        self.toolTip = BaseChatMessageCellView.tooltipFormatter.string(from: item.timestamp);

        self.message.attributedStringValue = msg;
    }

    override func layout() {
        if Settings.alternateMessageColoringBasedOnDirection.bool() {
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

    fileprivate func messageBody(item: ChatMessage) -> String {
        guard let msg = item.encryption.message() else {
//            guard let error = item.error else {
//                return item.message;
//            }
//            return "\(item.message)\n-----\n\(error)";
            return item.message;
        }
        return msg;
    }

    func formatTimestamp(_ ts: Date) -> String {
        let flags: Set<Calendar.Component> = [.day, .year];
        let components = Calendar.current.dateComponents(flags, from: ts, to: Date());
        if (components.day! == 1) {
            return "Yesterday";
        } else if (components.day! < 1) {
            return BaseChatMessageCellView.todaysFormatter.string(from: ts);
        }
        if (components.year! != 0) {
            return BaseChatMessageCellView.fullFormatter.string(from: ts);
        } else {
            return BaseChatMessageCellView.defaultFormatter.string(from: ts);
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
