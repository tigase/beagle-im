//
// DownloadStore.swift
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
import AppKit
import TigaseSwift

class DownloadStore {
    
    static let instance = DownloadStore();

    fileprivate let queue = DispatchQueue(label: "download_store_queue");

    let diskCacheUrl: URL;
    
    let cache = NSCache<NSString, NSImage>();
    var size: Int {
        return (try? FileManager.default.contentsOfDirectory(at: diskCacheUrl, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: .init(rawValue: 0)).map { url -> Int in
            return (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0) ?? 0;
            }.reduce(0, +)) ?? 0;
    }
    
    init() {
        diskCacheUrl = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent(Bundle.main.bundleIdentifier!, isDirectory: true).appendingPathComponent("download", isDirectory: true);
        if !FileManager.default.fileExists(atPath: diskCacheUrl.path) {
            try! FileManager.default.createDirectory(at: diskCacheUrl, withIntermediateDirectories: true, attributes: nil);
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(messageRemoved(_:)), name: DBChatHistoryStore.MESSAGE_REMOVED, object: nil);
    }
    
    @objc func messageRemoved(_ notification: Notification) {
        guard let item = notification.object as? ConversationEntryDeleted else {
            return;
        }
        self.deleteFile(for: "\(item.id)")
    }
    
    func store(_ source: URL, filename: String, with id: String) -> URL {
        let fileDir = diskCacheUrl.appendingPathComponent(id, isDirectory: true);
        if !FileManager.default.fileExists(atPath: fileDir.path) {
            try! FileManager.default.createDirectory(at: fileDir, withIntermediateDirectories: true, attributes: nil);
        }
        
        try? FileManager.default.copyItem(at: source, to: fileDir.appendingPathComponent(filename));
        if !FileManager.default.fileExists(atPath: fileDir.appendingPathComponent(id).path) {
            try! FileManager.default.createSymbolicLink(at: fileDir.appendingPathComponent(id), withDestinationURL: fileDir.appendingPathComponent(filename));
        }
        
        return fileDir.appendingPathComponent(filename);
    }
    
    func url(for id: String) -> URL? {
        let linkUrl = diskCacheUrl.appendingPathComponent(id, isDirectory: true).appendingPathComponent(id);
        
        guard let filePath = try? FileManager.default.destinationOfSymbolicLink(atPath: linkUrl.path) else {
            return nil;
        }
        
        return URL(fileURLWithPath: filePath);
    }
            
    func deleteFile(for id: String) {
        let fileDir = diskCacheUrl.appendingPathComponent(id, isDirectory: true);
        guard FileManager.default.fileExists(atPath: fileDir.path) else {
            return;
        }
        
        try? FileManager.default.removeItem(at: fileDir);
    }
    
//    func addImage(url: URL, maxWidthOrHeight: CGFloat, previewFor: URL) throws -> String {
//        let previewId = hash(for: previewFor);
//        guard !hasFile(for: previewId) else {
//            return previewId;
//        }
//
//        do {
//            return try addImage(url: url, maxWidthOrHeight: maxWidthOrHeight, withId: previewId);
//        } catch let err {
//            guard !hasFile(for: previewId) else {
//                return previewId;
//            }
//            throw err;
//        }
//    }
//
//    func addImage(url: URL, maxWidthOrHeight: CGFloat, withId: String? = nil) throws -> String {
//        guard let image = NSImage(contentsOf: url) else {
//            throw NSError(domain: "It is not an image file!", code: 500, userInfo: nil);
//        }
//
//        let previewId = withId ?? UUID().uuidString;
//        guard let scaled = image.scaled(maxWidthOrHeight: maxWidthOrHeight, format: .jpeg2000, properties: [.compressionFactor: 0.8]) else {
//            throw NSError(domain: "Scaling failed", code: 500, userInfo: nil);
//        }
//
//        try scaled.write(to: diskCacheUrl.appendingPathComponent(previewId));
//        return previewId;
//    }
//
//    func addToDownloadCache(url: URL) throws -> String {
//        let previewId = UUID().uuidString;
//        let destination = diskCacheUrl.appendingPathComponent(previewId).absoluteURL;
//
//        try FileManager.default.copyItem(at: url, to: destination);
//
//        return previewId;
//    }
//
//    func getImage(for id: String, load: Bool = false) -> NSImage? {
//        guard let image = self.cache.object(forKey: id as NSString) else {
//            guard load else {
//                return nil;
//            }
//            guard let url = getURL(for: id) else {
//                return nil;
//            }
//
//            guard let image = NSImage(contentsOf: url) else {
//                return nil;
//            }
//            self.cache.setObject(image, forKey: id as NSString);
//            return image;
//        }
//        return image;
//    }
//
//    func getImages(for ids: [(URL, String)], completion: @escaping ([(URL,NSImage)],Bool)->Void) {
//        var results: [(URL,NSImage)] = [];
//        for i in 0..<ids.count {
//            guard let image = getImage(for: ids[i].1, load: false) else {
//                queue.asyncAfter(deadline: DispatchTime.now() + 0.05) {
//                    for j in i..<ids.count {
//                        if let image = self.getImage(for: ids[j].1, load: true) {
//                            results.append((ids[j].0, image));
//                        }
//                    }
//                    completion(results, false);
//                }
//                return;
//            }
//            results.append((ids[i].0, image));
//        }
//        completion(results, true);
//    }
//
//    func getURL(for id: String) -> URL? {
//        let url = diskCacheUrl.appendingPathComponent(id);
//        return FileManager.default.fileExists(atPath: url.path) ? url : nil;
//    }
//
//    func getURL(for id: String?) -> URL? {
//        guard id != nil else {
//            return nil;
//        }
//        return getURL(for: id!);
//    }
//
//    func remote(for id: String) throws -> Bool {
//        guard let url = getURL(for: id) else {
//            return false;
//        }
//        try FileManager.default.removeItem(at: url);
//        return true;
//    }
//
//    func clear() {
//        try? FileManager.default.contentsOfDirectory(atPath: diskCacheUrl.path).forEach { (item) in
//            try? FileManager.default.removeItem(at: getURL(for: item)!);
//        }
//    }
//
//    func hasFile(for url: URL) -> String? {
//        let id = hash(for: url);
//        guard hasFile(for: id) else {
//            return nil;
//        }
//        return id;
//    }
//
//    fileprivate func hasFile(for id: String) -> Bool {
//        return FileManager.default.fileExists(atPath: diskCacheUrl.appendingPathComponent(id).path);
//    }
//
//    fileprivate func hash(for url: URL) -> String {
//        return Digest.sha256.digest(toHex: url.absoluteString.data(using: .utf8))!;
//    }

}
