//
// ShareLocationController.swift
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
import AppKit
import CoreLocation
import MapKit

class ShareLocationController: NSViewController, CLLocationManagerDelegate, MKMapViewDelegate {
    
    @IBOutlet var mapView: MKMapView!;
    
    var conversation: Conversation!;
    
    private let locationManager = CLLocationManager();
    
    private let currentAnnotation = MKPointAnnotation();
    private var inProgress: Bool = false;
    private var requestLocationItem: NSToolbarItem? {
        didSet {
            requestLocationItem?.target = self;
            requestLocationItem?.action = #selector(requestCurrentLocation(_:));
            requestLocationItem?.isEnabled = true;
            if #available(macOS 11.0, *) {
            } else {
                requestLocationItem?.image = NSImage(named: "location")
            }
        }
    }
    private var searchField: LocationSuggestionField?;
    
    private var cancellables: Set<AnyCancellable> = [];
    
    override func viewDidLoad() {
        super.viewDidLoad();
        locationManager.delegate = self;
        
        let clickGesture = NSPressGestureRecognizer(target: self, action: #selector(handleClick(_:)));
        self.mapView.addGestureRecognizer(clickGesture);
    }
    
    override func viewWillAppear() {
        cancellables.removeAll();
        super.viewWillAppear();
        requestLocationItem = view.window?.toolbar?.items.first(where: { $0.itemIdentifier.rawValue == "RequestCurrentLocation" })

        searchField = (view.window?.toolbar as? ShareLocationWindowToolbar)?.searchField;
        searchField?.mapViewRegion = mapView.region;
        searchField?.selectionPublisher.sink(receiveValue: { [weak self] placemark in
            self?.setCurrentLocation(placemark: placemark, coordinate: placemark.coordinate, zoomIn: true);
        }).store(in: &cancellables);
    }
    
    @objc func requestCurrentLocation(_ sender: Any) {
        guard CLLocationManager.locationServicesEnabled() else {
            let alert = NSAlert();
            alert.messageText = NSLocalizedString("Can't show your location", comment: "error message text");
            alert.informativeText = NSLocalizedString("To show current location, enable Wi-Fi network.", comment: "error message details");
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "button label"));
            alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                
            });
            return;
        }
        
        switch CLLocationManager.authorizationStatus() {
        case .authorizedAlways, .authorized:
            requestLocation();
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization();
        case .denied, .restricted:
            let alert = NSAlert();
            alert.messageText = NSLocalizedString("Can't show your location", comment: "error message text");
            alert.informativeText = NSLocalizedString("You've denied access to your location for this app. You need to allow it in System Preferences.", comment: "error message details");
            alert.addButton(withTitle: NSLocalizedString("OK", comment: "button label"));
            alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
                
            });
        default:
            break;
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if CLLocationManager.authorizationStatus() == .authorizedAlways || CLLocationManager.authorizationStatus() == .authorized {
            requestLocation();
        }
    }
    
    private func requestLocation() {
        inProgress = true;
        locationManager.requestLocation();
    }
    
    @objc func handleClick(_ sender: NSPressGestureRecognizer) {
        guard sender.state == .ended else {
            return;
        }
        
        let coordinate = self.mapView.convert(sender.location(in: self.mapView), toCoordinateFrom: self.mapView);
        setCurrentLocation(CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), zoomIn: false);
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("received locations:", locations);
        guard let location = locations.first, inProgress else {
            return;
        }
        inProgress = false;
        setCurrentLocation(location, zoomIn: true);
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let alert = NSAlert();
        alert.messageText = NSLocalizedString("Can't show your location", comment: "error message text");
        alert.informativeText = error.localizedDescription;
        alert.addButton(withTitle: NSLocalizedString("OK", comment: "button label"));
        alert.beginSheetModal(for: self.view.window!, completionHandler: { response in
            
        });
    }
    
    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        let view = MKPinAnnotationView(annotation: annotation, reuseIdentifier: nil);
        view.isEnabled = true;
        view.isDraggable = true;
        view.canShowCallout = true;
        
        let accessory = NSButton(image: NSImage(named: "location.fill")!, target: self, action: #selector(shareSelectedLocation));
        accessory.isBordered = false;
        accessory.isTransparent = false;
        accessory.frame = CGRect(origin: .zero, size: CGSize(width: 20, height: 20));
        view.rightCalloutAccessoryView = accessory;
        return view;
    }
        
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
        if newState == .ending, let annotation = view.annotation {
            setCurrentLocation(CLLocation(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude), zoomIn: false);
        }
    }
    
    @objc func shareSelectedLocation(_ sender: Any) {
        print("sharing currently selected location!");
        conversation.sendMessage(text: currentAnnotation.geoUri, correctedMessageOriginId: nil);
        self.view.window?.orderOut(self);
    }
    
    func setCurrentLocation(placemark place: CLPlacemark, coordinate: CLLocationCoordinate2D, zoomIn: Bool) {
        self.mapView.removeAnnotation(currentAnnotation);
        currentAnnotation.coordinate = coordinate;
        let address = [place.name, place.thoroughfare, place.locality, place.subLocality, place.administrativeArea, place.postalCode, place.country].compactMap({ $0 });
        if address.isEmpty {
            self.currentAnnotation.title = NSLocalizedString("Your location", comment: "search location pin label");
        } else {
            self.currentAnnotation.title = address.first;
        }
        DispatchQueue.main.async {
            if zoomIn {
                self.mapView.setRegion(MKCoordinateRegion(center: coordinate, latitudinalMeters: 2000, longitudinalMeters: 2000), animated: true);
            } else {
                self.mapView.centerCoordinate = coordinate;
            }
            self.searchField?.mapViewRegion = self.mapView.region;
            
            DispatchQueue.main.async {
                self.mapView.addAnnotation(self.currentAnnotation);
                self.mapView.selectAnnotation(self.currentAnnotation, animated: true);
            }
        }
    }
    
    private func setCurrentLocation(_ location: CLLocation, zoomIn: Bool) {
        self.mapView.removeAnnotation(currentAnnotation);
        
        
        let geocoder = CLGeocoder();
        geocoder.reverseGeocodeLocation(location, completionHandler: { (places, error) in
            guard error == nil, let place = places?.first else {
                return;
            }
            self.setCurrentLocation(placemark: place, coordinate: location.coordinate, zoomIn: zoomIn);
        })
    }
}

class ShareLocationWindowController: NSWindowController {
//
//    @IBOutlet var requestLocationItem: NSToolbarItem? {
//        didSet {
//            requestLocationItem?.target = self;
//            requestLocationItem?.action = #selector(requestCurrentLocation(_:));
//            requestLocationItem?.isEnabled = true;
//        }
//    }
//
//    @IBAction func requestCurrentLocation(_ sender: Any) {
//        (contentViewController as? ShareLocationController)?.requestCurrentLocation();
//    }
//
//    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
//        return true;
//    }
//
}

class ShareLocationWindowToolbar: NSToolbar {
    
    @IBOutlet var searchField: LocationSuggestionField!;
    
}

import Combine

class LocationSuggestionField: NSSearchField, NSSearchFieldDelegate {
    
    private var suggestionsController: SuggestionsWindowController?;
    
    var mapViewRegion: MKCoordinateRegion = MKCoordinateRegion();
    let selectionPublisher = PassthroughSubject<MKPlacemark,Never>();
        
    private var id = UUID();
    
    required init?(coder: NSCoder) {
        super.init(coder: coder);
        self.setup();
    }
    
    init() {
        super.init(frame: .zero);
        self.setup();
    }
    
    override func awakeFromNib() {
        super.awakeFromNib();
        self.setup();
    }
    
    func setup() {
        self.delegate = self;
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        if suggestionsController == nil {
            suggestionsController = SuggestionsWindowController(viewProviders: [LocationSuggestionItemView.Provider()], edge: .bottom);
            suggestionsController?.target = self;
            suggestionsController?.action = #selector(self.suggestionItemSelected(sender:))
            suggestionsController?.yOffset = self.frame.height * -1;
        }
//        suggestionsController?.beginFor(textField: self.searchField!);
    }
    
    func controlTextDidChange(_ obj: Notification) {
        let id = UUID();
        self.id = id;
        if self.stringValue.count < 2 {
            suggestionsController?.cancelSuggestions();
        } else {
            let query = self.stringValue;
            
            
            let request = MKLocalSearch.Request();
            request.naturalLanguageQuery = query;
            request.region = mapViewRegion;
            
            let search = MKLocalSearch(request: request);
            search.start(completionHandler: { (response, _) in
                guard let response = response, self.id == id else {
                    return;
                }
                
                let items = response.mapItems.map({ $0.placemark });
                if !items.isEmpty {
                    if !(self.suggestionsController?.window?.isVisible ?? false) {
                        self.suggestionsController?.beginFor(textField: self);
                    }
                }
                print("updating items:", items);
                self.suggestionsController?.update(suggestions: items);
            });
        }
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        suggestionsController?.cancelSuggestions();
    }
    
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            suggestionsController?.moveUp(textView);
            return true
        case #selector(NSResponder.moveDown(_:)):
            suggestionsController?.moveDown(textView);
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if let controller = self.suggestionsController {
                suggestionItemSelected(sender: controller);
            }
        case #selector(NSResponder.complete(_:)):
            suggestionsController?.cancelSuggestions();
            return true;
        default:
            break;
        }
        return false;
    }
    
    @objc func suggestionItemSelected(sender: Any) {
        guard let item = (sender as? SuggestionsWindowController)?.selected as? MKPlacemark else {
            return;
        }
        
        self.stringValue = "";
        
        selectionPublisher.send(item);
    }
    
}

class LocationSuggestionItemView: SuggestionItemViewBase<MKPlacemark> {
    
    struct Provider: SuggestionItemViewProvider {
        
        func view(for item: Any) -> SuggestionItemView? {
            guard item is MKPlacemark else {
                return nil;
            }
            return LocationSuggestionItemView();
        }
        
    }
    
    private let image: NSImageView;
    private let title: NSTextField;
    private let subtitle: NSTextField;
    private let stack: NSStackView;
    private let detailsStack: NSStackView;
    private let imageHeightConstraint: NSLayoutConstraint;
    
    override var item: MKPlacemark? {
        didSet {
            self.title.stringValue = item?.name ?? "";
            if let item = self.item {
                self.subtitle.stringValue = [item.thoroughfare, item.locality, item.subLocality, item.administrativeArea, item.postalCode, item.country].compactMap({ $0 }).joined(separator: ", ");
            } else {
                self.subtitle.stringValue = "";
            }
        }
    }
    
    override var itemHeight: Int {
        return 36;
    }

    required init() {
        image = NSImageView(image: NSImage(named: "location.fill")!);
        image.imageScaling = .scaleProportionallyUpOrDown;
        title = NSTextField(labelWithString: "");
//        title.font = NSFont.preferredFont(forTextStyle: .headline);
        title.font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium);
        title.cell?.truncatesLastVisibleLine = true;
        title.cell?.lineBreakMode = .byTruncatingTail;
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        subtitle = NSTextField(labelWithString: "");
//        subtitle = NSFont.preferredFont(forTextStyle: .subheadline);
        subtitle.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .light);
        subtitle.cell?.truncatesLastVisibleLine = true;
        subtitle.cell?.lineBreakMode = .byTruncatingTail;
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        detailsStack = NSStackView(views: [title, subtitle]);
        detailsStack.spacing = 0;
        detailsStack.alignment = .leading;
        detailsStack.orientation = .vertical;
        detailsStack.distribution = .equalCentering;
        detailsStack.setHuggingPriority(.defaultHigh, for: .horizontal);
        detailsStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        detailsStack.visibilityPriority(for: title);
        
        stack = NSStackView(views: [image, detailsStack]);
        stack.translatesAutoresizingMaskIntoConstraints = false;
        stack.spacing = 6;
        stack.alignment = .centerY;
        stack.orientation = .horizontal;
        stack.distribution = .fill;
//            stack.setHuggingPriority(.defaultHigh, for: .vertical);
        stack.setHuggingPriority(.defaultHigh, for: .horizontal);
        stack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal);
        stack.visibilityPriority(for: image);
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4);
        
        self.imageHeightConstraint = image.heightAnchor.constraint(equalToConstant: 28);
        NSLayoutConstraint.activate([
            imageHeightConstraint,
            image.heightAnchor.constraint(equalTo: image.widthAnchor),
            image.heightAnchor.constraint(equalTo: stack.heightAnchor, multiplier: 1.0, constant: -4 * 2),
            detailsStack.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -4)
        ])
        
        super.init();
        addSubview(stack);
        NSLayoutConstraint.activate([
            self.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            self.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            self.topAnchor.constraint(equalTo: stack.topAnchor),
            self.bottomAnchor.constraint(equalTo: stack.bottomAnchor)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

extension MKPointAnnotation {
    
    var geoUri: String {
        return coordinate.geoUri;
    }
    
}

extension CLLocationCoordinate2D {
    
    public static let geoRegex = try! NSRegularExpression(pattern: "geo:\\-?[0-9]+\\.?[0-9]*,\\-?[0-9]+\\.?[0-9]*");
    
    public var geoUri: String {
        return "geo:\(self.latitude),\(self.longitude)";
    }
    
    public init?(geoUri: String) {
        guard geoUri.starts(with: "geo:"), !CLLocationCoordinate2D.geoRegex.matches(in: geoUri, options: [], range: NSRange(location: 0, length: geoUri.count)).isEmpty else {
            return nil;
        }
        let parts = geoUri.dropFirst(4).split(separator: ",").compactMap({ Double(String($0)) });
        guard parts.count == 2 else {
            return nil;
        }
        self.init(latitude: parts[0], longitude: parts[1]);
    }
    
}

extension CLLocationCoordinate2D: Hashable {
    
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude;
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.latitude);
        hasher.combine(self.longitude);
    }
    
}
