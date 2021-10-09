//
// CameraVideoCapture.swift
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
import WebRTC

struct CameraVideoCapture: VideoCapturer {
    
    private let capturer: RTCCameraVideoCapturer;
    private let device: AVCaptureDevice;
    
    var currentDevice: VideoCaptureDevice {
        return .camera(device: device, format: nil);
    }
    
    init(delegate: RTCVideoSource, device: AVCaptureDevice) {
        self.capturer = RTCCameraVideoCapturer(delegate: delegate);
        self.device = device;
    }
    
    func startCapture(completionHandler: @escaping (Result<Void, Error>) -> Void) {
        guard let format = RTCCameraVideoCapturer.format(for: device, preferredOutputPixelFormat: capturer.preferredOutputPixelFormat()) else {
            completionHandler(.failure(CameraVideoCapturerError.noSupportedFormatAvailable(device)))
            return;
        }
        capturer.startCapture(with: device, format: format, fps: RTCCameraVideoCapturer.fps(for:  format), completionHandler: { error in
            completionHandler(.success(Void()));
        })
    }
    
    func stopCapture(completionHandler: @escaping () -> Void) {
        capturer.stopCapture(completionHandler: completionHandler);
    }
    
    enum CameraVideoCapturerError: Error {
        case noSupportedFormatAvailable(AVCaptureDevice)
    }
    
}
