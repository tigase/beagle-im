//
// DBCapabilitiesCache.swift
//
// BeagleIM
// Copyright (C) 2018 "Tigase, Inc." <office@tigase.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License,
// or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program. Look for COPYING file in the top folder.
// If not, see http://www.gnu.org/licenses/.
//

import Foundation
import TigaseSwift

class DBCapabilitiesCache: CapabilitiesCache {
    
    public static let instance = DBCapabilitiesCache();
    
    public let dispatcher: QueueDispatcher;

    fileprivate var getFeatureStmt: DBStatement;
    fileprivate var getIdentityStmt: DBStatement;
    fileprivate var getNodesWithFeatureStmt: DBStatement;
    fileprivate var insertFeatureStmt: DBStatement;
    fileprivate var insertIdentityStmt: DBStatement;
    fileprivate var nodeIsCached: DBStatement;
    fileprivate var featureIsSupported: DBStatement;

    fileprivate var features = [String: [String]]();
    fileprivate var identities: [String: DiscoveryModule.Identity] = [:];
    
    fileprivate init() {
        getFeatureStmt = try! DBConnection.main.prepareStatement("SELECT feature FROM caps_features WHERE node = :node");
        getIdentityStmt = try! DBConnection.main.prepareStatement("SELECT name, category, type FROM caps_identities WHERE node = :node");
        getNodesWithFeatureStmt = try! DBConnection.main.prepareStatement("SELECT node FROM caps_features WHERE feature = :features");
        insertFeatureStmt = try! DBConnection.main.prepareStatement("INSERT INTO caps_features (node, feature) VALUES (:node, :feature)");
        insertIdentityStmt = try! DBConnection.main.prepareStatement("INSERT INTO caps_identities (node, name, category, type) VALUES (:node, :name, :category, :type)");
        nodeIsCached = try! DBConnection.main.prepareStatement("SELECT count(feature) FROM caps_features WHERE node = :node");
        featureIsSupported = try! DBConnection.main.prepareStatement("SELECT count(feature) FROM caps_features WHERE node = :node AND feature = :feature");
        dispatcher = QueueDispatcher(label: "DBCapabilitiesCache");
    }

    open func getFeatures(for node: String) -> [String]? {
        return dispatcher.sync {
            guard let features = self.features[node] else {
                let features: [String] = try! self.getFeatureStmt.query(node) {cursor in cursor["feature"]! };
                guard !features.isEmpty else {
                    return nil;
                }
                self.features[node] = features;
                return features;
            }
            return features;
        }
    }
    
    open func getIdentity(for node: String) -> DiscoveryModule.Identity? {
        return dispatcher.sync {
            guard let identity = self.identities[node] else {
                guard let (category, type, name): (String?, String?, String?) = try! self.getIdentityStmt.findFirst(node, map: { cursor in
                    return (cursor["category"], cursor["type"], cursor["name"]);
                }) else {
                    return nil;
                }
                
                let identity = DiscoveryModule.Identity(category: category!, type: type!, name: name);
                self.identities[node] = identity;
                return identity;
            }
            return identity;
        }
    }
    
    open func getNodes(withFeature feature: String) -> [String] {
        return dispatcher.sync {
            return try! self.getNodesWithFeatureStmt.query(feature) { cursor in cursor["node"]! };
        }
    }
    
    open func isCached(node: String, handler: @escaping (Bool)->Void) {
        dispatcher.async {
            handler(self.isCached(node: node));
        }
    }
    
    open func isSupported(for node: String, feature: String) -> Bool {
        return getFeatures(for: node)?.contains(feature) ?? false;
    }
    
    open func store(node: String, identity: DiscoveryModule.Identity?, features: [String]) {
        dispatcher.async {
            guard !self.isCached(node: node) else {
                return;
            }
            
            self.features[node] = features;
            self.identities[node] = identity;
            
            for feature in features {
                _ = try! self.insertFeatureStmt.insert(node, feature);
            }
            
            if identity != nil {
                _ = try! self.insertIdentityStmt.insert(node, identity!.name, identity!.category, identity!.type);
            }
        }
    }
    
    fileprivate func isCached(node: String) -> Bool {
        do {
            let val = try self.nodeIsCached.scalar(node) ?? 0;
            return val != 0;
        } catch {
            // it is better to assume that we have features...
            return true;
        }
    }

}
