//
// DesktopVideoCapturer.swift
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

struct DesktopVideoCapturer: VideoCapturer {

    private let capturer: RTCDesktopVideoCapturer;
    private let displayId: CGDirectDisplayID;
    
    var currentDevice: VideoCaptureDevice {
        return .display(id: displayId);
    }
    
    init(delegate: RTCVideoSource, displayId: CGDirectDisplayID) {
        self.capturer = RTCDesktopVideoCapturer(delegate: delegate);
        self.displayId = displayId;
    }
    
    func startCapture(completionHandler: @escaping (Result<Void, Error>) -> Void) {
        self.capturer.startCapture(with: displayId, completionHander: {
            completionHandler(.success(Void()));
        })
    }
    
    func stopCapture(completionHandler: @escaping () -> Void) {
        self.capturer.stopCapture(completionHander: completionHandler);
    }

}
