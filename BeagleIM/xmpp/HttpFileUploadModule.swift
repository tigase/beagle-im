//
// HttpFileUploadModule.swift
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
import Martin
import Combine
import os

class HttpFileUploadModule: Martin.HttpFileUploadModule, Resetable, @unchecked Sendable {
    
    @Published
    var availableComponents: [UploadComponent] = [];
    
    var isAvaiable: Bool {
        return !availableComponents.isEmpty;
    }
    
    var isAvailablePublisher: Publishers.Map<Published<[HttpFileUploadModule.UploadComponent]>.Publisher, Bool> {
        return $availableComponents.map({ !$0.isEmpty });
    }
 
    private let logger = Logger(subsystem: "BeagleIM", category: "HttpFileUploadModule");
    private var cancellable: AnyCancellable?;
    
    override var context: Context? {
        didSet {
            cancellable?.cancel();
            cancellable = context?.$state.filter({ state in
                switch state {
                case .connected(let resumed):
                    return !resumed;
                default:
                    return false;
                }
            }).sink(receiveValue: { [weak self] _ in
                guard let self else {
                    return;
                }
                self.availableComponents = []
                Task {
                    do {
                        let stream = try await self.findHttpUploadComponentsStream();
                        for await value in stream {
                            self.logger.debug("found http upload component: \(value.jid)")
                            self.availableComponents.append(value)
                        }
                    } catch {
                        self.logger.error("retrieval of http upload components failed: \(error)")
                    }
                }
            });
        }
    }
    
    func reset(scopes: Set<ResetableScope>) {
        if scopes.contains(.session) {
            availableComponents = [];
        }
    }
    
}
