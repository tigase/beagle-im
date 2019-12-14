//
//  DownloadManager.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 13/12/2019.
//  Copyright © 2019 HI-LOW. All rights reserved.
//

import Foundation

class DownloadManager {
    
    static let instance = DownloadManager();
    
    func downloadFile(destination: DownloadStore, url: URL, maxSize: Int64, excludedMimetypes: [String], completionHandler: @escaping (Result<String,DownloadError>)->Void) {
        
        self.downloadFile(url: url, maxSize: maxSize, excludedMimetypes: excludedMimetypes) { (result) in
            switch result {
            case .success(let localUrl):
                let id = UUID().uuidString;
                DownloadStore.instance.store(localUrl, with: id);
                completionHandler(.success(id));
            case .failure(let err):
                completionHandler(.failure(err));
            }
        }
    }
    
    func downloadFile(url: URL, maxSize: Int64, excludedMimetypes: [String], completionHandler: @escaping (Result<URL,DownloadError>)->Void) {
        let sessionConfig = URLSessionConfiguration.default;
        let session = URLSession(configuration: sessionConfig);
        
        DownloadManager.retrieveHeaders(session: session, url: url, completionHandler: { headersResult in
            switch headersResult {
            case .success(let suggestedFilename, let expectedSize, let mimeType):
                if let type = mimeType {
                    guard !excludedMimetypes.contains(type) else {
                        completionHandler(.failure(.badMimeType(mimeType: type)));
                        return;
                    }
                }
                
                DownloadManager.download(session: session, url: url, completionHandler: completionHandler);
                break;
            case .failure(let statusCode):
                completionHandler(.failure(.responseError(statusCode: statusCode)));
            }
        })
    }
    
    static func download(session: URLSession, url: URL, completionHandler: @escaping (Result<URL, DownloadError>)->Void) {
        let request = URLRequest(url: url);
        let task = session.downloadTask(with: request) { (tempLocalUrl, response, error) in
            if let tempLocalUrl = tempLocalUrl, error == nil {
                completionHandler(.success(tempLocalUrl));
            } else {
                guard error == nil else {
                    completionHandler(.failure(.networkError(error: error!)));
                    return;
                }
                
                completionHandler(.failure(.responseError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500)));
            }
        }
        task.resume();
    }
    
    static func retrieveHeaders(session: URLSession, url: URL, completionHandler: @escaping (HeadersResult)->Void) {
        var request = URLRequest(url: url);
        request.httpMethod = "HEAD";
        session.dataTask(with: request) { (data, resp, error) in
            guard let response = resp as? HTTPURLResponse else {
                completionHandler(.failure(statusCode: 500));
                return;
            }
            
            switch response.statusCode {
            case 200:
                completionHandler(.success(suggestedFilename: response.suggestedFilename, expectedSize: response.expectedContentLength, mimeType: response.mimeType))
            default:
                completionHandler(.failure(statusCode: response.statusCode));
            }
        }.resume();
    }
    
    enum HeadersResult {
        case success(suggestedFilename: String?, expectedSize: Int64, mimeType: String?)
        case failure(statusCode: Int)
    }
        
    enum DownloadError: Error {
        case networkError(error: Error)
        case responseError(statusCode: Int)
        case tooBig(size: Int64)
        case badMimeType(mimeType: String?)
    }
}
