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
import SQLite3
import TigaseSwift

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

open class DBConnection {
    
    fileprivate var handle_:OpaquePointer? = nil;
    open var handle:OpaquePointer {
        get {
            return handle_!;
        }
    }
    
    public let dispatcher: QueueDispatcher;
    
    open var lastInsertRowId: Int? {
        let rowid = sqlite3_last_insert_rowid(handle);
        return rowid > 0 ? Int(rowid) : nil;
    }
    
    open var changesCount: Int {
        return Int(sqlite3_changes(handle));
    }
    
    init(dbFilename:String) throws {
        dispatcher = QueueDispatcher(queue: DispatchQueue(label: "db_queue"), queueTag: DispatchSpecificKey<DispatchQueue?>());
        
        try dispatcher.sync {
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
            
            let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE;
            
            _ = try self.check(sqlite3_open_v2(path, &self.handle_, flags | SQLITE_OPEN_FULLMUTEX, nil));
        }
    }
    
    deinit {
        sqlite3_close(handle);
    }
    
    open func execute(_ query: String) throws {
        try dispatcher.sync {
            _ = try self.check(sqlite3_exec(self.handle, query, nil, nil, nil));
        }
    }
    
    open func prepareStatement(_ query: String) throws -> DBStatement {
        return try dispatcher.sync {
            return try DBStatement(connection: self, query: query);
        }
    }
    
    
    fileprivate func check(_ result:Int32, statement:DBStatement? = nil) throws -> Int32 {
        guard let error = DBResult(errorCode: result, connection: self, statement: statement) else {
            return result;
        }
        
        throw error;
    }
    
}

public enum DBResult: Error {
    
    fileprivate static let successCodes = [ SQLITE_OK, SQLITE_ROW, SQLITE_DONE ];
    
    case error(message:String, code: Int32, statement:DBStatement?)
    
    init?(errorCode: Int32, connection: DBConnection, statement:DBStatement?) {
        guard !DBResult.successCodes.contains(errorCode) else {
            return nil;
        }
        
        let tmp = sqlite3_errmsg(connection.handle);
        let message = String(cString: tmp!);
        self = .error(message: message, code: errorCode, statement: statement);
    }
    
}

open class DBStatement {
    
    fileprivate var handle:OpaquePointer? = nil;
    fileprivate let connection:DBConnection;
    
    open lazy var columnCount:Int = Int(sqlite3_column_count(self.handle));
    
    open lazy var columnNames:[String] = (0..<Int32(self.columnCount)).map { (idx:Int32) -> String in
        return String(cString: sqlite3_column_name(self.handle, idx)!);
    }
    
    open lazy var cursor:DBCursor = DBCursor(statement: self);
    
    public let dispatcher: QueueDispatcher;
    
    open var lastInsertRowId: Int? {
        return connection.lastInsertRowId;
    }
    
    open var changesCount: Int {
        return connection.changesCount;
    }
    
    init(connection:DBConnection, query:String, dispatcher: QueueDispatcher = QueueDispatcher(queue: DispatchQueue(label: "DBStatementDispatcher"), queueTag: DispatchSpecificKey<DispatchQueue?>())) throws {
        self.connection = connection;
        self.dispatcher = dispatcher;
        _ = try connection.check(sqlite3_prepare_v2(connection.handle, query, -1, &handle, nil));
    }
    
    deinit {
        sqlite3_finalize(handle);
    }
    
    fileprivate func step(_ expect: Int32 = SQLITE_ROW) throws -> Bool  {
        return try connection.dispatcher.sync() {
            let result = try self.connection.check(sqlite3_step(self.handle));
            return result == expect;
        }
    }
    
    fileprivate func bind(_ params:Any?...) throws -> DBStatement {
        _ = try bind(params);
        return self;
    }
    
    fileprivate func bind(_ params:[String:Any?]) throws -> DBStatement {
        reset()
        for (k,v) in params {
            let pos = sqlite3_bind_parameter_index(handle, ":"+k);
            if pos == 0 {
                print("got pos = 0, while parameter count = ", sqlite3_bind_parameter_count(handle));
            }
            try bind(v, pos: pos);
        }
        return self;
    }
    
    fileprivate func bind(_ params:[Any?]) throws -> DBStatement {
        reset()
        for pos in 1...params.count {
            _ = try bind(params[pos-1], atIndex: pos);
        }
        return self;
    }
    
    fileprivate func bind(_ value:Any?, atIndex:Int) throws -> DBStatement {
        try bind(value, pos: Int32(atIndex));
        return self;
    }
    
    fileprivate func bind(_ value_:Any?, pos:Int32) throws {
        var r:Int32 = SQLITE_OK;
        if value_ == nil {
            r = sqlite3_bind_null(handle, pos);
        } else if let value:Any = value_ {
            switch value {
            case let v as [UInt8]:
                r = sqlite3_bind_blob(handle, pos, v, Int32(v.count), SQLITE_TRANSIENT);
            case let v as Data:
                r = v.withUnsafeBytes { (bytes) -> Int32 in
                    return sqlite3_bind_blob(handle, pos, bytes.baseAddress!, Int32(v.count), SQLITE_TRANSIENT);
                }
            case let v as Double:
                r = sqlite3_bind_double(handle, pos, v);
            case let v as Int:
                r = sqlite3_bind_int64(handle, pos, Int64(v));
            case let v as Bool:
                r = sqlite3_bind_int(handle, pos, Int32(v ? 1 : 0));
            case let v as String:
                r = sqlite3_bind_text(handle, pos, v, -1, SQLITE_TRANSIENT);
            case let v as Date:
                let timestamp = Int64(v.timeIntervalSince1970 * 1000);
                r = sqlite3_bind_int64(handle, pos, timestamp);
            case let v as StringValue:
                r = sqlite3_bind_text(handle, pos, v.stringValue, -1, SQLITE_TRANSIENT);
            default:
                throw DBResult.error(message: "Unsupported type \(value.self) for parameter \(pos)", code: SQLITE_FAIL, statement: self);
            }
        } else {
            sqlite3_bind_null(handle, pos)
        }
        _ = try check(r);
    }
    
    fileprivate func execute(_ params:[String:Any?]) throws -> DBStatement? {
        _ = try bind(params);
        return try execute();
    }
    
    fileprivate func execute(_ params:Any?...) throws -> DBStatement? {
        return try execute(params);
    }
    
    fileprivate func execute(_ params:[Any?]) throws -> DBStatement? {
        if params.count > 0 {
            _ = try bind(params);
        }
        reset(false);
        return try step() ? self : nil;
    }
    
    //    open func query(_ params:[String:Any?]) throws -> DBCursor? {
    //        return try execute(params)?.cursor;
    //    }
    //
    //    open func query(_ params:Any?...) throws -> DBCursor? {
    //        return try execute(params)?.cursor;
    //    }
    
    open func findFirst<T>(_ params: [String:Any?], map: (DBCursor)-> T?) throws -> T? {
        return try dispatcher.sync {
            guard let cursor = try execute(params)?.cursor else {
                return nil;
            }
            
            return map(cursor);
        }
    }
    
    open func findFirst<T>(_ params: Any?..., map: (DBCursor)-> T?) throws -> T? {
        return try dispatcher.sync {
            guard let cursor = try execute(params)?.cursor else {
                return nil;
            }
            
            return map(cursor);
        }
    }
    
    open func query(_ params:[String:Any?], forEach: (DBCursor)->Void) throws {
        try dispatcher.sync {
            if let cursor = try execute(params)?.cursor {
                repeat {
                    forEach(cursor);
                } while cursor.next();
            }
        }
    }
    
    open func query(_ params:Any?..., forEach: (DBCursor)->Void) throws {
        try dispatcher.sync {
            if let cursor = try execute(params)?.cursor {
                repeat {
                    forEach(cursor);
                } while cursor.next();
            }
        }
    }
    
    open func queryFirstMatching<T>(_ params:[String:Any?], forEachRowUntil: (DBCursor)->T?) throws -> T? {
        return try dispatcher.sync {
            if let cursor = try execute(params)?.cursor {
                var result: T?;
                repeat {
                    result = forEachRowUntil(cursor);
                } while result == nil && cursor.next();
                return result;
            }
            return nil;
        }
    }
    
    open func queryFirstMatching<T>(_ params:Any?..., forEachRowUntil: (DBCursor)->T?) throws -> T? {
        var result: T? = nil;
        try dispatcher.sync {
            if let cursor = try execute(params)?.cursor {
                repeat {
                    result = forEachRowUntil(cursor);
                } while result == nil && cursor.next();
            }
        }
        return result;
    }
    
    open func query<T>(_ params:[String:Any?], map: (DBCursor)->T?) throws -> [T] {
        var result = [T]();
        try dispatcher.sync {
            var tmp: T? = nil;
            if let cursor = try execute(params)?.cursor {
                repeat {
                    tmp = map(cursor);
                    if tmp != nil {
                        result.append(tmp!);
                    }
                } while cursor.next();
            }
        }
        return result;
    }
    
    open func query<T>(_ params:Any?..., map: (DBCursor)->T?) throws -> [T] {
        var result = [T]();
        try dispatcher.sync {
            var tmp: T? = nil;
            if let cursor = try execute(params)?.cursor {
                repeat {
                    tmp = map(cursor);
                    if tmp != nil {
                        result.append(tmp!);
                    }
                } while cursor.next();
            }
        }
        return result;
    }
    
    open func insert(_ params:Any?...) throws -> Int? {
        return try connection.dispatcher.sync {
            if params.count > 0 {
                _ = try self.bind(params);
            }
            self.reset(false);
            if try self.step(SQLITE_DONE) {
                return self.lastInsertRowId;
            }
            return nil;
        }
    }
    
    open func insert(_ params:[String:Any?]) throws -> Int? {
        return try connection.dispatcher.sync {
            _ = try self.bind(params);
            self.reset(false);
            if try self.step(SQLITE_DONE) {
                return self.lastInsertRowId;
            }
            return nil;
        }
    }
    
    open func update(_ params:Any?...) throws -> Int {
        return try connection.dispatcher.sync {
            _ = try self.execute(params);
            return self.changesCount;
        }
    }
    
    open func update(_ params:[String:Any?]) throws -> Int {
        return try connection.dispatcher.sync {
            _ = try self.execute(params);
            return self.changesCount;
        }
    }
    
    open func scalar(_ params:Any?...) throws -> Int? {
        return try dispatcher.sync {
            let cursor = try self.execute(params)?.cursor;
            return cursor?[0];
        }
    }
    
    open func scalar(_ params:[String:Any?]) throws -> Int? {
        return try dispatcher.sync {
            let cursor = try self.execute(params)?.cursor;
            return cursor?[0];
        }
    }
    
    open func scalar(_ params:Any?..., columnName: String) throws -> Int? {
        return try dispatcher.sync {
            let cursor = try self.execute(params)?.cursor;
            return cursor?[columnName];
        }
    }
    
    open func scalar(_ params:[String:Any?], columnName: String) throws -> Int? {
        return try dispatcher.sync {
            let cursor = try self.execute(params)?.cursor;
            return cursor?[columnName];
        }
    }
    
    fileprivate func reset(_ bindings:Bool=true) {
        sqlite3_reset(handle);
        if bindings {
            sqlite3_clear_bindings(handle);
        }
    }
    
    fileprivate func check(_ result:Int32) throws -> Int32 {
        return try connection.check(result, statement: self);
    }
    
}

open class DBCursor {
    
    fileprivate let connection: DBConnection;
    fileprivate let handle:OpaquePointer;
    
    open lazy var columnCount:Int = Int(sqlite3_column_count(self.handle));
    
    open lazy var columnNames:[String] = (0..<Int32(self.columnCount)).map { (idx:Int32) -> String in
        return String(cString: sqlite3_column_name(self.handle, idx)!);
    }
    
    init(statement:DBStatement) {
        self.connection = statement.connection;
        self.handle = statement.handle!;
    }
    
    subscript(index: Int) -> Double {
        return sqlite3_column_double(handle, Int32(index));
    }
    
    subscript(index: Int) -> Int {
        return Int(sqlite3_column_int64(handle, Int32(index)));
    }
    
    subscript(index: Int) -> String? {
        let ptr = sqlite3_column_text(handle, Int32(index));
        if ptr == nil {
            return nil;
        }
        return String(cString: UnsafePointer(ptr!));
    }
    
    subscript(index: Int) -> Bool {
        return sqlite3_column_int64(handle, Int32(index)) != 0;
    }
    
    subscript(index: Int) -> [UInt8]? {
        let idx = Int32(index);
        let origPtr = sqlite3_column_blob(handle, idx);
        if origPtr == nil {
            return nil;
        }
        let count = Int(sqlite3_column_bytes(handle, idx));
        let ptr = origPtr?.assumingMemoryBound(to: UInt8.self)
        return DBCursor.convert(count, data: ptr!);
    }
    
    subscript(index: Int) -> Data? {
        let idx = Int32(index);
        let origPtr = sqlite3_column_blob(handle, idx);
        if origPtr == nil {
            return nil;
        }
        let count = Int(sqlite3_column_bytes(handle, idx));
        return Data(bytes: origPtr!, count: count);
    }
    
    subscript(index: Int) -> Date {
        let timestamp = Double(sqlite3_column_int64(handle, Int32(index))) / 1000;
        return Date(timeIntervalSince1970: timestamp);
    }
    
    subscript(index: Int) -> JID? {
        if let str:String = self[index] {
            return JID(str);
        }
        return nil;
    }
    
    subscript(index: Int) -> BareJID? {
        if let str:String = self[index] {
            return BareJID(str);
        }
        return nil;
    }
    
    subscript(column: String) -> Double? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> Int? {
        //        return forColumn(column) {
        //            let v:Int? = self[$0];
        //            print("for \(column), position \($0) got \(v)")
        //            return v;
        //        }
        if let idx = columnNames.firstIndex(of: column) {
            return self[idx];
        }
        return nil;
    }
    
    subscript(column: String) -> String? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> Bool? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> [UInt8]? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> Data? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> Date? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> JID? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    subscript(column: String) -> BareJID? {
        return forColumn(column) {
            return self[$0];
        }
    }
    
    fileprivate func forColumn<T>(_ column:String, exec:(Int)->T?) -> T? {
        if let idx = columnNames.firstIndex(of: column) {
            return exec(idx);
        }
        return nil;
    }
    
    fileprivate static func convert<T>(_ count: Int, data: UnsafePointer<T>) -> [T] {
        let buffer = UnsafeBufferPointer(start: data, count: count);
        return Array(buffer)
    }
    
    open func next() -> Bool {
        return connection.dispatcher.sync {
            return sqlite3_step(self.handle) == SQLITE_ROW;
        }
    }
    
    open func next() -> DBCursor? {
        return next() ? self : nil;
    }
}

