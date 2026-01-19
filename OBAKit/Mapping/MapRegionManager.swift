//
//  MapRegionManager.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//
// swiftlint:disable file_length

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
    @objc optional func mapRegionManager(_ manager: MapRegionManager, didRemoveUserAnnotation annotation: UserDroppedPin)
    @objc optional func mapRegionManager(_ manager: MapRegionManager, didSelectUserAnnotation annotation: UserDroppedPin)

    @objc optional func mapRegionManagerDismissSearch(_ manager: MapRegionManager)

    @objc optional func mapRegionManagerDataLoadingStarted(_ manager: MapRegionManager)
    @objc optional func mapRegionManagerDataLoadingFinished(_ manager: MapRegionManager)

    @objc optional func mapRegionManagerShowZoomInStatus(_ manager: MapRegionManager, showStatus: Bool)
}

protocol MapRegionMapViewDelegate: NSObjectProtocol {
    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView)
    func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, calloutAccessoryControlTapped control: UIControl)
    func mapRegionManager(_ manager: MapRegionManager, customize stopAnnotationView: StopAnnotationView)
}

// MARK: - MapRegionManager

public class UserDroppedPin: MKPointAnnotation {}

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
        mapView.selectableMapFeatures = [.physicalFeatures, .pointsOfInterest]

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

        // Cancel all ongoing geocoding operations
        for geocoder in activeGeocoders.values {
            geocoder.cancelGeocode()
        }
        activeGeocoders.removeAll()

        // Clean up user pins
        userAnnotations.removeAll()
        userMapItems.removeAll()
    }

    // MARK: - Global Map Helpers

    public func registerAnnotationViews(mapView: MKMapView) {
        mapView.registerAnnotationView(MinimalStopAnnotationView.self)
        mapView.registerAnnotationView(MKMarkerAnnotationView.self)
        mapView.registerAnnotationView(StopAnnotationView.self)
        mapView.registerAnnotationView(PulsingAnnotationView.self)
        mapView.registerAnnotationView(PulsingVehicleAnnotationView.self)
        mapView.register(UserPinAnnotationView.self, forAnnotationViewWithReuseIdentifier: "UserDroppedPin")
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

    private func notifyDelegatesZoomInStatus(status: Bool) {
        for delegate in delegates.allObjects {
            delegate.mapRegionManagerShowZoomInStatus?(self, showStatus: status)
        }
    }

    private func notifyDelegatesUserAnnotationRemoved(_ annotation: UserDroppedPin) {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, didRemoveUserAnnotation: annotation)
        }
    }

    private func notifyDelegatesUserAnnotationSelected(_ annotation: UserDroppedPin) {
        for delegate in delegates.allObjects {
            delegate.mapRegionManager?(self, didSelectUserAnnotation: annotation)
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
        var bookmarksHash = [StopID: Bookmark]()
        for bm in bookmarks {
            bookmarksHash[bm.stopID] = bm
        }

        let existingAnnotations = mapView.annotations
        let existingBookmarkIDs = Set(existingAnnotations.compactMap { ($0 as? Bookmark)?.stopID })
        let existingStopIDs = Set(existingAnnotations.compactMap { ($0 as? Stop)?.id })
        var affectedStopIDs: Set<StopID> = []
        let stopAnnotationsToRemove = existingAnnotations.compactMap { annotation -> MKAnnotation? in
            guard
                let stop = annotation as? Stop,
                bookmarksHash[stop.id] != nil
            else {
                return nil
            }

            affectedStopIDs.insert(stop.id)
            return stop
        }
        let bookmarkAnnotationsToRemove = existingAnnotations.compactMap { annotation -> MKAnnotation? in
            guard
                let bookmark = annotation as? Bookmark,
                bookmarksHash[bookmark.stopID] == nil
            else {
                return nil
            }
            affectedStopIDs.insert(bookmark.stopID)
            return bookmark
        }
        let allAnnotationsToRemove = stopAnnotationsToRemove + bookmarkAnnotationsToRemove
        for annotation in allAnnotationsToRemove
            where mapView.selectedAnnotations.contains(where: { $0 === annotation }) {
            mapView.deselectAnnotation(annotation, animated: false)
        }
        mapView.removeAnnotations(allAnnotationsToRemove)

        let bookmarksToAdd = bookmarksHash.values.filter {
            !existingBookmarkIDs.contains($0.stopID)
        }
        mapView.addAnnotations(Array(bookmarksToAdd))

        let stopsToAdd = stops.filter {
            !bookmarksHash.keys.contains($0.id) &&
            !existingStopIDs.contains($0.id)
        }
        mapView.addAnnotations(stopsToAdd)
        refreshAnnotationViews(for: Array(affectedStopIDs))
        notifyDelegatesStopsChanged()
    }

    private func refreshAnnotationViews(for affectedStopIDs: [StopID]) {
        assert(Thread.isMainThread, "refreshAnnotationViews must be called on the main thread")
        for stopID in affectedStopIDs {
            let newAnnotation = mapView.annotations.first { annotation in
                if let bookmark = annotation as? Bookmark {
                    return bookmark.stopID == stopID
                } else if let stop = annotation as? Stop {
                    return stop.id == stopID
                }
                return false
            }
            guard let annotation = newAnnotation,
                  let view = mapView.view(for: annotation) as? StopAnnotationView else {
                continue
            }
            view.prepareForReuse()
            view.annotation = annotation
            view.delegate = self
            mapViewDelegate?.mapRegionManager(self, customize: view)
        }
    }
    // MARK: - Zoom In Warning

    private static let requiredHeightToShowStops = 40000.0

    public var zoomInStatus: Bool {
        mapView.visibleMapRect.height > MapRegionManager.requiredHeightToShowStops
    }

    private func updateZoomWarningOverlay(mapHeight: Double) {
        notifyDelegatesZoomInStatus(status: zoomInStatus)
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

        // Only add the annotation if it's not a user-dropped pin (to avoid duplicates)
        if findUserPin(for: mapItem) == nil {
            mapView.addAnnotation(mapItem.placemark)
        }

        // Clear searchResponse on next run loop to allow normal stop loading when panning
        DispatchQueue.main.async { [weak self] in
            self?.searchResponse = nil
        }
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

        // Clear searchResponse on next run loop to allow normal stop loading when panning
        // The annotation and callout remain visible even after searchResponse is cleared
        DispatchQueue.main.async { [weak self] in
            self?.searchResponse = nil
        }
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

    public func mapView(_ mapView: MKMapView, didSelect annotation: any MKAnnotation) {
        guard let feature = annotation as? MKMapFeatureAnnotation else { return }

        Task { [weak self] in
            await self?.handleMapFeatureSelection(feature)
        }
    }

    @MainActor
    private func handleMapFeatureSelection(_ feature: MKMapFeatureAnnotation) async {
        let request = MKMapItemRequest(mapFeatureAnnotation: feature)

        do {
            let mapItem = try await request.mapItem

            let searchRequest = SearchRequest(
                query: mapItem.name ?? "Dropped Pin",
                type: .address
            )
            let response = SearchResponse(
                request: searchRequest,
                results: [mapItem],
                boundingRegion: nil,
                error: nil
            )

            mapView.setCenter(mapItem.placemark.coordinate, animated: true)
            notifyDelegatesShowSearchResult(response: response)

        } catch {
            Logger.error("Failed to fetch map item: \(error)")

            // Fallback: create basic MKMapItem
            let placemark = MKPlacemark(coordinate: feature.coordinate)
            let mapItem = MKMapItem(placemark: placemark)
            mapItem.name = feature.title ?? "Dropped Pin"

            let searchRequest = SearchRequest(
                query: feature.title ?? "Dropped Pin",
                type: .address
            )
            let response = SearchResponse(
                request: searchRequest,
                results: [mapItem],
                boundingRegion: nil,
                error: nil
            )

            mapView.setCenter(mapItem.placemark.coordinate, animated: true)
            notifyDelegatesShowSearchResult(response: response)
        }
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

        if reuseIdentifier == "UserDroppedPin", let markerView = annotationView as? UserPinAnnotationView {
            markerView.animatesWhenAdded = true
            markerView.canShowCallout = false
            markerView.markerTintColor = ThemeColors.shared.brand

            if let userPin = annotation as? UserDroppedPin {
                markerView.onTap = { [weak self] in
                    self?.notifyDelegatesUserAnnotationSelected(userPin)
                }
            }
        }

        return annotationView
    }

    private func reuseIdentifier(for annotation: MKAnnotation) -> String? {
        switch annotation {
        case is Bookmark: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        case is MKUserLocation: return self.userLocationAnnotationReuseIdentifier
        case is Region: return MKMapView.reuseIdentifier(for: MKMarkerAnnotationView.self)
        case is Stop: return MKMapView.reuseIdentifier(for: StopAnnotationView.self)
        case is UserDroppedPin: return "UserDroppedPin"
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

    // MARK: - User-dropped pin
    // Made this public so can be accessed in MapViewController
    public private(set) var userAnnotations: [UserDroppedPin] = []
    // Dictionary mapping pin -> data
    private var userMapItems: [UserDroppedPin: MKMapItem] = [:]
    // Dictionary to track ongoing geocoding operations
    private var activeGeocoders: [UserDroppedPin: CLGeocoder] = [:]

    public func userPressedMap(_ gesture: UILongPressGestureRecognizer) {
        let touchPoint = gesture.location(in: mapView)
        let coordinate = mapView.convert(touchPoint, toCoordinateFrom: mapView)

        // Check if long-press is near an existing pin - if so, remove it.
        // This 44pt radius provides a larger touch target than the pin marker itself,
        // making it easier for users to remove pins without precise tapping.
        for pin in userAnnotations {
            let pinPoint = mapView.convert(pin.coordinate, toPointTo: mapView)
            let distance = hypot(touchPoint.x - pinPoint.x, touchPoint.y - pinPoint.y)

            if distance <= 44.0 {
                removeUserAnnotation(pin)
                return
            }
        }

        // Create new pin
        setUserAnnotation(coordinate: coordinate, title: nil, subtitle: nil)

        // Limit stored pins to prevent unbounded growth
        limitStoredPins(maxPins: 10)
    }

    // MARK: - User-dropped pin management

    /// Removes a specific user-dropped pin from the map and cleans up associated data
    public func removeUserAnnotation(_ annotation: UserDroppedPin) {
        // Notify delegates first (so UI can dismiss while data is still vaguely valid, though irrelevant)
        notifyDelegatesUserAnnotationRemoved(annotation)

        // Cancel any ongoing geocoding for this annotation
        if let geocoder = activeGeocoders[annotation] {
            geocoder.cancelGeocode()
            activeGeocoders.removeValue(forKey: annotation)
        }

        // Remove from data structures first
        userAnnotations.removeAll { $0 === annotation }
        userMapItems.removeValue(forKey: annotation)

        // Remove from map view last (visual removal)
        mapView.removeAnnotation(annotation)
    }

    /// Limits the number of stored pins to prevent unbounded growth
    /// - Parameter maxPins: Maximum number of pins to keep (default: 10)
    private func limitStoredPins(maxPins: Int = 10) {
        guard userAnnotations.count > maxPins else { return }

        // Remove oldest pins (first in array)
        let pinsToRemove = userAnnotations.prefix(userAnnotations.count - maxPins)

        for pin in pinsToRemove {
            // Cancel any ongoing geocoding
            if let geocoder = activeGeocoders[pin] {
                geocoder.cancelGeocode()
                activeGeocoders.removeValue(forKey: pin)
            }

            // Clean up data
            userMapItems.removeValue(forKey: pin)
            mapView.removeAnnotation(pin)
        }

        userAnnotations.removeFirst(userAnnotations.count - maxPins)
    }

    /// Finds a user-dropped pin for a given MKMapItem
    /// - Parameter mapItem: The map item to find the associated pin for
    /// - Returns: The pin associated with this map item, or nil
    public func findUserPin(for mapItem: MKMapItem) -> UserDroppedPin? {
        // First try to find by object identity
        if let pin = userMapItems.first(where: { $0.value === mapItem })?.key {
            return pin
        }

        // Fallback: find by coordinate matching
        let coord = mapItem.placemark.coordinate
        return userMapItems.first { (_, item) in
            let itemCoord = item.placemark.coordinate
            return abs(itemCoord.latitude - coord.latitude) < 0.0001 &&
                   abs(itemCoord.longitude - coord.longitude) < 0.0001
        }?.key
    }

    /// Entrypoint for displaying a user-driven search result on the map
    /// - Parameters:
    ///   - coordinate: The coordinate of the search result
    ///   - title: Optional title; it will be overwritten
    ///   - subtitle: Optional subtitle; it will be overwritten
    private func setUserAnnotation(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String?) {
        let annotation = UserDroppedPin()
        annotation.coordinate = coordinate
        annotation.title = title ?? "Dropped Pin"
        annotation.subtitle = subtitle ?? "Lat: \(coordinate.latitude), Lon: \(coordinate.longitude)"

        // Add to array
        self.userAnnotations.append(annotation)
        mapView.addAnnotation(annotation)

        reverseGeocodeLocation(coordinate: coordinate, annotation: annotation)
    }

    private func reverseGeocodeLocation(coordinate: CLLocationCoordinate2D, annotation: UserDroppedPin) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        // Use a local geocoder so multiple dropped pins can be reverse geocoded concurrently.
        let geocoder = CLGeocoder()

        // Track this geocoder so we can cancel it if needed
        activeGeocoders[annotation] = geocoder

        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, error in
            guard let self = self else { return }

            // Remove from active geocoders
            self.activeGeocoders.removeValue(forKey: annotation)

            // Verify this annotation still exists in our array (not removed)
            guard self.userAnnotations.contains(where: { $0 === annotation }) else {
                return
            }

            if let error = error {
                // Check if it was cancelled
                if (error as NSError).code == CLError.geocodeCanceled.rawValue {
                    return
                }
                Logger.error("Geocoding error: \(error.localizedDescription)")
                annotation.title = "Unknown Location"
                annotation.subtitle = "Could not retrieve location details"
                return
            }

            guard let placemark = placemarks?.first else {
                annotation.title = "Unknown Location"
                return
            }

            // Update annotation with location details
            self.updateAnnotation(annotation, with: placemark)

            // Create and Store MapItem
            let mapItem = MKMapItem(placemark: MKPlacemark(placemark: placemark))
            mapItem.name = annotation.title // Ensure the MapItem has the name we just generated

            // Store in Dictionary
            self.userMapItems[annotation] = mapItem

            // Trigger the initial "Open Sheet" behavior via SearchResponse
            // This mimics the "search" behavior to open the sheet immediately upon drop
            let query = annotation.title ?? "User Dropped Pin"
            let request = SearchRequest(query: query, type: .address)
            let response = SearchResponse(request: request, results: [mapItem], boundingRegion: nil, error: nil)
            self.searchResponse = response

            // Clear searchResponse on next run loop to allow normal stop loading when panning
            DispatchQueue.main.async { [weak self] in
                self?.searchResponse = nil
            }
        }
    }

    // Helper to retrieve item
    public func mapItem(for annotation: UserDroppedPin) -> MKMapItem? {
        return userMapItems[annotation]
    }

    private func updateAnnotation(_ annotation: UserDroppedPin, with placemark: CLPlacemark) {
        // Build the title from available components
        var titleComponents: [String] = []

        if let name = placemark.name {
            titleComponents.append(name)
        } else if let thoroughfare = placemark.thoroughfare {
            titleComponents.append(thoroughfare)
        } else if let locality = placemark.locality {
            titleComponents.append(locality)
        }

        // Build the subtitle
        var subtitleComponents: [String] = []

        if let locality = placemark.locality {
            subtitleComponents.append(locality)
        }
        if let administrativeArea = placemark.administrativeArea {
            subtitleComponents.append(administrativeArea)
        }
        if let country = placemark.country {
            subtitleComponents.append(country)
        }

        // Set the annotation text
        annotation.title = titleComponents.isEmpty ? "Unknown Location" : titleComponents.joined(separator: ", ")
        annotation.subtitle = subtitleComponents.joined(separator: ", ")
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

// swiftlint:enable file_length
