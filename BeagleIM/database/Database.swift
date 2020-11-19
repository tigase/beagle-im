//
// Database.swift
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

import Foundation
import TigaseSQLite3
import TigaseSwift
import OSLog

class Database {
    
    static let main: DatabasePool = {
        return try! DatabasePool(dbFilename: "beagleim.sqlite", schemaMigrator: DatabaseMigrator());
    }();
    
}

extension DatabasePool {
    convenience init(dbFilename: String, schemaMigrator: DatabaseSchemaMigrator? = nil) throws {
        let paths = NSSearchPathForDirectoriesInDomains(.applicationSupportDirectory, .userDomainMask, true);
        let documentDirectory = paths[0].appending("/" + (Bundle.main.infoDictionary!["CFBundleName"] as! String));
        let path = documentDirectory.appending("/" + dbFilename);
        if !FileManager.default.fileExists(atPath: documentDirectory) {
            try! FileManager.default.createDirectory(at: URL(fileURLWithPath: documentDirectory), withIntermediateDirectories: true, attributes: nil);
            // we previously stored file in document directory so we need to move it if it exists..
            let oldPath = NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0];
            if FileManager.default.fileExists(atPath: oldPath.appending("/" + dbFilename)) {
                try? FileManager.default.moveItem(atPath: oldPath.appending("/" + dbFilename), toPath: path);
            }
        }

        try self.init(configuration: Configuration(path: path, schemaMigrator: schemaMigrator));
        os_log(OSLogType.error, log: .sqlite, "Initialized database: %s", path);
    }
}

extension JID: DatabaseConvertibleStringValue {
    
    public func encode() -> String {
        return self.stringValue;
    }
    
}

extension BareJID: DatabaseConvertibleStringValue {
    
    public func encode() -> String {
        return self.stringValue;
    }
    
}

extension Element: DatabaseConvertibleStringValue {
    public func encode() -> String {
        return self.stringValue;
    }
}

extension Cursor {
    
    func jid(for column: String) -> JID? {
        return JID(string(for: column));
    }
    
    func jid(at column: Int) -> JID? {
        return JID(string(at: column));
    }
    
    subscript(index: Int) -> JID? {
        return JID(string(at: index));
    }
    
    subscript(column: String) -> JID? {
        return JID(string(for: column));
    }
}

extension Cursor {
    
    func bareJid(for column: String) -> BareJID? {
        return BareJID(string(for: column));
    }
    
    func bareJid(at column: Int) -> BareJID? {
        return BareJID(string(at: column));
    }
    
    subscript(index: Int) -> BareJID? {
        return BareJID(string(at: index));
    }
    
    subscript(column: String) -> BareJID? {
        return BareJID(string(for: column));
    }
}


