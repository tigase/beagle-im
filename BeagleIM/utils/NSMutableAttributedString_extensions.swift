//
// NSMutableAttributedString_extensions.swift
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

extension NSMutableAttributedString {
    
    static let AT_CHAR = ("@" as NSString).character(at: 0);
    
    func markMention(of nickname: String, withColor color: NSColor, bold: Bool) {
        let str = self.string as NSString;
        let ranges = str.ranges(of: nickname, options: []);
        ranges.forEach { (subrange) in
            if subrange.location > 0 && str.character(at: subrange.location - 1) == NSMutableAttributedString.AT_CHAR {
                let nickrange = NSRange(location: subrange.location - 1, length: subrange.length + 1);
                self.addAttribute(.foregroundColor, value: color, range: nickrange);
                if bold {
                    self.applyFontTraits(.boldFontMask, range: nickrange)
                }
            } else {
                self.addAttribute(.foregroundColor, value: color, range: subrange);
                if bold {
                    self.applyFontTraits(.boldFontMask, range: subrange)
                }
            }
        }
    }
    
    func mark(keyword: String, withColor color: NSColor, bold: Bool) {
        let str = self.string as NSString;
        let ranges = str.ranges(of: keyword, options: .caseInsensitive);
        ranges.forEach { (subrange) in
            self.addAttribute(.foregroundColor, value: color, range: subrange);
            if bold {
                self.applyFontTraits(.boldFontMask, range: subrange)
            }
        }
    }
    
    func mark(keywords: [String], withColor color: NSColor, bold: Bool) {
        let str = self.string as NSString;
        for keyword in keywords {
            let ranges = str.ranges(of: keyword, options: .caseInsensitive);
            ranges.forEach { (subrange) in
                self.addAttribute(.foregroundColor, value: color, range: subrange);
                if bold {
                    self.applyFontTraits(.boldFontMask, range: subrange)
                }
            }
        }
    }
}
