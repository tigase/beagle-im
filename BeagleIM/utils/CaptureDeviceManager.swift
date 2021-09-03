//
// CaptureDeviceManager.swift
//
// BeagleIM
// Copyright (C) 2021 "Tigase, Inc." <office@tigase.com>
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
import Combine
import AVFoundation

class CaptureDeviceManager {
    
    private static var authorizations: [AVMediaType: CurrentValueSubject<AVAuthorizationStatus,Never>] = [:];
    
    private static let queue = DispatchQueue(label: "CaptureDeviceManager");
    
    static func authorizationStatus(for mediaType: AVMediaType) -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: mediaType);
    }
    
    static func authorizationStatusPublisher(for mediaType: AVMediaType) -> CurrentValueSubject<AVAuthorizationStatus,Never> {
        return queue.sync {
            guard let subject = authorizations[mediaType] else {
                let subject = CurrentValueSubject<AVAuthorizationStatus,Never>(AVCaptureDevice.authorizationStatus(for: mediaType));
                authorizations[mediaType] = subject;
                return subject;
            }
            return subject;
        }
    }
    
    static func requestAccess(for mediaType: AVMediaType, completionHandler: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: mediaType, completionHandler: { result in
            queue.sync {
                authorizations[mediaType]?.send(result ? .authorized : .denied)
            }
            completionHandler(result);
        })
    }
        
}
