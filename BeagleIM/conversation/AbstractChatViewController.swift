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
import MapKit

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
    
    @IBOutlet var bottomView: NSStackView!;
    var messageFieldScroller: RoundedScrollView!;
    var messageField: AutoresizingTextView!;
    private var messageFieldScrollerHeight: NSLayoutConstraint!;
    private var bottomViewHeight: NSLayoutConstraint!;
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
        self.messageField = AutoresizingTextView();
        self.messageField.setup();
        self.messageField.isVerticallyResizable = true;
//        self.messageField.isHorizontallyResizable = true;
        self.messageField.autoresizingMask = [.height, .width];
        self.messageField.translatesAutoresizingMaskIntoConstraints = true;
        self.messageField.drawsBackground = false;
        self.messageField.isEditable = true;
        self.messageField.isRichText = false;
        self.messageField.allowsUndo = true;
        self.messageField.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .light);
        self.messageFieldScroller = RoundedScrollView();
        self.messageFieldScroller.borderType = .noBorder;
        self.messageFieldScroller.backgroundColor = NSColor(named: "chatBackgroundColor")!;
        self.messageFieldScroller.automaticallyAdjustsContentInsets = false;
        self.messageFieldScroller.contentInsets = NSEdgeInsets(top: 6, left: 11, bottom: 6, right: 11)
        self.messageFieldScroller.hasVerticalScroller = true;
        self.messageFieldScroller.autohidesScrollers = true;
        self.messageFieldScroller.drawsBackground = false;
        self.messageFieldScroller.documentView = messageField;
        self.messageFieldScroller.autoresizingMask = [.width, .height];
        self.messageFieldScroller.setContentHuggingPriority(.defaultHigh, for: .vertical);
        self.messageFieldScroller.setContentHuggingPriority(.defaultHigh, for: .horizontal);
        self.messageFieldScroller.setContentCompressionResistancePriority(.defaultHigh, for: .vertical);
        self.messageFieldScroller.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);
        self.messageFieldScrollerHeight = messageFieldScroller.heightAnchor.constraint(equalToConstant: 0);
        bottomView.addView(messageFieldScroller, in: .center);
        bottomViewHeight = bottomView.heightAnchor.constraint(equalTo: messageFieldScroller.heightAnchor, constant: 2 * 10);
        NSLayoutConstraint.activate([self.messageFieldScrollerHeight, self.bottomViewHeight]);
        bottomView.spacing = 6;
        bottomView.edgeInsets = NSEdgeInsets(top: 10, left: 10, bottom: 10, right: 10);
        bottomView.setHuggingPriority(.defaultHigh, for: .horizontal);
        bottomView.setHuggingPriority(.defaultHigh, for: .vertical);
        super.viewDidLoad();
        self.messageField.delegate = self;
        self.messageField.isContinuousSpellCheckingEnabled = Settings.spellchecking;
        self.messageField.isGrammarCheckingEnabled = Settings.spellchecking;
    }
    
    @objc func test(_ sender: Any) {
        
    }
    
    override func viewWillAppear() {
        super.viewWillAppear();
        self.messageField?.placeholderAttributedString = account != nil ? NSAttributedString(string: String.localizedStringWithFormat(NSLocalizedString("from %@...", comment: "placehoder of message entry field"), account.stringValue), attributes: [.foregroundColor: NSColor.placeholderTextColor, .font: NSFont.systemFont(ofSize: NSFont.systemFontSize)]) : nil;
        
        self.updateMessageFieldSize();
        self.messageFieldScroller.cornerRadius = messageFieldScrollerHeight.constant / 2;
                
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
    
    func startMessageCorrection(message: String, originId: String) {
        correctedMessageOriginId = originId;
        self.messageField.string = message;
        self.updateMessageFieldSize();
    }
    
    func textDidChange(_ notification: Notification) {
        self.updateMessageFieldSize();
        self.messageField.complete(nil);
    }
        
    func send(message: String, correctedMessageOriginId: String?) -> Bool {
        return false;
    }
        
    func updateMessageFieldSize() {
        let height = min(max(messageField.intrinsicContentSize.height, 14), 100) + self.messageFieldScroller.contentInsets.top + self.messageFieldScroller.contentInsets.bottom;// + (messageFieldScroller.borderWidth * 2);
        self.messageFieldScrollerHeight.constant = height;
    }
       
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let destination = segue.destinationController as? ConversationLogController {
            self.conversationLogController = destination;
        }
    }
    
    func prepareConversationLogContextMenu(dataSource: ConversationDataSource, menu: NSMenu, forRow row: Int) {
        if row != NSNotFound || (self.conversationLogController?.selectionManager.hasSelection ?? false) {
            let reply = menu.addItem(withTitle: NSLocalizedString("Reply", comment: "context menu item"), action: #selector(replySelectedMessages), keyEquivalent: "");
            reply.target = self
            reply.tag = row;
            if #available(macOS 11.0, *) {
                reply.image = NSImage(systemSymbolName: "arrowshape.turn.up.left", accessibilityDescription: "reply")
            }
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
    
    @objc func showMap(_ sender: NSMenuItem) {
        let tag = sender.tag;
        guard tag >= 0 else {
            return
        }
        
        guard let item = dataSource.getItem(withId: tag) else {
            return;
        }
        
        guard case let .location(coordinate) = item.payload else {
            return;
        }
        let placemark = MKPlacemark(coordinate: coordinate);
        let region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000);
        let mapItem = MKMapItem(placemark: placemark);
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: region.center),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: region.span)
        ])
    }
    
    var suggestionsController: SuggestionsWindowController?;
    
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            if suggestionsController?.window?.isVisible ?? false {
                suggestionsController?.moveUp(textView);
                return true
            }
        case #selector(NSResponder.moveDown(_:)):
            if suggestionsController?.window?.isVisible ?? false {
                suggestionsController?.moveDown(textView);
                return true
            }
        case #selector(NSResponder.cancelOperation(_:)):
            if suggestionsController?.window?.isVisible ?? false {
                suggestionsController?.cancelSuggestions();
                return true;
            } else {
                return false;
            }
        case #selector(NSResponder.insertNewline(_:)):
            if let controller = suggestionsController, controller.window?.isVisible ?? false {
                suggestionItemSelected(sender: controller);
                return true;
            } else {
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
            }
        case #selector(NSResponder.deleteToBeginningOfLine(_:)):
            guard textView.textStorage?.length ?? 0 == 0 else {
                return false;
            }
            NotificationCenter.default.post(name: ChatsListViewController.CLOSE_SELECTED_CHAT, object: nil);
            return true;
        default:
            break;
        }
        return false;
    }
    
    func textView(_ textView: NSTextView, completions words: [String], forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>?) -> [String] {
        guard charRange.length != 0 && charRange.location != NSNotFound else {
            suggestionsController?.cancelSuggestions();
            return [];
        }

        let tmp = textView.string;
        let utf16 = tmp.utf16;
        let start = utf16.index(utf16.startIndex, offsetBy: charRange.lowerBound);
        let end = utf16.index(utf16.startIndex, offsetBy: charRange.upperBound);
        guard let query = String(utf16[start..<end]) else {
            suggestionsController?.cancelSuggestions();
            return [];
        }

        let suggestions: [Any] = prepareCompletions(for: query);

        index?.initialize(to: -1);//suggestions.isEmpty ? -1 : 0);

        if suggestions.isEmpty {
            suggestionsController?.cancelSuggestions();
        } else {
            if suggestionsController == nil {
                suggestionsController = SuggestionsWindowController(viewProviders: suggestionProviders, edge: .top);
                suggestionsController?.backgroundColor = NSColor.textBackgroundColor;
                suggestionsController?.target = self;
                suggestionsController?.action = #selector(self.suggestionItemSelected(sender:))
            }
            let range = NSRange(location: charRange.location, length: charRange.length)
            DispatchQueue.main.async {
                self.suggestionsController?.beginFor(textView: textView, range: range);
                self.suggestionsController?.update(suggestions: suggestions);
            }
        }
        
        return [];
    }
    
    func prepareCompletions(for query: String) -> [Any] {
        if Settings.suggestEmoticons, let face = EmojiFaces.search(contains: query) {
            return [face];
        }

        guard query.first == ":" else {
            return [];
        }
        
        let q = String(query.dropFirst());
        guard !q.isEmpty else {
            return [];
        }
        return Array(EmojiShortcodes.search(contains: q));
    }
    
    @objc func suggestionItemSelected(sender: Any) {
        guard let item = (sender as? SuggestionsWindowController)?.selected, let range = (sender as? SuggestionsWindowController)?.range else {
            return;
        }

        suggestionSelected(item: item, range: range);
        
        suggestionsController?.cancelSuggestions();
    }
    
    var suggestionProviders: [SuggestionItemViewProvider] = [EmojiShortcodeSuggestionItemView.Provider(),EmojiFaceSuggestionItemView.Provider()];
    
    func suggestionSelected(item: Any, range: NSRange) {
        switch item {
        case let key as String:
            self.messageField.replaceCharacters(in: range, with: EmojiShortcodes.emoji(for: key) ?? "");
        case let key as EmojiFace:
            self.messageField.replaceCharacters(in: range, with: key.value);
        default:
            break;
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

class EmojiShortcodeSuggestionItemView: SuggestionItemViewBase<String> {
    
    struct Provider: SuggestionItemViewProvider {
        
        func view(for item: Any) -> SuggestionItemView? {
            guard item is String else {
                return nil;
            }
            return EmojiShortcodeSuggestionItemView();
        }
        
    }
    
    override var itemHeight: Int {
        return 24;
    }
    
    override var item: String? {
        didSet {
            if let key = item {
                emoji.stringValue = EmojiShortcodes.emoji(for: key) ?? "";
                label.stringValue = key;
            } else {
                emoji.stringValue = "";
                label.stringValue = "";
            }
            
        }
    }
    
    let emoji: NSTextField;
    let label: NSTextField;
    let stack: NSStackView;
    
    required init() {
        emoji = NSTextField(labelWithString: "");
        emoji.cell?.truncatesLastVisibleLine = false;
        emoji.cell?.lineBreakMode = .byWordWrapping;
        emoji.cell?.alignment = .center;
        emoji.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);

        label = NSTextField(labelWithString: "");
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium);
        label.cell?.truncatesLastVisibleLine = true;
        label.cell?.lineBreakMode = .byTruncatingTail;
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        
        stack = NSStackView(views: [emoji, label]);
        stack.translatesAutoresizingMaskIntoConstraints = false;
        stack.spacing = 6;
        stack.alignment = .centerY;
        stack.orientation = .horizontal;
        stack.distribution = .fill;
//            stack.setHuggingPriority(.defaultHigh, for: .vertical);
        stack.setHuggingPriority(.defaultHigh, for: .horizontal);
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack.visibilityPriority(for: emoji);
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4);
        NSLayoutConstraint.activate([
            emoji.heightAnchor.constraint(equalToConstant: 20),
            emoji.widthAnchor.constraint(equalToConstant: 28),
            emoji.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 1.0, constant: -2 * 2),
            label.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2)
        ])

        super.init();

        emoji.font = NSFont.systemFont(ofSize: 20/1.2);
        
        addSubview(stack);
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            self.topAnchor.constraint(equalTo: stack.topAnchor),
            self.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

class EmojiFaceSuggestionItemView: SuggestionItemViewBase<EmojiFace> {
    
    struct Provider: SuggestionItemViewProvider {
        
        func view(for item: Any) -> SuggestionItemView? {
            guard item is EmojiFace else {
                return nil;
            }
            return EmojiFaceSuggestionItemView();
        }
        
    }
    
    override var itemHeight: Int {
        return 24;
    }
    
    override var item: EmojiFace? {
        didSet {
            if let key = item {
                emoji.stringValue = key.value;
                label.stringValue = key.key;
            } else {
                emoji.stringValue = "";
                label.stringValue = "";
            }
            
        }
    }
    
    let emoji: NSTextField;
    let label: NSTextField;
    let stack: NSStackView;
    
    required init() {
        emoji = NSTextField(labelWithString: "");
        emoji.cell?.truncatesLastVisibleLine = false;
        emoji.cell?.lineBreakMode = .byWordWrapping;
        emoji.cell?.alignment = .center;
        emoji.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal);

        label = NSTextField(labelWithString: "");
        label.font = NSFont.systemFont(ofSize: NSFont.systemFontSize - 1, weight: .medium);
        label.cell?.truncatesLastVisibleLine = true;
        label.cell?.lineBreakMode = .byTruncatingTail;
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        
        stack = NSStackView(views: [emoji, label]);
        stack.translatesAutoresizingMaskIntoConstraints = false;
        stack.spacing = 6;
        stack.alignment = .centerY;
        stack.orientation = .horizontal;
        stack.distribution = .fill;
//            stack.setHuggingPriority(.defaultHigh, for: .vertical);
        stack.setHuggingPriority(.defaultHigh, for: .horizontal);
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack.visibilityPriority(for: emoji);
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4);
        NSLayoutConstraint.activate([
            emoji.heightAnchor.constraint(equalToConstant: 20),
            emoji.widthAnchor.constraint(equalToConstant: 28),
            emoji.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 1.0, constant: -2 * 2),
            label.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -2)
        ])

        super.init();

        emoji.font = NSFont.systemFont(ofSize: 20/1.2);
        
        addSubview(stack);
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            self.topAnchor.constraint(equalTo: stack.topAnchor),
            self.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
