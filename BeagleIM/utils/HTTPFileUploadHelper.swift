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
import TigaseLogging

class HTTPFileUploadHelper {
    
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "HTTPFileUploadHelper")
    
    static func upload(withClient client: Context, filename: String, inputStream: InputStream, filesize size: Int, mimeType: String?, delegate: URLSessionDelegate?, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        let httpUploadModule = client.module(.httpFileUpload);
        httpUploadModule.findHttpUploadComponent(completionHandler: { result in
            switch result {
            case .success(let results):
                guard !results.isEmpty else {
                    completionHandler(.failure(.notSupported));
                    return;
                }
                guard let compJid: JID = results.first(where: { $0.maxSize > size })?.jid else {
                    completionHandler(.failure(.fileTooBig))
                    return;
                }
            
                httpUploadModule.requestUploadSlot(componentJid: compJid, filename: filename, size: size, contentType: mimeType, completionHandler: { result in
                    switch result {
                    case .success(let slot):
                        var request = URLRequest(url: slot.putUri);
                        slot.putHeaders.forEach({ (k,v) in
                            request.addValue(v, forHTTPHeaderField: k);
                        });
                        request.httpMethod = "PUT";
                        request.httpBodyStream = inputStream;
                        request.addValue(String(size), forHTTPHeaderField: "Content-Length");
                        if let mimeType = mimeType {
                            request.addValue(mimeType, forHTTPHeaderField: "Content-Type");
                        }
                        let session = URLSession(configuration: URLSessionConfiguration.default, delegate: delegate, delegateQueue: OperationQueue.main);
                        session.dataTask(with: request) { (data, response, error) in
                            let code = (response as? HTTPURLResponse)?.statusCode ?? 500;
                            guard error == nil && (code == 200 || code == 201) else {
                                self.logger.error("upload of file \(filename) failed, error: \(error as Any), response: \(response as Any)");
                                completionHandler(.failure(.httpError));
                                return;
                            }
                            if code == 200 {
                                completionHandler(.failure(.invalidResponseCode(url: slot.getUri)));
                            } else {
                                completionHandler(.success(slot.getUri));
                            }
                        }.resume();
                    case .failure(_):
                        completionHandler(.failure(.unknownError));
                    }
                });
            case .failure(let error):
                if error == .item_not_found {
                    completionHandler(.failure(.notSupported));
                } else {
                    completionHandler(.failure(.unknownError));
                }
            }
        });
    }
    
    enum UploadResult {
        case success(url: URL, filesize: Int, mimeType: String?)
        case failure(ShareError)
    }
}
