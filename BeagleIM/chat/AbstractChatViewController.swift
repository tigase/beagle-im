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

    var chat: DBChatProtocol! {
        didSet {
            conversationLogController?.chat = chat;
        }
    }
    var account: BareJID! {
        return chat.account;
    }
    
    var jid: BareJID! {
        return chat.jid.bareJid;
    }

    private(set) var dataSource: ChatViewDataSource!;
    
    @IBOutlet var messageFieldScroller: NSScrollView!;
    @IBOutlet var messageField: AutoresizingTextView!;
    @IBOutlet var messageFieldScrollerHeight: NSLayoutConstraint!;
    var conversationLogController: ConversationLogController? {
        didSet {
            self.conversationLogController?.logTableViewDelegate = conversationTableViewDelegate();
            self.conversationLogController?.chat = self.chat;
            self.dataSource = self.conversationLogController?.dataSource;
        }
    }
    
    var scrollChatToMessageWithId: Int?;
                
    override func viewDidLoad() {
        super.viewDidLoad();
        self.messageField.delegate = self;
        self.messageField.isContinuousSpellCheckingEnabled = Settings.spellchecking.bool();
        self.messageField.isGrammarCheckingEnabled = Settings.spellchecking.bool();
    }
    
    override func viewWillAppear() {
        self.conversationLogController?.scrollChatToMessageWithId = self.scrollChatToMessageWithId;
        self.scrollChatToMessageWithId = nil
        super.viewWillAppear();
        self.messageField?.placeholderAttributedString = account != nil ? NSAttributedString(string: "from \(account.stringValue)...", attributes: [.foregroundColor: NSColor.placeholderTextColor]) : nil;
        
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
    }
    
    override func viewWillDisappear() {
        super.viewWillDisappear();
        if let account = self.account, let jid = self.jid {
            let draft = self.messageField.string;
            DBChatStore.instance.storeMessage(draft: draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft, for: account, with: jid);
        }
    }
    
    override func viewDidAppear() {
        super.viewDidAppear();
        //DispatchQueue.main.async {
            if !NSEvent.modifierFlags.contains(.shift) {
                self.view.window?.makeFirstResponder(self.messageField);
            }
        //}
    }
    
    func conversationTableViewDelegate() -> NSTableViewDelegate? {
        return nil;
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
                guard self.send(message: msg) else {
                    return;
                }
                self.messageField.reset();
                self.updateMessageFieldSize();
            }
            return true;
        default:
            return false;
        }
    }
        
    func send(message: String) -> Bool {
        return false;
    }
    
    func sendAttachment(originalUrl: URL, uploadedUrl: URL, filesize: Int64, mimeType: String?) -> Bool {
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

class DeletedMessage: ChatViewItemProtocol {
    
    let id: Int;
    let account: BareJID;
    let jid: BareJID;
    
    let timestamp: Date = Date();
    let state: MessageState = .outgoing;
    let encryption: MessageEncryption = .none;
    let encryptionFingerprint: String? = nil;

    init(id: Int, account: BareJID, jid: BareJID) {
        self.id = id;
        self.account = account;
        self.jid = jid;
    }
    
    func isMergeable(with item: ChatViewItemProtocol) -> Bool {
        return false;
    }
    
}

class SystemMessage: ChatViewItemProtocol {
    let id: Int;
    let account: BareJID;
    let jid: BareJID;
    let timestamp: Date;
    let state: MessageState;
    let encryption: MessageEncryption = .none;
    let encryptionFingerprint: String? = nil;
    let kind: Kind;
    
    init(nextItem item: ChatViewItemProtocol, kind: Kind) {
        id = item.id;
        timestamp = item.timestamp.addingTimeInterval(-0.001);
        account = item.account;
        jid = item.jid;
        state = .incoming;
        self.kind = kind;
    }
    
    func isMergeable(with item: ChatViewItemProtocol) -> Bool {
        return false;
    }

    enum Kind {
        case unreadMessages
    }
}
