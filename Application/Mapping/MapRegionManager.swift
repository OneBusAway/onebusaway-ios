//
//  MapRegionManager.swift
//  OBAKit
//
//  Created by Aaron Brethorst on 11/21/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import UIKit
import CoreLocation
import MapKit

@objc(OBAMapRegionDelegate)
public protocol MapRegionDelegate {
    @objc optional func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop])
    @objc optional func mapRegionManager(_ manager: MapRegionManager, searchUpdated searchResponse: SearchResponse)

    @objc optional func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager)
    @objc optional func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager)

    @objc optional func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    @objc optional func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)

    @objc optional func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl)
}

@objc(OBAMapRegionManager)
public class MapRegionManager: NSObject {

    private let application: Application

    private var regionChangeRequestTimer: Timer?

    private var userLocationAnnotationView: PulsingAnnotationView? {
        didSet {
            updateUserHeadingDisplay()
        }
    }

    @objc public let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.mapType = .mutedStandard

        return mapView
    }()

    @objc public init(application: Application) {
        self.application = application

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized

        super.init()

        application.locationService.addDelegate(self)

        mapView.registerAnnotationView(StopAnnotationView.self)
        mapView.registerAnnotationView(PulsingAnnotationView.self)
        mapView.delegate = self
    }

    deinit {
        delegates.removeAllObjects()
        application.locationService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
        requestStopsOperation?.cancel()
    }

    // MARK: - Map Information

    public var visibleMapRect: MKMapRect? {
        get {
            guard let currentRegion = application.regionsService.currentRegion else {
                return nil
            }

            if currentRegion.serviceRect.contains(mapView.visibleMapRect) {
                return mapView.visibleMapRect
            }
            else {
                return currentRegion.serviceRect
            }
        }
        set {
            if let v = newValue {
                mapView.visibleMapRect = v
            }
        }
    }

    // MARK: - Data Loading

    @objc func requestDataForMapRegion(_ timer: Timer) {
        guard let modelService = application.restAPIModelService else {
            return
        }

        self.requestStopsOperation?.cancel()
        self.requestStopsOperation = nil

        notifyDelegatesDataLoadingStarted()

        let requestStopsOperation = modelService.getStops(region: mapView.region)
        requestStopsOperation.then { [weak self] in
            guard let self = self else {
                return
            }

            self.stops = requestStopsOperation.stops

            self.notifyDelegatesDataLoadingFinished()
        }

        self.requestStopsOperation = requestStopsOperation
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<MapRegionDelegate>.weakObjects()

    @objc
    public func addDelegate(_ delegate: MapRegionDelegate) {
        delegates.add(delegate)
    }

    @objc
    public func removeDelegate(_ delegate: MapRegionDelegate) {
        delegates.remove(delegate)
    }

    private func notifyDelegatesSearchResultsChanged() {
        guard let searchResponse = searchResponse else {
            return
        }

        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, searchUpdated: searchResponse)
        }
    }

    private func notifyDelegatesStopsChanged() {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, stopsUpdated: stops)
        }
    }

    /// Notifies delegates that data loading has started.
    /// In UI terms, this should mean that a loading indicator is shown in the app.
    private func notifyDelegatesDataLoadingStarted() {
        for delegate in delegates.allObjects {
            delegate.mapRegionManagerDataLoadingStarted?(self)
        }
    }

    /// Notifies delegates that data loading has finished.
    /// In UI terms, this should mean that a loading indicator is hidden in the app.
    private func notifyDelegatesDataLoadingFinished() {
        for delegate in delegates.allObjects {
            delegate.mapRegionManagerDataLoadingFinished?(self)
        }
    }

    // MARK: - Operations

    private var requestStopsOperation: StopsModelOperation?

    // MARK: - Stops

    public private(set) var stops = [Stop]() {
        didSet {
            mapView.updateAnnotations(with: stops)
            notifyDelegatesStopsChanged()
        }
    }

    public func fetchStopWithID(_ id: String, completion: @escaping (Stop?) -> Void) {
        if let stop = (stops.filter {$0.id == id}).first {
            completion(stop)
            return
        }

        guard let modelService = application.restAPIModelService else {
            return
        }

        let op = modelService.getStop(id: id)
        op.then {
            completion(op.stops.first)
        }
    }

    // MARK: - Overlays

    private var walkingDirectionsOverlay: MKOverlay?
    private var walkingDirectionsStop: Stop?

    /// Adds a map overlay specifically to show walking directions from the user's current location to the stop
    ///
    /// - Parameters:
    ///   - overlay: The walking directions overlay.
    ///   - stop: The stop to which the walking directions point.
    public func addWalkingDirectionsOverlay(_ overlay: MKOverlay, for stop: Stop) {
        if let walkingDirectionsOverlay = walkingDirectionsOverlay {
            mapView.removeOverlay(walkingDirectionsOverlay)
        }

        walkingDirectionsOverlay = overlay
        walkingDirectionsStop = stop

        mapView.addOverlay(walkingDirectionsOverlay!, level: MKOverlayLevel.aboveRoads)
    }

    /// Removes the walking directions overlay that matches `stop`.
    ///
    /// - Parameter stop: The stop to which walking directions should be removed.
    public func removeWalkingDirectionsOverlay(for stop: Stop) {
        guard
            walkingDirectionsStop == stop,
            let walkingDirectionsOverlay = walkingDirectionsOverlay
        else {
            return
        }

        self.walkingDirectionsStop = nil
        self.walkingDirectionsOverlay = nil
        mapView.removeOverlay(walkingDirectionsOverlay)
    }

    // MARK: - Map Status Overlay

    private lazy var statusOverlay = StatusOverlayView.autolayoutNew()

    /// This method will add `statusOverlay` as a subview of `mapView`, and set up necessary constraints.
    /// Call it in `viewDidAppear` of the view controller that hosts `mapView`.
    ///
    /// - Note: This method can be called repeatedly, and will not have any effect after the first invocation.
    ///
    @objc public func addStatusOverlayToMap() {
        guard statusOverlay.superview == nil else {
            return
        }

        mapView.addSubview(statusOverlay)

        NSLayoutConstraint.activate([
            statusOverlay.centerXAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.centerXAnchor),
            statusOverlay.topAnchor.constraint(equalTo: mapView.safeAreaLayoutGuide.topAnchor, constant: ThemeMetrics.padding)
        ])
    }

    private static let requiredHeightToShowStops = 75000.0

    private func updateZoomWarningOverlay(mapHeight: Double) {
        let animated = statusOverlay.superview != nil

        if mapHeight > MapRegionManager.requiredHeightToShowStops {
            let message = NSLocalizedString("map_region_manager.status_overlay.zoom_to_see_stops", value: "Zoom in to look for stops", comment: "Map region manager message to the user when they need to zoom in more to view stops")
            statusOverlay.showOverlay(message: message, animated: animated)
        }
        else {
            statusOverlay.hideOverlay(animated: animated)
        }
    }

    // MARK: - Search

    public var searchResponse: SearchResponse? {
        didSet {
            notifyDelegatesSearchResultsChanged()
        }
    }
}

// MARK: - Map View Delegate

extension MapRegionManager: MKMapViewDelegate {
    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        updateZoomWarningOverlay(mapHeight: mapView.visibleMapRect.height)

        guard mapView.visibleMapRect.height <= MapRegionManager.requiredHeightToShowStops else {
            return
        }

        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        for delegate in delegates.allObjects {
            delegate.mapView?(mapView, didSelect: view)
        }
    }

    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        for delegate in delegates.allObjects {
            delegate.mapView?(mapView, didDeselect: view)
        }
    }

    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        for delegate in delegates.allObjects {
            delegate.mapView?(mapView, annotationView: view, calloutAccessoryControlTapped: control)
        }
    }

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let reuseIdentifier = reuseIdentifier(for: annotation) else {
            return nil
        }

        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier, for: annotation)

        if self.userLocationAnnotationView == nil, let userLocation = annotationView as? PulsingAnnotationView {
            self.userLocationAnnotationView = userLocation
        }

        return annotationView
    }

    private func reuseIdentifier(for annotation: MKAnnotation) -> String? {
        switch annotation {
        case is MKUserLocation: return MKMapView.reuseIdentifier(for: PulsingAnnotationView.self)
        case is Stop: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        default: return nil
        }
    }

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline) // swiftlint:disable:this force_cast
        renderer.strokeColor = application.theme.colors.primary.withAlphaComponent(0.75)
        renderer.lineWidth = 6.0
        renderer.lineCap = .round

        return renderer
    }
}

// MARK: - Location Service Delegate

extension MapRegionManager: LocationServiceDelegate {
    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        mapView.showsUserLocation = service.isLocationUseAuthorized
    }

    public func locationService(_ service: LocationService, headingChanged heading: CLHeading?) {
        updateUserHeadingDisplay()
    }

    private func updateUserHeadingDisplay() {
        guard
            let heading = application.locationService.currentHeading,
            let annotationView = userLocationAnnotationView
        else {
            return
        }

        if annotationView.headingImage == nil {
            annotationView.headingImage = Icons.userHeading
        }

        // The PulsingAnnotationView treats east as 0º.
        annotationView.headingImageView.transform = heading.trueHeading.affineTransform(rotatedBy: -0.5 * .pi)
    }
}
