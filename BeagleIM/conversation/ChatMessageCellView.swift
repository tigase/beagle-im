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
import Martin

class ChatMessageCellView: BaseChatCellView {

    var id: Int = 0;

    @IBOutlet var message: MessageTextView!
        
    func updateTextColor() {
    }
        

    override func set(item: ConversationEntry) {
        super.set(item: item);
        id = item.id;
    }
    
    func set(item: ConversationEntry, message: String, correctionTimestamp: Date?, nickname: String? = nil) {
        set(item: item);
        
        if correctionTimestamp != nil, case .incoming(_) = item.state {
            self.state!.stringValue = "✏️\(self.state!.stringValue)";
        }
        
        let messageBody = self.messageBody(item: item, message: message);
        let msg = NSMutableAttributedString(string: messageBody);
        let fontSize = NSFont.systemFontSize;
        msg.setAttributes([.font: NSFont.systemFont(ofSize: fontSize)], range: NSRange(location: 0, length: msg.length));
        
        if Settings.enableMarkdownFormatting {
            Markdown.applyStyling(attributedString: msg, fontSize: fontSize, showEmoticons: Settings.showEmoticons);
        }
        if let nick = nickname {
            msg.markMention(of: nick, withColor: NSColor.systemBlue, bold: Settings.boldKeywords);
        }
        let keywords = Settings.markKeywords;
        if !keywords.isEmpty {
            msg.mark(keywords: keywords, withColor: NSColor.systemRed, bold: Settings.boldKeywords);
        }
        if let errorMessage = item.state.errorMessage {
            msg.append(NSAttributedString(string: "\n------\n\(errorMessage)", attributes: [.foregroundColor : NSColor.systemRed]));
        }
        self.message.textColor = NSColor.controlTextColor;
        self.message.attributedString = msg;
        updateTextColor();
        autodetectLinksAndData(messageBody: msg.string);
    }
    
    func setRetracted(item: ConversationEntry) {
        set(item: item);

        let msg = NSAttributedString(string: NSLocalizedString("(this message has been removed)", comment: "replaces removed messages"), attributes: [.font: NSFontManager.shared.convert(NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium), toHaveTrait: .italicFontMask), .foregroundColor: NSColor.secondaryLabelColor]);
        
        self.message.textColor = NSColor.secondaryLabelColor;
        self.message.attributedString = msg;
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
                        if let phoneNumber = match.phoneNumber, let url = URL(string: "tel:\(phoneNumber.replacingOccurrences(of: " ", with: "-"))") {
                            textStorage.addAttribute(.link, value: url, range: match.range);
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
    
    override func prepareTooltip(item: ConversationEntry) -> String {
        switch item.payload {
        case .message(_, let correctionTimestamp):
            if let timestamp = correctionTimestamp {
                return String.localizedStringWithFormat(NSLocalizedString("edited at %@", comment: "mark's message that was edited"), BaseChatCellView.tooltipFormatter.string(from: timestamp));
            }
        default:
            break;
        }
        return super.prepareTooltip(item: item);
    }
    
    fileprivate func messageBody(item: ConversationEntry, message: String) -> String {
        guard let msg = item.options.encryption.message() else {
            switch item.state {
            case .incoming_error(_, let errorMessage), .outgoing_error(_, let errorMessage):
                if let error = errorMessage {
                    return "\(message)\n-----\n\(error)"
                }
            default:
                break;
            }
            return message;
        }
        return msg;
    }
        
    override func layout() {
        super.layout();
        self.message.invalidateIntrinsicContentSize();
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

}
