//
// DBCapabilitiesCache.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
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
import TigaseSQLite3

extension Query {
    static let capsFindFeaturesForNode = Query("SELECT feature FROM caps_features WHERE node = :node");
    static let capsFindIdentityForNode = Query("SELECT name, category, type FROM caps_identities WHERE node = :node");
    static let capsFindNodesWithFeature = Query("SELECT node FROM caps_features WHERE feature = :feature");
    static let capsInsertFeatureForNode = Query("INSERT INTO caps_features (node, feature) VALUES (:node, :feature)");
    static let capsInsertIdentityForNode = Query("INSERT INTO caps_identities (node, name, category, type) VALUES (:node, :name, :category, :type)");
    static let capsCountFeaturesForNode = Query("SELECT count(feature) FROM caps_features WHERE node = :node");
}

class DBCapabilitiesCache: CapabilitiesCache {
    
    public static let instance = DBCapabilitiesCache();
    
    public let queue: DispatchQueue;
    
    private var features = [String: [String]]();
    private var identities: [String: [DiscoveryModule.Identity]] = [:];
    
    fileprivate init() {
        queue = DispatchQueue(label: "DBCapabilitiesCache", attributes: .concurrent);
    }

    open func features(for node: String) -> [String]? {
        return queue.sync {
            guard let features = self.features[node] else {
                let features = try! Database.main.reader({ database in
                    try database.select(query: .capsFindFeaturesForNode, params: ["node": node]).mapAll({ $0.string(for: "feature")});
                })
                guard !features.isEmpty else {
                    return nil;
                }
                self.features[node] = features;
                return features;
            }
            return features;
        }
    }
    
    open func identities(for node: String) -> [DiscoveryModule.Identity]? {
        return queue.sync {
            guard let identities = self.identities[node] else {
                let identities = try! Database.main.reader({ database in
                    try database.select(query: .capsFindIdentityForNode, params: ["node": node]).mapAll({ cursor -> DiscoveryModule.Identity? in
                        guard let category = cursor.string(for: "category"), let type = cursor.string(for: "type") else {
                            return nil;
                        }
                        return DiscoveryModule.Identity(category: category, type: type, name: cursor.string(for: "name"));
                    });
                });
                if !identities.isEmpty {
                    self.identities[node] = identities;
                    return identities;
                } else {
                    return nil;
                }
            }
            return identities;
        }
    }
    
    open func nodes(withFeature feature: String) -> [String] {
        return try! Database.main.reader({ database in
            try database.select(query: .capsFindNodesWithFeature, params: ["feature": feature]).mapAll({ $0.string(for: "node") });
        })
    }
    
    open func isCached(node: String) -> Bool {
        queue.sync {
            return self._isCached(node: node);
        }
    }
    
    open func isSupported(feature: String, for node: String) -> Bool {
        return features(for: node)?.contains(feature) ?? false;
    }
    
    open func areSupported(features: [String], for node: String) -> Bool {
        return features.allSatisfy({ isSupported(feature: $0, for: node) });
    }
    
    open func store(node: String, identities: [DiscoveryModule.Identity], features: [String]) {
        queue.async(flags: .barrier) {
            guard !self._isCached(node: node) else {
                return;
            }
            
            self.features[node] = features;
            self.identities[node] = identities;
            
            try! Database.main.writer({ database in
                for feature in features {
                    try database.insert(query: .capsInsertFeatureForNode, params: ["node": node, "feature": feature]);
                }
                for identity in identities {
                    try database.insert(query: .capsInsertIdentityForNode, params: ["node": node, "name": identity.name, "category": identity.category, "type": identity.type]);
                }
            })
        }
    }
    
    fileprivate func _isCached(node: String) -> Bool {
        do {
            return try Database.main.reader({ database in
                try database.count(query: .capsCountFeaturesForNode, params: ["node": node]);
            }) > 0
        } catch {
            // it is better to assume that we have features...
            return true;
        }
    }

}
