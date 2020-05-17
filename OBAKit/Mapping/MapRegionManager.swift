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
import CocoaLumberjackSwift

// MARK: - MapRegionDelegate

@objc(OBAMapRegionDelegate)
public protocol MapRegionDelegate {
    @objc optional func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop])

    @objc optional func mapRegionManager(_ manager: MapRegionManager, noSearchResults response: SearchResponse)
    @objc optional func mapRegionManager(_ manager: MapRegionManager, disambiguateSearch response: SearchResponse)
    @objc optional func mapRegionManager(_ manager: MapRegionManager, showSearchResult response: SearchResponse)

    @objc optional func mapRegionManagerDismissSearch(_ manager: MapRegionManager)

    @objc optional func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager)
    @objc optional func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager)
}

protocol MapRegionMapViewDelegate: NSObjectProtocol {
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl)
    func mapRegionManager(_ manager: MapRegionManager, customize stopAnnotationView: StopAnnotationView)
}

// MARK: - MapRegionManager

public class MapRegionManager: NSObject,
    MKMapViewDelegate,
    RegionsServiceDelegate,
    StopAnnotationDelegate {

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

    /// Whether the map view shows the direction the user is currently facing in.
    ///
    /// Defaults to `true`.
    public var mapViewShowsHeading: Bool {
        get { application.userDefaults.bool(forKey: mapViewShowsHeadingKey) }
        set {
            application.userDefaults.set(newValue, forKey: mapViewShowsHeadingKey)
            userLocationAnnotationView?.headingImageView.isHidden = !newValue
        }
    }
    private let mapViewShowsHeadingKey = "mapRegionManager.mapViewShowsHeadingKey"

    /// Provides storage for the last visible map rect of the map view.
    /// 
    /// In the event that this value is unavailable, the getter will try to offer up an alternative,
    /// such as the current region's service rect.
    public var lastVisibleMapRect: MKMapRect? {
        get {
            var lastRect = application.regionsService.currentRegion?.serviceRect

            guard let rawValue = application.userDefaults.value(forKey: lastVisibleMapRectKey) as? Data else {
                return lastRect
            }

            do {
                lastRect = try PropertyListDecoder().decode(MKMapRect.self, from: rawValue)
            } catch let error {
                DDLogError("Unable to decode last visible map rect: \(error)")
            }

            return lastRect
        }
        set {
            do {
                let encodedValue = try PropertyListEncoder().encode(newValue)
                application.userDefaults.set(encodedValue, forKey: lastVisibleMapRectKey)
            } catch let error {
                DDLogError("Unable to encode last visible map rect: \(error)")
            }
        }
    }
    private let lastVisibleMapRectKey = "mapRegionManager.lastVisibleMapRect"

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        application.userDefaults.register(defaults: [
            mapViewShowsTrafficKey: true,
            mapViewShowsScaleKey: true,
            mapViewShowsHeadingKey: true
        ])

        super.init()

        application.locationService.addDelegate(self)
        application.regionsService.addDelegate(self)

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized
        mapView.showsScale = mapViewShowsScale
        mapView.showsTraffic = mapViewShowsTraffic

        registerAnnotationViews(mapView: mapView)

        mapView.delegate = self

        renderRegionsOnMap()
    }

    deinit {
        mapView.delegate = nil
        mapView.removeAllAnnotations()
        delegates.removeAllObjects()
        application.locationService.removeDelegate(self)
        application.regionsService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
        requestStopsOperation?.cancel()
    }

    // MARK: - Global Map Helpers

    public func registerAnnotationViews(mapView: MKMapView) {
        mapView.registerAnnotationView(MinimalStopAnnotationView.self)
        mapView.registerAnnotationView(MKMarkerAnnotationView.self)
        mapView.registerAnnotationView(StopAnnotationView.self)
        mapView.registerAnnotationView(PulsingAnnotationView.self)
        mapView.registerAnnotationView(PulsingVehicleAnnotationView.self)
    }

    // MARK: - Data Loading

    @objc func requestDataForMapRegion(_ timer: Timer) {
        guard let apiService = application.restAPIService else {
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

        let op = apiService.getStops(region: mapRegion)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                self.stops = response.list
                self.notifyDelegatesDataLoadingFinished()
                self.requestStopsOperation = nil
            }
        }

        self.requestStopsOperation = op
    }

    // MARK: - Map View Delegate

    weak var mapViewDelegate: MapRegionMapViewDelegate?

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

    /// Instructs delegates to close/dismiss their search UIs.
    private func notifyDelegatesDismissSearch() {
        for delegate in delegates.allObjects {
            delegate.mapRegionManagerDismissSearch?(self)
        }
    }

    // MARK: - Operations

    private var requestStopsOperation: DecodableOperation<RESTAPIResponse<[Stop]>>?

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

        guard let apiService = application.restAPIService else {
            return
        }

        let op = apiService.getStop(id: id)
        op.complete { result in
            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                completion(response.list.first)
            }
        }
    }

    // MARK: - Map Status Overlay

    weak var statusOverlay: StatusOverlayView?

    private static let requiredHeightToShowStops = 40000.0

    private func updateZoomWarningOverlay(mapHeight: Double) {
        guard let statusOverlay = statusOverlay else { return }

        let animated = statusOverlay.superview != nil

        if mapHeight > MapRegionManager.requiredHeightToShowStops {
            let message = OBALoc("map_region_manager.status_overlay.zoom_to_see_stops", value: "Zoom in to look for stops", comment: "Map region manager message to the user when they need to zoom in more to view stops")
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
            searchResponse.results.count == 1
        else { return false }

        return true
    }

    public var searchResponse: SearchResponse? {
        didSet {
            guard let searchResponse = searchResponse else {
                return
            }

            guard searchResponse.results.count > 0 else {
                notifyDelegatesNoSearchResults(response: searchResponse)
                return
            }

            guard
                searchResponse.results.count == 1,
                let result = searchResponse.results.first
            else {
                notifyDelegatesDisambiguationRequired(response: searchResponse)
                return
            }

            switch result {
            case let result as MKMapItem:
                displaySearchResult(mapItem: result)
                notifyDelegatesShowSearchResult(response: searchResponse)
            case let result as Route:
                loadSearchResponse(searchResponse, route: result)
            case let result as StopsForRoute:
                displaySearchResult(stopsForRoute: result)
                notifyDelegatesShowSearchResult(response: searchResponse)
            case let result as Stop:
                displaySearchResult(stop: result)
                notifyDelegatesDismissSearch()
            case is VehicleStatus:
                notifyDelegatesShowSearchResult(response: searchResponse)
            default:
                DDLogError("Unhandled search result object! \(result)")
            }
        }
    }

    private func displaySearchResult(mapItem: MKMapItem) {
        mapView.setCenter(mapItem.placemark.coordinate, animated: true)
        mapView.addAnnotation(mapItem.placemark)
    }

    private func displaySearchResult(stopsForRoute: StopsForRoute) {
        mapView.removeAllAnnotations()

        mapView.addOverlays(stopsForRoute.polylines)
        mapView.addAnnotations(stopsForRoute.stops)

        let inset: CGFloat = 40.0
        mapView.visibleMapRect = self.mapView.mapRectThatFits(stopsForRoute.mapRect, edgePadding: UIEdgeInsets(top: inset, left: inset, bottom: 200, right: inset))
    }

    private func displaySearchResult(stop: Stop) {
        mapView.addAnnotation(stop)
        mapView.setCenterCoordinate(centerCoordinate: stop.coordinate, zoomLevel: 18, animated: true)
        mapView.selectAnnotation(stop, animated: false)
    }

    // MARK: - Search/Route

    func loadSearchResponse(_ searchResponse: SearchResponse, route: Route) {
        guard let apiService = application.restAPIService else { return }

        let op = apiService.getStopsForRoute(id: route.id)
        op.complete { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .failure(let error):
                print("TODO FIXME handle error! \(error)")
            case .success(let response):
                let response = SearchResponse(response: searchResponse, substituteResult: response.entry)
                self.searchResponse = response
            }
        }
    }

    // MARK: - Stop Annotation Delegate

    func isStopBookmarked(_ stop: Stop) -> Bool {
        application.userDataStore.findBookmark(stopID: stop.id) != nil
    }

    var iconFactory: StopIconFactory {
        application.stopIconFactory
    }

    private let requiredHeightToShowExtraStopData = 7000.0

    var shouldHideExtraStopAnnotationData: Bool {
        mapView.visibleMapRect.height > requiredHeightToShowExtraStopData
    }

    // MARK: - Map View Delegate

    private func reloadStopAnnotations() {
        if searchResponseOverridesStopLoading() {
            return
        }

        updateZoomWarningOverlay(mapHeight: mapView.visibleMapRect.height)

        guard mapView.visibleMapRect.height <= MapRegionManager.requiredHeightToShowStops else {
            mapView.removeAnnotations(type: Stop.self)
            return
        }

        let visibleStops = mapView.annotations(in: mapView.visibleMapRect).filter(type: Stop.self)
        for s in visibleStops {
            if let stopView = mapView.view(for: s) as? StopAnnotationView {
                stopView.isHidingExtraStopAnnotationData = shouldHideExtraStopAnnotationData
            }
        }

        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: 0.25, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
    }

    private var isHidingRegions: Bool? {
        didSet {
            if oldValue != isHidingRegions {
                let val = isHidingRegions ?? true
                application.regionsService.regions
                    .compactMap { mapView.view(for: $0) }
                    .forEach { $0.isHidden = val }
            }
        }
    }

    private func reloadRegionAnnotations() {
        isHidingRegions = mapView.visibleMapRect.height <= MapRegionManager.requiredHeightToShowStops
    }

    public func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        lastVisibleMapRect = mapView.visibleMapRect

        reloadRegionAnnotations()
        reloadStopAnnotations()
    }

    public func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        mapViewDelegate?.mapView(mapView, didSelect: view)
    }

    public func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        mapViewDelegate?.mapView(mapView, didDeselect: view)
    }

    public func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl) {
        mapViewDelegate?.mapView(mapView, annotationView: view, calloutAccessoryControlTapped: control)
    }

    public func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let reuseIdentifier = reuseIdentifier(for: annotation) else {
            return nil
        }

        let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: reuseIdentifier, for: annotation)

        if self.userLocationAnnotationView == nil, let userLocation = annotationView as? PulsingAnnotationView {
            userLocation.headingImageView.isHidden = !mapViewShowsHeading
            self.userLocationAnnotationView = userLocation
        }

        if let stopAnnotation = annotationView as? StopAnnotationView {
            stopAnnotation.delegate = self
            mapViewDelegate?.mapRegionManager(self, customize: stopAnnotation)
        }

        return annotationView
    }

    private func reuseIdentifier(for annotation: MKAnnotation) -> String? {
        switch annotation {
        case is MKUserLocation: return MKMapView.reuseIdentifier(for: PulsingAnnotationView.self)
        case is Region: return MKMapView.reuseIdentifier(for: MKMarkerAnnotationView.self)
        case is Stop: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        default: return nil
        }
    }

    public func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if let overlay = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: overlay)
            renderer.strokeColor = ThemeColors.shared.brand.withAlphaComponent(0.75)
            renderer.lineWidth = 3.0
            renderer.lineCap = .round

            return renderer
        }

        fatalError() // :(
    }

    // MARK: - Regions

    public func regionsService(_ service: RegionsService, updatedRegionsList regions: [Region]) {
        renderRegionsOnMap()
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        mapView.setVisibleMapRect(region.serviceRect, animated: true)
    }

    private func renderRegionsOnMap() {
        mapView.updateAnnotations(with: application.regionsService.regions)
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
