//
// VideoCaptureDevice.swift
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

enum VideoCaptureDevice: Equatable {
    case camera(device: AVCaptureDevice, format: AVCaptureDevice.Format?)
    case display(id: CGDirectDisplayID)
    
    static var `default`: VideoCaptureDevice? {
        guard let device = AVCaptureDevice.default(for: AVMediaType.video) else {
            return nil;
        }
        return .camera(device: device, format: nil);
    }
    
    static var allDevices: [VideoCaptureDevice] {
        return RTCCameraVideoCapturer.captureDevices().map({ .camera(device: $0, format: nil) }) + NSScreen.screens.map({ .display(id: $0.displayId )});
    }
    
    var label: String {
        switch self {
        case .camera(let device, _):
            return device.localizedName;
        case .display(let id):
            return NSScreen.screens.first(where: { $0.displayId == id })?.localizedName ?? "";
        }
    }
    
    func capturer(for videoSource: RTCVideoSource) -> VideoCapturer {
        switch self {
        case .camera(let device, _):
            return CameraVideoCapture(delegate: videoSource, device: device);
        case .display(let id):
            return DesktopVideoCapturer(delegate: videoSource, displayId: id);
        }
    }
    
}
