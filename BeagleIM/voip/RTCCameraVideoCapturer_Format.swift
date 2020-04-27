//
// RTCCameraVideoCapturer_Format.swift
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
import WebRTC

extension RTCCameraVideoCapturer {
    
    static func format(for device: AVCaptureDevice, preferredWidth: Int32 = Int32.max, preferredHeight: Int32 = Int32.max, preferredOutputPixelFormat: FourCharCode) -> AVCaptureDevice.Format? {
        var formats = RTCCameraVideoCapturer.supportedFormats(for: device);
        // trimm to fit in 720x480
//        formats = formats.filter({ format -> Bool in
//            let size = CMVideoFormatDescriptionGetDimensions(format.formatDescription);
//            return !(max(size.width, size.height) > 720 || min(size.width, size.height) > 480);
//        });
        formats = formats.sorted(by: { f1, f2 -> Bool in
            let size1 = CMVideoFormatDescriptionGetDimensions(f1.formatDescription);
            let size2 = CMVideoFormatDescriptionGetDimensions(f2.formatDescription);
            let diff1 = Int(abs(preferredWidth - size1.width)) + Int(abs(preferredHeight - size1.height));
            let diff2 = Int(abs(preferredWidth - size2.width)) + Int(abs(preferredHeight - size2.height));
            if diff1 == diff2 {
                if CMFormatDescriptionGetMediaSubType(f1.formatDescription) == preferredOutputPixelFormat {
                    return true;
                }
                return false;
            }
            return diff1 < diff2;
        });
        return formats.first;
    }
    
    static func fps(for format: AVCaptureDevice.Format) -> Int {
        let limit = 30.0;
        var fps = 0.0;
        
        for range in format.videoSupportedFrameRateRanges {
            fps = max(fps, range.maxFrameRate);
        }

        return Int(min(fps, limit));
    }
        
}
//
//  RTCCameraVideoCapturer_Format.swift
//  BeagleIM
//
//  Created by Andrzej Wójcik on 25/04/2020.
//  Copyright © 2020 HI-LOW. All rights reserved.
//

import Foundation
