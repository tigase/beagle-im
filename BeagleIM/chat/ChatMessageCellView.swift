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

class ChatMessageCellView: BaseChatCellView {

    var id: Int = 0;
    var ts: Date?;
    var sender: String?;

    @IBOutlet var message: MessageTextView!
        
    func updateTextColor() {
    }
        
    override func set(senderName: String, attributedSenderName: NSAttributedString? = nil) {
        super.set(senderName: senderName, attributedSenderName: attributedSenderName);
        sender = senderName;
    }
    
    func set(message item: ChatMessage, nickname: String? = nil, keywords: [String]? = nil) {
        super.set(item: item);
        ts = item.timestamp;
        id = item.id;
        let messageBody = self.messageBody(item: item);
        let msg = NSMutableAttributedString(string: messageBody);
        msg.setAttributes([.font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .light)], range: NSRange(location: 0, length: msg.length));
        
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
        case .outgoing_unsent:
            self.message.textColor = NSColor.secondaryLabelColor;
        case .outgoing_delivered:
            self.message.textColor = nil;
        case .outgoing_error, .outgoing_error_unread:
            self.message.textColor = nil;
        default:
            self.message.textColor = nil;//NSColor.textColor;
        }
        self.message.textColor = NSColor.controlTextColor;
        self.message.attributedString = msg;
        updateTextColor();
        autodetectLinksAndData(messageBody: msg.string);
    }
    
    private func autodetectLinksAndData(messageBody: String) {
        let id = self.id;
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard self != nil else {
                return;
            }
            if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue | NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.address.rawValue) {

                let matches = detector.matches(in: messageBody, range: NSMakeRange(0, messageBody.utf16.count));
                guard !matches.isEmpty else {
                    return;
                }
                DispatchQueue.main.async { [weak self] in
                    guard let that = self, that.id == id, let textStorage = that.message.textStorage else {
                        return;
                    }
                    textStorage.beginEditing();
                    matches.forEach { match in
                        if let url = match.url {
                            textStorage.addAttribute(.link, value: url, range: match.range);
                        }
                        if let phoneNumber = match.phoneNumber {
                            textStorage.addAttribute(.link, value: URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "-"))")!, range: match.range);
                        }
                        if let address = match.components {
                            let query = address.values.joined(separator: ",").addingPercentEncoding(withAllowedCharacters: .urlHostAllowed);
                            let mapUrl = URL(string: "http://maps.apple.com/?q=\(query!)")!;
                            textStorage.addAttribute(.link, value: mapUrl, range: match.range);
                        }
                    }
                    textStorage.endEditing();
                    that.message.invalidateIntrinsicContentSize();
                }
            }
        }
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

}

class ChatMessageSelectableCellView: ChatMessageCellView {
    
    var isEmphasized: Bool = false {
        didSet {
            updateTextColor();
        }
    }
    
    var isSelected: Bool = false {
        didSet {
            updateTextColor();
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow();
        if let window = self.window {
            NotificationCenter.default.addObserver(self, selector: #selector(becomeKey(_:)), name: NSWindow.didBecomeKeyNotification, object: window);
            NotificationCenter.default.addObserver(self, selector: #selector(resignKey(_:)), name: NSWindow.didResignKeyNotification, object: window);
        }
    }
    
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window = self.window {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window);
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window);
        }
        super.viewWillMove(toWindow: newWindow);
    }
    
    @objc func becomeKey(_ notification: Notification) {
        updateTextColor();
    }
    
    @objc func resignKey(_ notification: Notification) {
        updateTextColor();
    }
    
    override var appearance: NSAppearance? {
        didSet {
            updateTextColor();
        }
    }
    
    override func updateTextColor() {
        if isSelected && (window?.isKeyWindow ?? false) && self.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == NSAppearance.Name.aqua {
            message.layoutManager!.setTemporaryAttributes([.foregroundColor: NSColor.controlBackgroundColor], forCharacterRange: NSRange(location: 0, length: message.textStorage!.length));
        } else {
            message.layoutManager!.removeTemporaryAttribute(.foregroundColor, forCharacterRange: NSRange(location: 0, length: message.textStorage!.length));
        }
        message.needsToDraw(message.visibleRect);
    }

    override func layout() {
        super.layout();
        self.message.invalidateIntrinsicContentSize();
        super.layout();
    }
}
