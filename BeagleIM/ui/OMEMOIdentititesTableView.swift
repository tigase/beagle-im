//
// OMEMOIdentititesTableView.swift
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
import MartinOMEMO

open class OMEMOIdentitiesTableView: NSTableView, NSTableViewDataSource {
    
    open var identities: [Identity] = [] {
        didSet {
            self.reloadData();
        }
    }
    
    override open var dataSource: NSTableViewDataSource? {
        get {
            return self;
        }
        set {}
    }
    
    var selectedIdentities: [Identity] {
        return self.selectedRowIndexes.map { (row) -> Identity in
            return self.identities[row];
        }
    }
    
    public func numberOfRows(in tableView: NSTableView) -> Int {
        return identities.count;
    }
    
    func prettify(fingerprint tmp: String) -> String {
        var fingerprint = tmp;
        var idx = fingerprint.startIndex;
        for _ in 0..<(fingerprint.count / 8) {
            idx = fingerprint.index(idx, offsetBy: 8);
            fingerprint.insert(" ", at: idx);
            idx = fingerprint.index(after: idx);
        }
        return fingerprint;
    }

}
