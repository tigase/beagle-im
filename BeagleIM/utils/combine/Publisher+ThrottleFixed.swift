//
// PublisheThrottleForRender.swift
//
// BeagleIM
// Copyright (C) 2022 "Tigase, Inc." <office@tigase.com>
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

extension Publisher where Failure == Never {
    
    func throttleFixed<S>(for interval: TimeInterval, scheduler: S, latest: Bool) -> AnyPublisher<Output,Never> where S: DispatchQueue {
        if #available(iOS 13.2, macOS 10.15, *) {
            return self.throttle(for: S.SchedulerTimeType.Stride.init(floatLiteral: interval), scheduler: scheduler, latest: latest).eraseToAnyPublisher();
        } else {
            return self.throttle(for: RunLoop.SchedulerTimeType.Stride.init(floatLiteral: interval), scheduler: RunLoop.main, latest: latest).eraseToAnyPublisher();
        }
    }
    
}
