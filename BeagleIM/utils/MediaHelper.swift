//
// MediaHelper.swift
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

import AVKit

enum ShareError: Error {
    case unknownError
    case noAccessError
    case noFileSizeError
    case noMimeTypeError
    
    case notSupported
    case fileTooBig
    
    case httpError
    case invalidResponseCode(url: URL)
    
    var message: String {
        switch self {
        case .invalidResponseCode:
            return "Server did not confirm file upload correctly."
        case .unknownError:
            return "Please try again later."
        case .noAccessError:
            return "It was not possible to access the file."
        case .noFileSizeError:
            return "Could not retrieve file size.";
        case .noMimeTypeError:
            return "Could not detect MIME type of a file.";
        case .notSupported:
            return "Feature not supported by XMPP server";
        case .fileTooBig:
            return "File is too big to share";
        case .httpError:
            return "Upload to HTTP server failed.";
        }
    }
}

class MediaHelper {
    
    static func askImageQuality(window: NSWindow, forceQualityQuestion askQuality: Bool, _ completionHandler: @escaping (Result<ImageQuality,ShareError>)->Void) {
        if let quality = askQuality ? nil : ImageQuality.current {
            completionHandler(.success(quality));
        } else {
            DispatchQueue.main.async {
                let alert = NSAlert();
                alert.icon = NSImage(named: NSImage.infoName);
                alert.messageText = "Select quality";
                alert.informativeText = "Select quality of the image for sharing";
                let values: [ImageQuality] = [.original, .highest, .high, .medium, .low];
                for value in  values {
                    alert.addButton(withTitle: value.rawValue.capitalized);
                }
                alert.beginSheetModal(for: window, completionHandler: { response in
                    let idx = response.rawValue - 1000;
                    guard idx < values.count else {
                        completionHandler(.failure(.noAccessError));
                        return;
                    }
                    completionHandler(.success(values[idx]));
                });
            }
        }
    }
    
    static func askVideoQuality(window: NSWindow, forceQualityQuestion askQuality: Bool, _ completionHandler: @escaping (Result<VideoQuality,ShareError>)->Void) {
        if let quality = askQuality ? nil : VideoQuality.current {
            completionHandler(.success(quality));
        } else {
            DispatchQueue.main.async {
                let alert = NSAlert();
                alert.icon = NSImage(named: NSImage.infoName);
                alert.messageText = "Select quality";
                alert.informativeText = "Select quality of the video for sharing";

                let values: [VideoQuality] = [.original, .high, .medium, .low];
                for value in  values {
                    alert.addButton(withTitle: value.rawValue.capitalized);
                }
                alert.beginSheetModal(for: window, completionHandler: { response in
                    let idx = response.rawValue - 1000;
                    guard idx < values.count else {
                        completionHandler(.failure(.noAccessError));
                        return;
                    }
                    completionHandler(.success(values[idx]));
                });
            }
        }
    }
    
    static func compressImage(url: URL, filename: String, quality: ImageQuality, deleteSource: Bool, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard quality != .original else {
            completionHandler(.success(url));
            return;
        }
        guard let inData = try? Data(contentsOf: url), let image = NSImage(data: inData) else {
            if deleteSource {
                try? FileManager.default.removeItem(at: url);
            }
            completionHandler(.failure(.notSupported));
            return;
        }
        if deleteSource {
            try? FileManager.default.removeItem(at: url);
        }
        
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename + ".jpg", isDirectory: false);
        guard let outData = image.scaled(maxWidthOrHeight: quality.size).jpegData(compressionQuality: quality.quality) else {
            return;
        }
        do {
            try outData.write(to: fileUrl);
            completionHandler(.success(fileUrl));
        } catch {
            completionHandler(.failure(.noAccessError));
            return;
        }
    }
    
    static func compressMovie(url: URL, filename: String, quality: VideoQuality, deleteSource: Bool, progressCallback: @escaping (Float)->Void, completionHandler: @escaping (Result<URL,ShareError>)->Void) {
        guard quality != .original else {
            completionHandler(.success(url));
            return;
        }
        let video = AVAsset(url: url);
        print("asset:", video, video.isExportable, video.isPlayable)
        let exportSession = AVAssetExportSession(asset: video, presetName: quality.preset)!;
        print("export profiles:", AVAssetExportSession.exportPresets(compatibleWith: video));
        exportSession.shouldOptimizeForNetworkUse = true;
        exportSession.outputFileType = .mp4;
        let fileUrl = FileManager.default.temporaryDirectory.appendingPathComponent(filename + ".mp4", isDirectory: false);
        exportSession.outputURL = fileUrl;
        print("exporting movie from:", url, "to:", fileUrl, FileManager.default.fileExists(atPath: url.path), FileManager.default.fileExists(atPath: fileUrl.path));
        
        let timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { _ in
            progressCallback(exportSession.progress);
        })
        exportSession.exportAsynchronously {
            timer.invalidate();
            print("export status:", exportSession.status, exportSession.error)
            if deleteSource {
                try? FileManager.default.removeItem(at: url);
            }
            completionHandler(.success(fileUrl));
        }
    }
    
}
