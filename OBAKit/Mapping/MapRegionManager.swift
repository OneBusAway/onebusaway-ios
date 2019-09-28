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
import OBAKitCore

// MARK: - MapRegionDelegate

@objc(OBAMapRegionDelegate)
public protocol MapRegionDelegate {
    @objc optional func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop])

    @objc optional func mapRegionManager(_ manager: MapRegionManager, noSearchResults response: SearchResponse)
    @objc optional func mapRegionManager(_ manager: MapRegionManager, disambiguateSearch response: SearchResponse)
    @objc optional func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse)

    @objc optional func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager)
    @objc optional func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager)

    @objc optional func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    @objc optional func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)

    @objc optional func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl)
}

// MARK: - MapRegionManager

public class MapRegionManager: NSObject, StopAnnotationDelegate, MKMapViewDelegate {

    private let application: Application

    private var regionChangeRequestTimer: Timer?

    private var userLocationAnnotationView: PulsingAnnotationView? {
        didSet {
            updateUserHeadingDisplay()
        }
    }

    public let mapView: MKMapView = {
        let mapView = MKMapView()
        mapView.mapType = .mutedStandard
        mapView.showsUserLocation = true
        mapView.showsCompass = false
        return mapView
    }()

    // MARK: - User Defaults

    /// Whether the map view displays current traffic conditions.
    ///
    /// `true` by default.
    public var mapViewShowsTraffic: Bool {
        get { application.userDefaults.bool(forKey: mapViewShowsTrafficKey) }
        set {
            application.userDefaults.set(newValue, forKey: mapViewShowsTrafficKey)
            mapView.showsTraffic = newValue
        }
    }
    private let mapViewShowsTrafficKey = "mapRegionManager.mapViewShowsTraffic"

    /// Whether the map view displays a scale indicator while zooming.
    ///
    /// `true` by default.
    public var mapViewShowsScale: Bool {
        get { application.userDefaults.bool(forKey: mapViewShowsScaleKey) }
        set {
            application.userDefaults.set(newValue, forKey: mapViewShowsScaleKey)
            mapView.showsScale = newValue
        }
    }
    private let mapViewShowsScaleKey = "mapRegionManager.mapViewShowsScale"

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        application.userDefaults.register(defaults: [
            mapViewShowsTrafficKey: true,
            mapViewShowsScaleKey: true
        ])

        super.init()

        application.locationService.addDelegate(self)

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized
        mapView.showsScale = mapViewShowsScale
        mapView.showsTraffic = mapViewShowsTraffic

        registerAnnotationViews(mapView: mapView)
        mapView.delegate = self
    }

    deinit {
        delegates.removeAllObjects()
        application.locationService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
        requestStopsOperation?.cancel()
    }

    // MARK: - Global Map Helpers

    public func registerAnnotationViews(mapView: MKMapView) {
        mapView.registerAnnotationView(StopAnnotationView.self)
        mapView.registerAnnotationView(PulsingAnnotationView.self)
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
            guard let newValue = newValue else { return }
            mapView.visibleMapRect = newValue
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

        // Add a 'fudge factor' around the current size of the map's
        // visible region. This will mean that we load some stops that
        // are just outside of the visible bounds of the screen, which
        // means that stops should (fingers crossed) seem to load instantly.
        var mapRegion = mapView.region
        mapRegion.span.latitudeDelta *= 1.1
        mapRegion.span.longitudeDelta *= 1.1

        let requestStopsOperation = modelService.getStops(region: mapRegion)
        requestStopsOperation.then { [weak self] in
            guard let self = self else { return }

            self.stops = requestStopsOperation.stops

            self.notifyDelegatesDataLoadingFinished()

            self.requestStopsOperation = nil
        }

        self.requestStopsOperation = requestStopsOperation
    }

    // MARK: - Delegates

    private let delegates = NSHashTable<MapRegionDelegate>.weakObjects()

    public func addDelegate(_ delegate: MapRegionDelegate) {
        delegates.add(delegate)
    }

    public func removeDelegate(_ delegate: MapRegionDelegate) {
        delegates.remove(delegate)
    }

    // MARK: - Delegates/Search

    private func notifyDelegatesNoSearchResults(response: SearchResponse) {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, noSearchResults: response)
        }
    }

    private func notifyDelegatesDisambiguationRequired(response: SearchResponse) {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, disambiguateSearch: response)
        }
    }

    private func notifyDelegatesShowSearchResult(response: SearchResponse) {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, showSearchResult: response)
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

    // MARK: - Map Status Overlay

    private lazy var statusOverlay = StatusOverlayView.autolayoutNew()

    /// This method will add `statusOverlay` as a subview of `mapView`, and set up necessary constraints.
    /// Call it in `viewDidAppear` of the view controller that hosts `mapView`.
    ///
    /// - Note: This method can be called repeatedly, and will not have any effect after the first invocation.
    ///
    public func addStatusOverlayToMap() {
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

    public func cancelSearch() {
        searchResponse = nil
        mapView.removeAllAnnotations()
        mapView.removeOverlays(mapView.overlays)
        reloadStopAnnotations()
    }

    private func searchResponseOverridesStopLoading() -> Bool {
        guard
            let searchResponse = searchResponse,
            searchResponse.results.count == 1,
            let result = searchResponse.results.first
        else { return false }

        return result is Route
    }

    public var searchResponse: SearchResponse? {
        didSet {
            guard let searchResponse = searchResponse else {
                return
            }

            if searchResponse.results.count == 0 {
                notifyDelegatesNoSearchResults(response: searchResponse)
            }
            else if searchResponse.results.count == 1, let result = searchResponse.results.first {
                if let result = result as? MKMapItem {
                    mapView.setCenter(result.placemark.coordinate, animated: true)
                    mapView.addAnnotation(result.placemark)
                    notifyDelegatesShowSearchResult(response: searchResponse)
                }
                else if let result = result as? Route {
                    loadSearchResponse(searchResponse, route: result)
                }
                else if let result = result as? StopsForRoute {
                    mapView.removeAllAnnotations()

                    mapView.addOverlays(result.polylines)
                    mapView.addAnnotations(result.stops)

                    let inset: CGFloat = 40.0
                    mapView.visibleMapRect = self.mapView.mapRectThatFits(result.mapRect, edgePadding: UIEdgeInsets(top: inset, left: inset, bottom: 200, right: inset))
                    notifyDelegatesShowSearchResult(response: searchResponse)
                }
            }
            else {
                notifyDelegatesDisambiguationRequired(response: searchResponse)
            }
        }
    }

    // MARK: - Search/Route

    func loadSearchResponse(_ searchResponse: SearchResponse, route: Route) {
        guard let apiService = application.restAPIModelService else { return }

        let op = apiService.getStopsForRoute(routeID: route.id)

        op.then { [weak self] in
            guard
                let self = self,
                let stopsForRoute = op.stopsForRoute
            else { return }

            let response = SearchResponse(response: searchResponse, substituteResult: stopsForRoute)
            self.searchResponse = response
        }
    }

    // MARK: - Stop Annotation Delegate

    func isStopBookmarked(_ stop: Stop) -> Bool {
        application.userDataStore.findBookmark(stopID: stop.id) != nil
    }

    var iconFactory: StopIconFactory {
        application.stopIconFactory
    }

    // MARK: - Map View Delegate

    private func reloadStopAnnotations() {
        if searchResponseOverridesStopLoading() {
            return
        }

        updateZoomWarningOverlay(mapHeight: mapView.visibleMapRect.height)

        guard mapView.visibleMapRect.height <= MapRegionManager.requiredHeightToShowStops else {
            return
        }

        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }

    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        reloadStopAnnotations()
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

        if let stopAnnotation = annotationView as? StopAnnotationView {
            stopAnnotation.delegate = self
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
        renderer.strokeColor = ThemeColors.shared.primary.withAlphaComponent(0.75)
        renderer.lineWidth = 3.0
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
