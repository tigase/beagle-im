//
// HTTPFileUploadHelper.swift
//
// BeagleIM
// Copyright (C) 2020 "Tigase, Inc." <office@tigase.com>
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
import Martin
import os

class HTTPFileUploadHelper {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HTTPFileUploadHelper")

    static func upload(withClient client: Context, filename: String, fileUrl: URL, mimeType: String?, delegate: URLSessionDelegate?) async throws -> URL {
        guard let size = try fileUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            throw ShareError.noFileSizeError;
        }
        
        let httpUploadModule = client.module(.httpFileUpload);
        let results = try await httpUploadModule.findHttpUploadComponents();
        guard !results.isEmpty else {
            throw ShareError.notSupported;
        }
        guard let compJid = results.first(where: { $0.maxSize > size })?.jid else {
            throw ShareError.fileTooBig;
        }
        
        let slot = try await httpUploadModule.requestUploadSlot(componentJid: compJid, filename: filename, size: size, contentType: mimeType);
        
        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: delegate, delegateQueue: OperationQueue.main);
        var request = URLRequest(url: slot.putUri);
        slot.putHeaders.forEach({ (k,v) in
            request.addValue(v, forHTTPHeaderField: k);
        });
        request.httpMethod = "PUT";
        request.addValue(String(size), forHTTPHeaderField: "Content-Length");
        if let mimeType = mimeType {
            request.addValue(mimeType, forHTTPHeaderField: "Content-Type");
        }
        
        let (_, response) = try await session.upload(for: request, fromFile: fileUrl)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 500;
        guard (code == 200 || code == 201) else {
            self.logger.error("upload of file \(filename) failed, response: \(response)");
            throw ShareError.httpError;
        }
        if code == 200 {
            throw ShareError.invalidResponseCode(url: slot.getUri);
        } else {
            return slot.getUri;
        }
    }
}
