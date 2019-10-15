//
// NSString_extensions.swift
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

import Foundation

extension NSString {
    
    func ranges(of substring: String, options: NSString.CompareOptions = []) -> [NSRange] {
        var range: NSRange? = NSRange(location: 0, length: self.length);
        
        var ranges: [NSRange] = [];
        while range != nil {
            let subrange = self.range(of: substring, options: options, range: range!);
            if subrange.location == NSNotFound {
                break;
            }
            ranges.append(subrange);
            range = range!.intersection(NSRange(location: subrange.location + subrange.length, length: range!.length));
        }
        return ranges;
    }
    
}
