//
// ChatLocationCellView.swift
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
import MapKit

class CustomMapView: MKMapView {

    override func scrollWheel(with event: NSEvent) {
        superScrollWheel(with: event);
    }
    
}

extension MKMapView {
    
    func superScrollWheel(with event: NSEvent) {
        super.scrollWheel(with: event);
    }
    
}

class ChatLocationCellView: BaseChatCellView {

    @IBOutlet var mapView: MKMapView! {
        didSet {
            let toRemove = mapView.gestureRecognizers;
            for item in toRemove {
                mapView.removeGestureRecognizer(item);
            }
            let recognizer = NSClickGestureRecognizer(target: self, action: #selector(mapClicked(_:)));
            mapView.addGestureRecognizer(recognizer);
            mapView.wantsLayer = true;
            mapView.layer?.cornerRadius = 10;
            mapView.layer?.masksToBounds = true;
            self.wantsLayer = true;
            self.canDrawSubviewsIntoLayer = true;
        }
    }
    var id: Int = 0;
                
    let annotation = MKPointAnnotation();

    override func set(item: ConversationEntry) {
        super.set(item: item);
        id = item.id;
    }
    
    func set(item: ConversationEntry, location: CLLocationCoordinate2D) {
        guard id != item.id else {
            return;
        }
        
        set(item: item);
        
//        if correctionTimestamp != nil, case .incoming(_) = item.state {
//            self.state!.stringValue = "✏️\(self.state!.stringValue)";
//        }
        mapView.removeAnnotation(annotation);
        annotation.coordinate = location;
        mapView.setRegion(MKCoordinateRegion(center: location, latitudinalMeters: 1000, longitudinalMeters: 1000), animated: false);
        mapView.addAnnotation(annotation);
    }

    @IBAction func mapClicked(_ sender: Any) {
        let placemark = MKPlacemark(coordinate: annotation.coordinate);
        let region = MKCoordinateRegion(center: annotation.coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000);
        let item = MKMapItem(placemark: placemark);
        item.openInMaps(launchOptions: [
            MKLaunchOptionsMapCenterKey: NSValue(mkCoordinate: region.center),
            MKLaunchOptionsMapSpanKey: NSValue(mkCoordinateSpan: region.span)
        ])
    }
}
