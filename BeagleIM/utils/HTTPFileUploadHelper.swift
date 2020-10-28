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
import TigaseSwift

class HTTPFileUploadHelper {
    
    static func upload(forAccount account: BareJID, filename: String, inputStream: InputStream, filesize size: Int, mimeType: String?, delegate: URLSessionDelegate?, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        if let client = XmppService.instance.getClient(for: account) {
            let httpUploadModule: HttpFileUploadModule = client.modulesManager.getModule(HttpFileUploadModule.ID)!;
            httpUploadModule.findHttpUploadComponent(onSuccess: { (results) in
                var compJid: JID? = nil;
                results.forEach({ (k,v) in
                    if compJid != nil {
                        return;
                    }
                    if v != nil && v! < size {
                        return;
                    }
                    compJid = k;
                });

                guard compJid != nil else {
                    guard results.count > 0 else {
                        completionHandler(.failure(.notSupported));
                        return;
                    }
                    completionHandler(.failure(.fileTooBig));
                    return;
                }
            
                httpUploadModule.requestUploadSlot(componentJid: compJid!, filename: filename, size: size, contentType: mimeType, onSuccess: { (slot) in
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
                            print("error:", error as Any, "response:", response as Any)
                            completionHandler(.failure(.httpError));
                            return;
                        }
                        if code == 200 {
                            completionHandler(.failure(.invalidResponseCode(url: slot.getUri)));
                        } else {
                            completionHandler(.success(slot.getUri));
                        }
                    }.resume();
                }, onError: { (error, message) in
                    completionHandler(.failure(.unknownError));
                })
            }, onError: { (error) in
                if error != nil && error! == ErrorCondition.item_not_found {
                    completionHandler(.failure(.notSupported));
                } else {
                    completionHandler(.failure(.unknownError));
                }
            })
        }
    }
    
    enum UploadResult {
        case success(url: URL, filesize: Int, mimeType: String?)
        case failure(ShareError)
    }
}
