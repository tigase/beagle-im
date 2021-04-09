//
// AbstractChatViewController.swift
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
import TigaseSwift

class AbstractChatViewController: NSViewController, NSTextViewDelegate {

    var conversation: Conversation! {
        didSet {
            conversationLogController?.conversation = conversation;
        }
    }
    var account: BareJID! {
        return conversation.account;
    }
    
    var jid: BareJID! {
        return conversation.jid;
    }

    private(set) var dataSource: ConversationDataSource!;
    
    @IBOutlet var messageFieldScroller: NSScrollView!;
    @IBOutlet var messageField: AutoresizingTextView!;
    @IBOutlet var messageFieldScrollerHeight: NSLayoutConstraint!;
    var conversationLogController: ConversationLogController? {
        didSet {
            self.conversationLogController?.conversation = self.conversation;
            self.dataSource = self.conversationLogController?.dataSource;
        }
    }
        
    private(set) var correctedMessageOriginId: String?;
                
    override var acceptsFirstResponder: Bool {
        return true;
    }
    
    override func keyDown(with event: NSEvent) {
        guard event.specialKey == nil else {
            return;
        }
    
        self.view.window?.makeFirstResponder(messageField);
        messageField.keyDown(with: event);
    }
    
    override func viewDidLoad() {
        print("AbstractChatViewController::viewDidLoad() - begin")
        super.viewDidLoad();
        self.messageField.delegate = self;
        self.messageField.isContinuousSpellCheckingEnabled = Settings.spellchecking;
        self.messageField.isGrammarCheckingEnabled = Settings.spellchecking;
        print("AbstractChatViewController::viewDidLoad() - end")
    }
    
    override func viewWillAppear() {
        print("AbstractChatViewController::viewWillAppear() - begin")
        super.viewWillAppear();
        self.messageField?.placeholderAttributedString = account != nil ? NSAttributedString(string: "from \(account.stringValue)...", attributes: [.foregroundColor: NSColor.placeholderTextColor, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]) : nil;
        
        self.updateMessageFieldSize();
                
        DBChatStore.instance.messageDraft(for: account, with: jid, completionHandler: { draft in
            guard let text = draft else {
                return;
            }
            DispatchQueue.main.async {
                self.messageField.string = text;
                self.updateMessageFieldSize();
            }
        });
        print("AbstractChatViewController::viewWillAppear() - end")
    }
    
    override func viewWillDisappear() {
        print("AbstractChatViewController::viewWillDisappear() - begin")
        super.viewWillDisappear();
        if let account = self.account, let jid = self.jid {
            let draft = self.messageField.string;
            DBChatStore.instance.storeMessage(draft: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft, for: account, with: jid);
        }
        print("AbstractChatViewController::viewWillDisappear() - end")
    }
    
    override func viewDidAppear() {
        print("AbstractChatViewController::viewDidAppear() - begin")
        super.viewDidAppear();
        //DispatchQueue.main.async {
            if !NSEvent.modifierFlags.contains(.shift) {
                self.view.window?.makeFirstResponder(self.messageField);
            }
        //}
        print("AbstractChatViewController::viewDidAppear() - end")
    }
    
    func startMessageCorrection(message: String, originId: String) {
        correctedMessageOriginId = originId;
        self.messageField.string = message;
        self.updateMessageFieldSize();
    }
    
    func textDidChange(_ notification: Notification) {
        self.updateMessageFieldSize();
    }
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.deleteToBeginningOfLine(_:)):
            guard textView.textStorage?.length ?? 0 == 0 else {
                return false;
            }
            NotificationCenter.default.post(name: ChatsListViewController.CLOSE_SELECTED_CHAT, object: nil);
            return true;
        case #selector(NSResponder.insertNewline(_:)):
            guard !NSEvent.modifierFlags.contains(.shift) else {
                return false;
            }
            DispatchQueue.main.async {
                let msg = textView.string;
                guard !msg.isEmpty else {
                    return;
                }
                guard self.send(message: msg, correctedMessageOriginId: self.correctedMessageOriginId) else {
                    return;
                }
                self.messageField.reset();
                self.correctedMessageOriginId = nil;
                self.updateMessageFieldSize();
            }
            return true;
        default:
            return false;
        }
    }
        
    func send(message: String, correctedMessageOriginId: String?) -> Bool {
        return false;
    }
        
    func updateMessageFieldSize() {
        let height = min(max(messageField.intrinsicContentSize.height, 14), 100) + self.messageFieldScroller.contentInsets.top + self.messageFieldScroller.contentInsets.bottom;
        self.messageFieldScrollerHeight.constant = height;
    }
       
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let destination = segue.destinationController as? ConversationLogController {
            self.conversationLogController = destination;
        }
    }
    
    func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int) {
        if row != NSNotFound || (self.conversationLogController?.selectionManager.hasSelection ?? false) {
            let reply = menu.addItem(withTitle: "Reply", action: #selector(replySelectedMessages), keyEquivalent: "");
            reply.target = self
            reply.tag = row;
        }
    }
    
    @objc func replySelectedMessages(_ sender: Any) {
        guard let texts = self.conversationLogController?.selectionManager.selection?.selectedTexts else {
            return;
        }
        
        // need to insert "> " on any "\n"
        let text: String = prepareReply(from: texts);
        let current = messageField.string;
        self.messageField.string = current.isEmpty ? "\(text)\n" : "\(current)\n\(text)\n";
        self.updateMessageFieldSize();
    }
    
    func prepareReply(from items: [NSAttributedString]) -> String {
        return items.flatMap { $0.string.split(separator: "\n")}.map {
            if $0.starts(with: ">") {
                return ">\($0)";
            } else {
                return "> \($0)"
            }
        }.joined(separator: "\n");
    }
}

extension NSTextField {
 
    func characterIndexFor(event: NSEvent) -> CharacterRange? {
        guard let contentView = event.window?.contentView else {
            return nil;
        }
        
        let textContainer:NSTextContainer = NSTextContainer.init()
        let layoutManager:NSLayoutManager = NSLayoutManager.init()
        let textStorage:NSTextStorage = NSTextStorage.init()
        layoutManager.addTextContainer(textContainer);
        textStorage.addLayoutManager(layoutManager);

        layoutManager.typesetterBehavior = .latestBehavior;
        textContainer.lineFragmentPadding = 2;
        textContainer.maximumNumberOfLines = self.maximumNumberOfLines;
        textContainer.lineBreakMode = self.lineBreakMode;
        
        textContainer.size = self.cell?.titleRect(forBounds: self.bounds).size ?? .zero;
        
        textStorage.beginEditing();
        textStorage.setAttributedString(self.attributedStringValue);
        textStorage.addAttribute(.font, value: self.font!, range: NSRange(location: 0, length: textStorage.length));
        textStorage.endEditing();
        
        layoutManager.glyphRange(for: textContainer);
        
        let point = contentView.convert(event.locationInWindow, from: nil);
        let textPoint1 = convert(point, from: contentView);
        let textPoint = NSPoint(x: textPoint1.x, y: textPoint1.y);// y: textPoint1.y / 1.0666);
        
        var distance: CGFloat = 0;
        //let idx = layoutManager.characterIndex(for: textPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: &distance);
        let idx = layoutManager.glyphIndex(for: textPoint, in: textContainer, fractionOfDistanceThroughGlyph: &distance);
        let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: idx, length: 1), in: textContainer);
        guard rect.contains(textPoint) else {
            return nil;
        }
        let charIdx = layoutManager.characterIndexForGlyph(at: idx);
        
        var nextIdx = idx;
        while nextIdx < layoutManager.numberOfGlyphs - 1 {
            nextIdx = nextIdx + 1;
            let nextRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: nextIdx, length: 1), in: textContainer);
            if !nextRect.equalTo(rect) {
                let nextCharIdx = layoutManager.characterIndexForGlyph(at: nextIdx);
                return CharacterRange(location: charIdx, length: nextCharIdx - charIdx);
            }
        }
        
        return CharacterRange(location: charIdx, length: self.attributedStringValue.length - charIdx);
//        var nextIdx = idx;
//
//        if idx < layoutManager.numberOfGlyphs - 1 {
//            let nextCharIdx = layoutManager.characterIndexForGlyph(at: idx + 1);
//            let str = self.attributedStringValue;
//            let tmp = str.attributedSubstring(from: NSRange(location: charIdx, length: nextCharIdx - charIdx));
//            print("char:", charIdx, "next:", nextCharIdx, "tmp:", tmp);
//            return (charIdx, nextCharIdx - charIdx);
//        } else {
//            return (charIdx, self.attributedStringValue.length - charIdx);
//        }
    }
    
    class CharacterRange: Comparable {
        
        let location: Int;
        let length: Int;
        var lowerBound: Int {
            return location;
        }
        var upperBound: Int {
            return location + length;
        }
        
        init(location: Int, length: Int) {
            self.location = location;
            self.length = length;
        }
        
    }
}

func < (lhs: NSTextField.CharacterRange, rhs: NSTextField.CharacterRange) -> Bool {
    return lhs.location < rhs.location;
}

func == (lhs: NSTextField.CharacterRange, rhs: NSTextField.CharacterRange) -> Bool {
    return lhs.location == rhs.location;
}
