//
// Markdown.swift
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
import TigaseLogging

extension unichar: ExpressibleByUnicodeScalarLiteral {
    public typealias UnicodeScalarLiteralType = UnicodeScalar
    
    public init(unicodeScalarLiteral value: UnicodeScalar) {
        self.init(value.value);
    }
}

class Markdown {
    
    class ParagraphStyle: NSMutableParagraphStyle {
        
        var type: `Type`?;
        
        enum `Type` {
            case quote
            case code
            case list
        }
    }
    
    static let quoteParagraphStyle: NSParagraphStyle = {
        var paragraphStyle = ParagraphStyle();
        paragraphStyle.type = .quote;
        paragraphStyle.headIndent = 16;
        paragraphStyle.firstLineHeadIndent = 4;
        paragraphStyle.alignment = .natural;
        return paragraphStyle;
    }();
    
    static let codeParagraphStyle: NSParagraphStyle = {
        var paragraphStyle = ParagraphStyle();
        paragraphStyle.type = .code;
        paragraphStyle.headIndent = 10;
        paragraphStyle.tailIndent = -10;
        paragraphStyle.firstLineHeadIndent = 10;
        paragraphStyle.alignment = .natural;
        return paragraphStyle;
    }();
    
    static let listParagraphStyle: NSParagraphStyle = {
        var paragraphStyle = ParagraphStyle();
        paragraphStyle.type = .list;
        paragraphStyle.headIndent = 22;
        paragraphStyle.alignment = .natural;
        paragraphStyle.paragraphSpacingBefore = 5;
        paragraphStyle.firstLineHeadIndent = 10;
        return paragraphStyle;
    }();
    
    static let listParagraphContinuationStyle: NSParagraphStyle = {
        var paragraphStyle = ParagraphStyle();
        paragraphStyle.type = .list;
        paragraphStyle.headIndent = 22;
        paragraphStyle.alignment = .natural;
        paragraphStyle.firstLineHeadIndent = 22;
        return paragraphStyle;
    }();
    
    static let NEW_LINE: unichar = "\n";
    static let GT_SIGN: unichar = ">";
    static let SPACE: unichar = " ";
    static let ASTERISK: unichar = "*";
    static let UNDERSCORE: unichar = "_";
    static let GRAVE_ACCENT: unichar = "`";
    static let CR_SIGN: unichar = "\r";
    static let DOT: unichar = ".";
    static let MINUS: unichar = "-";
    
    static let ZERO: unichar = "0";
    static let ONE: unichar = "1";
    static let TWO: unichar = "2";
    static let THREE: unichar = "3";
    static let FOUR: unichar = "4";
    static let FIVE: unichar = "5";
    static let SIX: unichar = "6";
    static let SEVEN: unichar = "7";
    static let EIGHT: unichar = "8";
    static let NINE: unichar = "9";
    
    static let TILDE: unichar = "~";

    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Markdown");
        
    static func isNumber(_ c: unichar) -> Bool {
        return c >= 48 && c <= 57;
    }
        
    static var usedTime: Int = 0;
    
    enum ListMarker {
        case number
        case minus
        case asterisk
    }
    
    static func applyStyling(attributedString msg: NSMutableAttributedString, fontSize: CGFloat, showEmoticons: Bool) {
        let start = Date();
        
        let stylingColor = NSColor(calibratedWhite: 0.5, alpha: 1.0);
        
        var message = msg.string as NSString;
        
        var boldStart: Int? = nil;
        var italicStart: Int? = nil;
        var underlineStart: Int? = nil;
        var quoteStart: Int? = nil;
        var quoteLevel = 0;
        var listStart: Int? = nil;
        var crossOutStart: Int? = nil;
        var idx = 0;
        
        var canStart = true;
        var listMarker: ListMarker?;
        
        var wordIdx: Int? = showEmoticons ? 0 : nil;
        
        msg.removeAttribute(.paragraphStyle, range: NSRange(location: 0, length: msg.length));
        
        while idx < message.length {
            let c = message.character(at: idx);
            switch c {
            case GT_SIGN:
                if quoteStart == nil && (idx == 0 || message.character(at: idx-1) == NEW_LINE) {
                    let start = idx;
                    while idx < message.length, message.character(at: idx) == GT_SIGN {
                        idx = idx + 1;
                    }
                    if idx < message.length && message.character(at: idx) == SPACE {
                        quoteStart = start;
                        quoteLevel = idx - start;
                        msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: start, length: idx - start));
                    } else {
                        idx = idx - 1;
                    }
                }
            case ASTERISK:
                if let nextChar = idx + 1 < message.length ? message.character(at: idx + 1) : nil {
                    if nextChar == ASTERISK {
                        if boldStart == nil {
                            if canStart {
                                boldStart = idx;
                            }
                        } else {
                            msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: boldStart!, length: (idx+2) - idx));
                            msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: (idx+2) - idx));
                            
                            msg.applyFontTraits(.boldFontMask, range: NSRange(location: boldStart!, length: (idx+2) - boldStart!));
                            boldStart = nil;
                        }
                        canStart = true;
                        idx = idx + 1;
                        break;
                    } else if nextChar == SPACE && listStart == nil && (idx == 0 || message.character(at: idx-1) == NEW_LINE) {
                        listStart = idx;
                        listMarker = .asterisk;
                        msg.applyFontTraits(.boldFontMask, range: NSRange(location: idx, length: 1));
                        break;
                    }
                }
                
                if italicStart == nil {
                    if canStart {
                        italicStart = idx;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: italicStart!, length: 1));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: 1));
                    
                    msg.applyFontTraits(.italicFontMask, range: NSRange(location: italicStart!, length: (idx+1) - italicStart!));
                    italicStart = nil;
                }
                canStart = true;
            case MINUS:
                if listStart == nil && canStart && (idx == 0 || message.character(at: idx-1) == NEW_LINE) && ((idx + 1) < message.length && message.character(at: idx + 1) == SPACE) {
                    listStart = idx;
                    listMarker = .minus;
                    msg.applyFontTraits(.boldFontMask, range: NSRange(location: idx, length: 1));
                }
            case TILDE:
                if crossOutStart == nil {
                    if canStart && idx + 2 < message.length && message.character(at: idx + 1) == TILDE {
                        crossOutStart = idx;
                        idx = idx + 1;
                    }
                } else if idx + 1 < message.length && message.character(at: idx + 1) == TILDE {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: crossOutStart!, length: 2));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: 2));
                    msg.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.thick.rawValue, range: NSRange(location: crossOutStart! + 2, length: (idx - (crossOutStart! + 2))));
                    idx = idx + 1;
                    crossOutStart = nil;
                }
                canStart = true;
            case UNDERSCORE:
                if underlineStart == nil {
                    if canStart {
                        underlineStart = idx;
                    }
                } else {
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: underlineStart!, length: 1));
                    msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: idx, length: 1));
                    
                    msg.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: underlineStart! + 1, length: idx - (underlineStart! + 1)));
                    underlineStart = nil;
                }
                canStart = true;
            case GRAVE_ACCENT:
//                if codeStart == nil {
                    if canStart {
                        let codeStart = idx;
                        let isBlock = 0 == idx || (message.character(at: idx-1) == NEW_LINE) || (idx > 3 && message.length > (idx + 1) && message.character(at: idx + 1) == SPACE && message.character(at: idx-2) == GT_SIGN && (0 == idx - 3 || message.character(at: idx - 3) == NEW_LINE));
                        wordIdx = nil;
                        while idx < message.length, message.character(at: idx) == "`" {
                            idx = idx + 1;
                        }
                        let codeCount = idx - codeStart;
                        
                        var count = 0;
                        while idx < message.length {
                            if message.character(at: idx) == GRAVE_ACCENT {
                                count = count + 1;
                                if count == codeCount {
                                    let tmp = idx + 1;
                                    if tmp == message.length || [" ", "\n"].contains(message.character(at: tmp)) {
                                        break;
                                    }
                                }
                            } else {
                                count = 0;
                            }
                            idx = idx + 1;
                        }
                        if codeCount != count {
                            idx = codeStart + codeCount;
                        } else {
                            msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: codeStart, length: codeCount));
                            msg.addAttribute(.foregroundColor, value: stylingColor, range: NSRange(location: (idx+1)-codeCount, length: codeCount));

                            msg.applyFontTraits([.fixedPitchFontMask, .unboldFontMask, .unitalicFontMask], range: NSRange(location: codeStart, length: idx - codeStart));
                            if isBlock {
                                msg.addAttribute(.paragraphStyle, value: codeParagraphStyle, range: NSRange(location: codeStart, length: idx - codeStart));
                            }
                            msg.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular), range: NSRange(location: codeStart, length: (idx+1) - codeStart));
                                                        
                            if idx - codeStart > 1 {
                                let clearRange = NSRange(location: codeStart + codeCount, length: idx - (codeStart + (2*codeCount)));
                                msg.removeAttribute(.foregroundColor, range: clearRange);
                                msg.removeAttribute(.underlineStyle, range: clearRange);
                                //msg.addAttribute(.foregroundColor, value: textColor ?? NSColor.textColor, range: clearRange);
                            }
                            
                            if idx == message.length {
                                wordIdx = message.length;
                            } else {
                                wordIdx = idx + 1;
                            }
                        }
                    }
//                } else {
//                }
                canStart = true;
            case CR_SIGN, NEW_LINE, SPACE:
                if showEmoticons {
                    if wordIdx != nil && wordIdx! != idx {
                        // something is wrong, it looks like IDX points to replaced value!
                        let range = NSRange(location: wordIdx!, length: idx - wordIdx!);
                        if let emoji = String.emojis[message.substring(with: range)] {
                            let len = message.length;
                            msg.replaceCharacters(in: range, with: emoji);
                            message = msg.string as NSString;
                            let diff = message.length - len;
                            idx = idx + diff;
                        }
                    }
                    if idx < message.length {
                        wordIdx = idx + 1;
                    } else {
                        wordIdx = message.length;
                    }
                }
                if NEW_LINE == c {
                    boldStart = nil;
                    underlineStart = nil;
                    italicStart = nil
                    if (quoteStart != nil) {
                        logger.debug("quote level: \(quoteLevel)");
                        if idx < message.length {
                            let range = NSRange(location: quoteStart!, length: idx - quoteStart!);
                            logger.debug("message possibly causing a crash: \(message), range: \(range), length: \(message.length)");
                            msg.addAttribute(.paragraphStyle, value: Markdown.quoteParagraphStyle, range: range);
                        }
                        quoteStart = nil;
                    }
                    if listStart != nil {
                        if let paragraphStyle = listParagraphStyle(for: message, startAt: listStart, listMarker: listMarker) {
                            let range = NSRange(location: listStart!, length: idx - listStart!);
                            msg.addAttribute(.paragraphStyle, value: paragraphStyle, range: range);
                        }
                        listStart = nil;

                        if idx + 1 < message.length && message.character(at: idx + 1) != NEW_LINE  {
                            if isContinuation(char: message.character(at: idx + 1), listMarker: listMarker!) {
                                listStart = idx + 1;
                            }
                        } else {
                            listMarker = nil;
                        }
                    }
                }
                canStart = true;
            case ZERO, ONE, TWO, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE:
                if listStart == nil && (idx == 0 || message.character(at: idx - 1) == NEW_LINE) {
                    var nidx = idx + 1;
                    var hadDot = false;
                    while nidx < message.length {
                        let c1 = message.character(at: nidx);
                        if hadDot {
                            if c1 != SPACE {
                                // not a valid list!
                                break
                            } else {
                                // we have found a list!
                                listMarker = .number;
                                listStart = idx;
                                msg.applyFontTraits(.boldFontMask, range: NSRange(location: idx, length: (nidx - idx) - 1));
                                idx = nidx - 1;
                                break;
                            }
                        } else {
                            if c1 == DOT {
                                hadDot = true;
                            } else if isNumber(c1) {
                                // ok, still a number..
                            } else {
                                // not a valid list!
                                break;
                            }
                        }
                        nidx = nidx + 1;
                    }
                }
                canStart = false;
                break;
            default:
                canStart = false;
                break;
            }
            if idx < message.length {
                idx = idx + 1;
            }
        }

        if (quoteStart != nil) {
            msg.addAttribute(.paragraphStyle, value: Markdown.quoteParagraphStyle, range: NSRange(location: quoteStart!, length: (idx - quoteStart!)-1));
            quoteStart = nil;
        }

        if (listStart != nil) {
            if let paragraphStyle = listParagraphStyle(for: message, startAt: listStart, listMarker: listMarker) {
                let range = NSRange(location: listStart!, length: (idx - listStart!) - 1);
                msg.addAttribute(.paragraphStyle, value: paragraphStyle, range: range);
            }
            listStart = nil;
        }

        if showEmoticons && wordIdx != nil && wordIdx! != idx {
            let range = NSRange(location: wordIdx!, length: idx - wordIdx!);
            if let emoji = String.emojis[message.substring(with: range)] {
                msg.replaceCharacters(in: range, with: emoji);
                message = msg.string as NSString;
            }
        }
        
        let end = Date();
        usedTime = usedTime + Int((end.timeIntervalSince1970 - start.timeIntervalSince1970) * 1000);
        logger.debug("time used for markdown parsing: \(usedTime)");
    }
    
    static func listParagraphStyle(for message: NSString, startAt: Int?, listMarker: ListMarker?) -> NSParagraphStyle? {
        guard let startAt = startAt, let listMarker = listMarker else {
            return nil;
        }
        
        let c = message.character(at: startAt);
        switch listMarker {
        case .asterisk:
            return c == ASTERISK ? listParagraphStyle : listParagraphContinuationStyle;
        case .minus:
            return c == MINUS ? listParagraphStyle : listParagraphContinuationStyle;
        case .number:
            return isNumber(c) ? listParagraphStyle : listParagraphContinuationStyle;
        default:
            return nil;
        }
    }
    
    static func isContinuation(char c: unichar, listMarker: ListMarker) -> Bool {
        switch listMarker {
        case .asterisk:
            return c != ASTERISK;
        case .minus:
            return c != MINUS;
        case .number:
            return !isNumber(c);
        default:
            return true;
        }
    }
 
}

extension String {
    
    static let emojisList = [
        "😳": ["O.o"],
        "☺️": [":-$", ":$"],
        "😄": [":-D", ":D", ":-d", ":d", ":->", ":>"],
        "😉": [";-)", ";)"],
        "😊": [":-)", ":)"],
        "😡": [":-@", ":@"],
        "😕": [":-S", ":S", ":-s", ":s", ":-/", ":/"],
        "😭": [";-(", ";("],
        "😮": [":-O", ":O", ":-o", ":o"],
        "😎": ["B-)", "B)"],
        "😐": [":-|", ":|"],
        "😛": [":-P", ":P", ":-p", ":p"],
        "😟": [":-(", ":("]
    ];
    
    static var emojis: [String:String] = Dictionary(uniqueKeysWithValues: String.emojisList.flatMap({ (arg0) -> [(String,String)] in
        let (k, list) = arg0
        return list.map { v in return (v, k)};
    }));
    
    func emojify() -> String {
        var result = self;
        let words = components(separatedBy: " ").filter({ s in !s.isEmpty});
        for word in words {
            if let emoji = String.emojis[word] {
                result = result.replacingOccurrences(of: word, with: emoji);
            }
        }
        return result;
    }
}
