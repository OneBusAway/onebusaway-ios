//
//  MapRegionManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
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

    public static let DefaultLoadDataRegionFudgeFactor: Double = 1.1

    /// The 'fudge factor' around the current size of the map's
    /// visible region when loading map data. This will mean that we load some
    /// stops that are just outside of the visible bounds of the screen, which mean
    /// that stops should (fingers crossed) seem to load instantly.
    ///
    /// The number of stops loaded is still limited by the server, see `RESTAPIService.getStops` for details.
    /// Note, that this is a `preferred` value. `MapRegionManager` may or may not respect this value.
    /// The default value may be accessed as a constant, `MapRegionManager.DefaultLoadDataRegionFudgeFactor`.
    ///
    /// By default, this value is set to `1.1x`, but should be adjusted depending on user context, such as:
    /// - If no stops were loaded within the given region, you could set this value to something higher and attempt to load data again.
    /// - In low-density geographic regions, you may want to set this value higher in order to display a full list of stops.
    /// - When VoiceOver is enabled, it can be reasonably assumed that the user won't be visually overloaded with
    /// the map being full of annotations, therefore loading more stops is encouraged.
    public var preferredLoadDataRegionFudgeFactor: Double = MapRegionManager.DefaultLoadDataRegionFudgeFactor

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
        mapView.isRotateEnabled = false

        return mapView
    }()

    // MARK: - User Defaults

    /// This user defaults key points to a value that indicates whether stop annotation views should
    /// show labels underneath them enumerating the routes served by that stop.
    public static let mapViewShowsStopAnnotationLabelsDefaultsKey = "mapRegionManager.mapViewShowsStopAnnotationLabels"

    /// Whether the map view displays current traffic conditions.
    ///
    /// `true` by default.
    public var mapViewShowsTraffic: Bool {
        get {
            // Disable traffic in the Simulator to work around a bug in Xcode 11 and 12
            // where the console spews hundreds of error messages that read:
            // "Compiler error: Invalid library file"
            //
            // https://stackoverflow.com/a/63176707
            #if targetEnvironment(simulator)
            return false
            #else
            return application.userDefaults.bool(forKey: mapViewShowsTrafficKey)
            #endif
        }
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
                Logger.error("Unable to decode last visible map rect: \(error)")
            }

            return lastRect
        }
        set {
            do {
                let encodedValue = try PropertyListEncoder().encode(newValue)
                application.userDefaults.set(encodedValue, forKey: lastVisibleMapRectKey)
            } catch let error {
                Logger.error("Unable to encode last visible map rect: \(error)")
            }
        }
    }
    private let lastVisibleMapRectKey = "mapRegionManager.lastVisibleMapRect"

    private let mapViewMapTypeKey = "mapRegionManager.selectedMapType"

    /// Changing this value will also update `mapView`.
    var userSelectedMapType: MKMapType {
        get {
            let rawMapType: Int = application.userDefaults.integer(forKey: mapViewMapTypeKey)
            return MKMapType(rawValue: UInt(rawMapType)) ?? .mutedStandard
        } set {
            application.userDefaults.set(newValue.rawValue, forKey: mapViewMapTypeKey)
            mapView.mapType = newValue
        }
    }

    // MARK: - Init

    public init(application: Application) {
        self.application = application

        application.userDefaults.register(defaults: [
            mapViewShowsTrafficKey: true,
            mapViewShowsScaleKey: true,
            mapViewShowsHeadingKey: true,
            mapViewMapTypeKey: MKMapType.mutedStandard.rawValue,
            MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey: true,
        ])

        super.init()

        application.locationService.addDelegate(self)
        application.regionsService.addDelegate(self)

        mapView.showsUserLocation = application.locationService.isLocationUseAuthorized
        mapView.showsScale = mapViewShowsScale
        mapView.showsTraffic = mapViewShowsTraffic
        mapView.mapType = userSelectedMapType

        registerAnnotationViews(mapView: mapView)

        mapView.delegate = self

        Task { @MainActor [weak self] in
            await self?.renderRegionsOnMap()
        }
    }

    deinit {
        mapView.delegate = nil
        mapView.removeAllAnnotations()
        delegates.removeAllObjects()
        application.locationService.removeDelegate(self)
        application.regionsService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
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

    func requestDataForMapRegion() async {
        guard let apiService = application.apiService else {
            return
        }

        await MainActor.run {
            notifyDelegatesDataLoadingStarted()
        }

        defer {
            Task { @MainActor in
                notifyDelegatesDataLoadingFinished()
            }
        }

        var mapRegion = mapView.region
        mapRegion.span.latitudeDelta *= preferredLoadDataRegionFudgeFactor
        mapRegion.span.longitudeDelta *= preferredLoadDataRegionFudgeFactor

        do {
            let stops = try await apiService.getStops(region: mapRegion).list

            await MainActor.run {
                // Some UI code is dependent on this being changed on Main.
                self.stops = stops
            }
        } catch {
            await self.application.displayError(error)
        }
    }

    @objc func requestDataForMapRegion(_ timer: Timer) {
        Task(priority: .utility) {
            await requestDataForMapRegion()
        }
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

    // MARK: - Setters

    public var bookmarks = [Bookmark]() {
        didSet {
            displayUniqueStopAnnotations()
        }
    }

    public private(set) var stops = [Stop]() {
        didSet {
            displayUniqueStopAnnotations()
        }
    }

    private func displayUniqueStopAnnotations() {
        mapView.removeAnnotations(type: Bookmark.self)
        var bookmarksHash = [StopID: Bookmark]()

        for bm in bookmarks {
            bookmarksHash[bm.stopID] = bm
        }

        mapView.addAnnotations(Array(bookmarksHash.values))

        let bookmarkStopIDs = Set(bookmarksHash.keys)
        let rejectedStops = stops.filter { bookmarkStopIDs.contains($0.id) }
        let acceptedStops = stops.filter { !rejectedStops.contains($0) }

        mapView.removeAnnotations(rejectedStops)
        mapView.addAnnotations(acceptedStops)

        notifyDelegatesStopsChanged()
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
                Logger.error("Unhandled search result object! \(result)")
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

    func _loadSearchResponse(_ searchResponse: SearchResponse, route: Route) async {
        guard let apiService = application.apiService else {
            return
        }

        do {
            let response = try await apiService.getStopsForRoute(routeID: route.id)
            await MainActor.run {
                self.searchResponse = SearchResponse(response: searchResponse, substituteResult: response.entry)
            }
        } catch {
            await self.application.displayError(error)
        }
    }

    func loadSearchResponse(_ searchResponse: SearchResponse, route: Route) {
        Task {
            await _loadSearchResponse(searchResponse, route: route)
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
        // only the standard map type shows extra data.
        if mapView.mapType == .hybrid || mapView.mapType == .satellite {
            return true
        }

        // only show the extra data below `requiredHeightToShowExtraStopData`
        if mapView.visibleMapRect.height > requiredHeightToShowExtraStopData {
            return true
        }

        // Finally, return the opposite of the appropriate user defaults value.
        // This user defaults key is written in affirmative language and negated
        // here because it's a lot easier for users to reason about a switch that
        // says "show a thing" [true] or [false] versus "hide a thing" [true] or [false]
        return !application.userDefaults.bool(forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey)
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
            userLocation.canShowCallout = true
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
        case is Bookmark: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        case is MKUserLocation: return self.userLocationAnnotationReuseIdentifier
        case is Region: return MKMapView.reuseIdentifier(for: MKMarkerAnnotationView.self)
        case is Stop: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        default: return nil
        }
    }

    // On iOS 14, use the default MKUserLocationView because it will display imprecise locations elegantly.
    private var userLocationAnnotationReuseIdentifier: String? {
        // Use the default MKUserLocationView when the user has only authorized imprecise location access.
        if application.locationService.accuracyAuthorization == .reducedAccuracy {
            return nil
        }
        else {
            return MKMapView.reuseIdentifier(for: PulsingAnnotationView.self)
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
        Task { @MainActor [weak self] in
            await self?.renderRegionsOnMap()
        }
    }

    public func regionsService(_ service: RegionsService, updatedRegion region: Region) {
        mapView.setVisibleMapRect(region.serviceRect, animated: true)
    }

    @MainActor
    private func renderRegionsOnMap() async {
        mapView.updateAnnotations(with: application.regionsService.regions)
    }
}

// MARK: - Location Service Delegate

extension MapRegionManager: LocationServiceDelegate {
    public func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        // "reset" this property to change the user location annotation view as needed.
        mapView.showsUserLocation = false
        mapView.showsUserLocation = service.isLocationUseAuthorized
    }

    public func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        // nop.
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
