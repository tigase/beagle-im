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

class RTCDesktopVideoCapturer: RTCVideoCapturer {
    
    private var timer: Timer?;
    
    func startCapture(with displayId: CGDirectDisplayID, completionHander: @escaping ()->Void) {
        DispatchQueue.main.async {
            self.timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 25, repeats: true, block: { timer in
                self.grabScreen(displayId: displayId);
            })
            completionHander();
        }
    }
    
    func stopCapture(completionHander: @escaping ()->Void) {
        DispatchQueue.main.async {
            self.timer?.invalidate();
            completionHander();
        }
    }
 
    private func grabScreen(displayId: CGDirectDisplayID) {
        guard let cgImage = CGDisplayCreateImage(displayId) else {
            return;
        }
        
        var pxbuffer: CVPixelBuffer? = nil
        let options: NSDictionary = [:]

        let dataFromImageDataProvider = CFDataCreateMutableCopy(kCFAllocatorDefault, 0, cgImage.dataProvider!.data);
        guard let x = CFDataGetMutableBytePtr(dataFromImageDataProvider) else {
            return;
        }
        
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault, cgImage.width, cgImage.height, kCVPixelFormatType_32BGRA, x, cgImage.bytesPerRow, nil, nil, options, &pxbuffer)
        
        if let pixelBuffer = pxbuffer {
            let rtcPixelBuffer = RTCCVPixelBuffer(pixelBuffer: pixelBuffer);
            
            let videoFrame = RTCVideoFrame(buffer: rtcPixelBuffer, rotation: RTCVideoRotation._0, timeStampNs:  Int64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)));
        
            self.delegate?.capturer(self, didCapture: videoFrame);
        }
    }

}

extension NSScreen {
    
    var displayId: CGDirectDisplayID {
        let number = self.deviceDescription[NSDeviceDescriptionKey(rawValue: "NSScreenNumber")] as! NSNumber;
        return CGDirectDisplayID(truncating: number);
    }
    
}
