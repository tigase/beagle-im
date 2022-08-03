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

class HttpFileUploadModule: Martin.HttpFileUploadModule, Resetable {
    
    @Published
    var availableComponents: [UploadComponent] = [];
    
    var isAvaiable: Bool {
        return !availableComponents.isEmpty;
    }
    
    var isAvailablePublisher: AnyPublisher<Bool,Never> {
        return $availableComponents.map({ !$0.isEmpty }).eraseToAnyPublisher();
    }
 
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
                self?.findHttpUploadComponent(completionHandler: { result in
                    switch result {
                    case .success(let values):
                        self?.availableComponents = values;
                    case .failure(let error):
                        break;
                    }
                });
            });
        }
    }
    
    func reset(scopes: Set<ResetableScope>) {
        if scopes.contains(.session) {
            availableComponents = [];
        }
    }
    
}
