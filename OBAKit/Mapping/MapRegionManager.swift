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

public class UserDroppedPin: MKPointAnnotation {
    // Matches the isolation of the nonisolated MKPointAnnotation initializer it overrides.
    nonisolated override public init() {
        super.init()
    }
}

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

    /// Debounced request task for SwiftUI hosts driving `scheduleStopsRequest(in:)`.
    private var pendingStopsRequestTask: Task<Void, Never>?

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

    isolated deinit {
        mapView.delegate = nil
        mapView.removeAllAnnotations()
        delegates.removeAllObjects()
        application.locationService.removeDelegate(self)
        application.regionsService.removeDelegate(self)
        regionChangeRequestTimer?.invalidate()
        pendingStopsRequestTask?.cancel()

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
        mapView.registerAnnotationView(RentalAnnotationView.self)
        mapView.registerAnnotationView(RentalClusterAnnotationView.self)
        mapView.registerAnnotationView(BackgroundDotAnnotationView.self)
        mapView.register(UserPinAnnotationView.self, forAnnotationViewWithReuseIdentifier: "UserDroppedPin")
    }

    // MARK: - Background De-emphasis

    /// The stop whose sheet currently occupies the map, or nil when no sheet is up.
    ///
    /// While it is set, every *other* stop, bookmark, and rental marker collapses
    /// into a subtle gray dot that doesn't answer taps, so the selected stop's
    /// route lines and vehicles read against a network that is still legible as
    /// *position* but no longer competes with them. Set by `MapViewController`
    /// when it presents and dismisses the sheet.
    public var stopSheetSelection: StopID? {
        didSet {
            guard oldValue != stopSheetSelection else { return }
            refreshBackgroundAnnotationEmphasis()
        }
    }

    /// Whether `annotation` renders as a background dot right now.
    ///
    /// Stops and bookmarks are the manager's own; everything else answers through
    /// the layer that draws it. The route-focus layer declines, so its vehicles
    /// keep their full markers — they are what the sheet came up to show.
    private func recedesBehindStopSheet(_ annotation: MKAnnotation) -> Bool {
        guard let stopSheetSelection else { return false }
        // The sheet's own stop keeps its pin: it is the anchor that everything
        // else on screen — the route lines, the vehicles, the sheet — describes.
        if let stop = annotation as? Stop, stop.id == stopSheetSelection { return false }
        if let bookmark = annotation as? Bookmark, bookmark.stopID == stopSheetSelection { return false }
        return participatesInBackgroundEmphasis(annotation)
    }

    /// A type test, deliberately blind to the current selection: a swap from one
    /// stop's sheet to another has to refresh both the stop that stopped being
    /// selected and the one that started.
    private func participatesInBackgroundEmphasis(_ annotation: MKAnnotation) -> Bool {
        if annotation is Stop || annotation is Bookmark { return true }
        return mapLayers.contains { $0.recedesBehindStopSheet(annotation) }
    }

    /// MapKit asks `viewFor` once, when an annotation is added, so changing the
    /// selection changes nothing for what is already on screen. Removing and
    /// re-adding the affected annotations is the supported way to force a fresh
    /// round trip.
    private func refreshBackgroundAnnotationEmphasis() {
        let affected = mapView.annotations.filter { participatesInBackgroundEmphasis($0) }
        guard !affected.isEmpty else { return }
        mapView.removeAnnotations(affected)
        mapView.addAnnotations(affected)
    }

    // MARK: - Map Layers

    /// Registered toggleable data layers, in Map sheet order.
    public private(set) var mapLayers: [MapLayer] = []

    /// The UserDefaults key persisting a layer's on/off state.
    public static func mapLayerDefaultsKey(id: String) -> String {
        "mapLayer.\(id).enabled"
    }

    /// Registers a layer, registers its persistence default, and activates it when
    /// its persisted state says on. Layers appear in the Map sheet in registration
    /// order within their group.
    public func registerMapLayer(_ layer: MapLayer) {
        guard !mapLayers.contains(where: { $0.id == layer.id }) else { return }

        application.userDefaults.register(defaults: [
            Self.mapLayerDefaultsKey(id: layer.id): layer.isEnabledByDefault
        ])
        mapLayers.append(layer)

        if isMapLayerEnabled(id: layer.id) {
            layer.activate()
            forwardViewport(to: layer)
        }
    }

    /// Deactivates and removes a layer (e.g. when the region changes to one that
    /// doesn't support it). The persisted preference is kept.
    public func removeMapLayer(id: String) {
        guard let index = mapLayers.firstIndex(where: { $0.id == id }) else { return }
        let layer = mapLayers.remove(at: index)
        if isMapLayerEnabled(id: id) {
            layer.deactivate()
        }
    }

    public func mapLayer(id: String) -> MapLayer? {
        mapLayers.first { $0.id == id }
    }

    public func isMapLayerEnabled(id: String) -> Bool {
        application.userDefaults.bool(forKey: Self.mapLayerDefaultsKey(id: id))
    }

    public func setMapLayerEnabled(_ enabled: Bool, id: String) {
        guard isMapLayerEnabled(id: id) != enabled else { return }
        application.userDefaults.set(enabled, forKey: Self.mapLayerDefaultsKey(id: id))

        if let layer = mapLayer(id: id) {
            if enabled {
                layer.activate()
                forwardViewport(to: layer)
            } else {
                layer.deactivate()
            }
        }

        NotificationCenter.default.post(name: .mapLayerEnabledStateDidChange, object: id)
        application.analytics?.reportEvent(
            pageURL: "app://localhost/map",
            label: AnalyticsLabels.mapLayerToggled,
            value: "\(id):\(enabled ? "on" : "off")"
        )
    }

    /// The UserDefaults key persisting the shared rental minimum-range threshold.
    static let rentalMinimumRangeDefaultsKey = "mapLayer.rentals.minimumRangeMeters"

    /// The minimum-range filter shared by the Bikes and Scooters layers — one
    /// threshold, not one per layer.
    ///
    /// It lives here beside the per-layer enablement so `mapLayersDifferFromDefaults`
    /// and `resetMapLayersToDefaults()` cover it, which is what makes the Map
    /// sheet's Reset button honest. No `register(defaults:)` is needed: an unset
    /// key reads as 0, which is exactly `.any`.
    var rentalRangeFilter: RentalRangeFilter {
        get {
            RentalRangeFilter(
                minimumRangeMeters: application.userDefaults.integer(forKey: Self.rentalMinimumRangeDefaultsKey)
            )
        }
        set {
            guard rentalRangeFilter != newValue else { return }
            application.userDefaults.set(newValue.minimumRangeMeters, forKey: Self.rentalMinimumRangeDefaultsKey)

            NotificationCenter.default.post(name: .rentalRangeFilterDidChange, object: nil)
            application.analytics?.reportEvent(
                pageURL: "app://localhost/map",
                label: AnalyticsLabels.rentalRangeFilterChanged,
                value: String(newValue.minimumRangeMeters)
            )
        }
    }

    /// The number of enabled, non-hidden layers — the basemap button's badge.
    public var enabledMapLayerCount: Int {
        mapLayers.filter { $0.availability != .unsupported && isMapLayerEnabled(id: $0.id) }.count
    }

    /// True when any layer's on/off state differs from its default, or the rental
    /// range filter is active *and visible* — drives the Map sheet's Reset
    /// affordance. The filter row only renders when a `.otherModes` layer is
    /// registered (rental layers are region-gated), so a non-zero filter left over
    /// from another region must not offer a Reset that changes nothing on screen.
    public var mapLayersDifferFromDefaults: Bool {
        if rentalRangeFilter != .any, mapLayers.contains(where: { $0.group == .otherModes }) { return true }
        return mapLayers.contains { isMapLayerEnabled(id: $0.id) != $0.isEnabledByDefault }
    }

    /// Restores every registered layer to its default on/off state, and clears the
    /// rental range filter.
    public func resetMapLayersToDefaults() {
        for layer in mapLayers {
            setMapLayerEnabled(layer.isEnabledByDefault, id: layer.id)
        }
        rentalRangeFilter = .any
    }

    /// Whether stop annotations should render. True when no stops layer is
    /// registered — the layer row is additive; its absence must not hide stops.
    var isStopsLayerEnabled: Bool {
        guard mapLayer(id: StopsMapLayer.layerID) != nil else { return true }
        return isMapLayerEnabled(id: StopsMapLayer.layerID)
    }

    /// Called by `StopsMapLayer` when its toggle flips; re-renders stop annotations.
    func stopsLayerVisibilityDidChange() {
        if isStopsLayerEnabled {
            displayUniqueStopAnnotations()
        } else {
            removeStopAnnotationsPreservingSelection()
        }
    }

    /// Removes stop annotations for the layer toggle, but never a stop the rider is
    /// actively looking at: a searched or selected stop is explicit user intent and
    /// outranks the browse-layer preference (bookmarks get the same exemption).
    private func removeStopAnnotationsPreservingSelection() {
        let selectedStopIDs = Set(mapView.selectedAnnotations.compactMap { ($0 as? Stop)?.id })
        let stopsToRemove = mapView.annotations.compactMap { $0 as? Stop }.filter { !selectedStopIDs.contains($0.id) }
        mapView.removeAnnotations(stopsToRemove)
    }

    /// Feeds the current viewport to a layer, applying its zoom window: outside
    /// the window the layer receives nil and removes its annotations.
    private func forwardViewport(to layer: MapLayer) {
        let visibleRect = mapView.visibleMapRect
        let insideWindow = layer.zoomWindow.contains(visibleHeight: visibleRect.height)
        layer.viewportDidChange(insideWindow ? visibleRect : nil)
    }

    private func updateMapLayers() {
        for layer in mapLayers where isMapLayerEnabled(id: layer.id) {
            forwardViewport(to: layer)
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

    public private(set) var stops = [Stop]()

    /// UIKit publish: stores stops and diffs the manager's own `mapView`.
    private func setStops(_ newStops: [Stop]) {
        stops = newStops
        displayUniqueStopAnnotations()
    }

    /// SwiftUI publish: stores stops and notifies delegates, skipping the
    /// offscreen `mapView` diff SwiftUI hosts don't need.
    private func publishStopsToDelegates(_ newStops: [Stop]) {
        stops = newStops
        notifyDelegatesStopsChanged()
    }

    private func displayUniqueStopAnnotations() {
        // When multiple bookmarks exist for the same stop, the last one in the bookmarks array takes precedence
        let bookmarksHash = bookmarks.dedupedByStopID()

        let existingAnnotations = mapView.annotations
        let existingStopIDs = Set(existingAnnotations.compactMap { ($0 as? Stop)?.id })
        var affectedStopIDs: Set<StopID> = []

        // Remove Stop annotations that now have a corresponding Bookmark
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

        // Remove Bookmark annotations that are stale:
        //   - The bookmark's stop no longer has ANY bookmark (deleted), OR
        //   - The bookmark on the map is a different object than the current one (replaced)
        let bookmarkAnnotationsToRemove = existingAnnotations.compactMap { annotation -> MKAnnotation? in
            guard let bookmark = annotation as? Bookmark else {
                return nil
            }

            guard let currentBookmark = bookmarksHash[bookmark.stopID] else {
                // No bookmark exists for this stop anymore, remove the stale annotation
                affectedStopIDs.insert(bookmark.stopID)
                return bookmark
            }

            // If a different bookmark now represents this stop, remove the old one
            if currentBookmark.id != bookmark.id {
                affectedStopIDs.insert(bookmark.stopID)
                return bookmark
            }

            return nil
        }

        let allAnnotationsToRemove = stopAnnotationsToRemove + bookmarkAnnotationsToRemove
        for annotation in allAnnotationsToRemove {
            guard mapView.selectedAnnotations.contains(where: { $0 === annotation }) else { continue }
            mapView.deselectAnnotation(annotation, animated: false)
        }
        mapView.removeAnnotations(allAnnotationsToRemove)

        // Add new Bookmark annotations that aren't already on the map
        // Check by bookmark ID (not just stopID) to correctly add replacements
        let existingBookmarkIDs = Set(mapView.annotations.compactMap { ($0 as? Bookmark)?.id })
        let bookmarksToAdd = bookmarksHash.values.filter {
            !existingBookmarkIDs.contains($0.id)
        }
        mapView.addAnnotations(Array(bookmarksToAdd))

        // Re-add Stop annotations for stops that no longer have bookmarks.
        // With the stops layer toggled off, nothing is added — bookmarks are
        // user content and stay visible regardless.
        let stopsToAdd = isStopsLayerEnabled ? stops.filter {
            !bookmarksHash.keys.contains($0.id) &&
            !existingStopIDs.contains($0.id)
        } : []
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

    /// Above this visible-map-rect height (in map points), the map is considered
    /// too zoomed-out to load or display stops. Both the UIKit region-change path
    /// and SwiftUI hosts (via `MapPanelRootView`) gate stop loading on this value
    /// so the two surfaces agree on when stops appear.
    static let requiredHeightToShowStops = 40000.0

    /// How long a camera settle is coalesced before stops are fetched. Shared by
    /// the UIKit `regionChangeRequestTimer` and the SwiftUI `scheduleStopsRequest`
    /// debounce so retuning one surface can't silently leave the other behind.
    static let stopsRequestDebounceInterval: TimeInterval = 0.25

    /// Whether the zoom-in-for-stops warning should show for a map whose
    /// visible `MKMapRect` is `height` map points tall. Exposed so the SwiftUI
    /// `MapPanelRootView` drives its status pill from the same threshold the
    /// UIKit map uses, keeping the two surfaces in agreement.
    public static func shouldShowZoomInWarning(forVisibleMapRectHeight height: Double) -> Bool {
        height > requiredHeightToShowStops
    }

    public var zoomInStatus: Bool {
        MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: mapView.visibleMapRect.height)
    }

    private func updateZoomWarningOverlay() {
        notifyDelegatesZoomInStatus(status: zoomInStatus)
    }

    // MARK: - Search

    public func cancelSearch() {
        searchResponse = nil
        mapView.removeAllAnnotations()
        mapView.removeOverlays(mapView.overlays)
        reloadStopAnnotations()
        notifyMapLayersAnnotationsCleared()
        notifyMapLayersOverlaysCleared()
    }

    /// `removeAllAnnotations` strips layer annotations behind the layers' backs;
    /// tell them so their bookkeeping and the map agree again.
    private func notifyMapLayersAnnotationsCleared() {
        for layer in mapLayers where isMapLayerEnabled(id: layer.id) {
            layer.mapAnnotationsWereCleared()
        }
    }

    /// Wholesale overlay removal strips layer overlays behind the layers' backs;
    /// tell each enabled layer so it can re-add its own. Mirrors
    /// `notifyMapLayersAnnotationsCleared()`.
    private func notifyMapLayersOverlaysCleared() {
        for layer in mapLayers where isMapLayerEnabled(id: layer.id) {
            layer.mapOverlaysWereCleared()
        }
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
        notifyMapLayersAnnotationsCleared()

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

    /// The redesigned Stop page opens as a sheet directly over the map, so the callout's
    /// preview-then-chevron detour costs a tap and buys nothing. The legacy Stop page pushes onto
    /// the navigation stack, replacing the map wholesale, and keeps the callout as its preview.
    var showsStopAnnotationCallouts: Bool {
        !FeatureFlags.isNewStopPageEnabled(userDefaults: application.userDefaults)
    }

    /// Re-asks every stop annotation currently on the map whether it should show a callout.
    ///
    /// `canShowCallout` is computed once, when `viewFor` attaches the delegate, but
    /// `showsStopAnnotationCallouts` reads a feature flag the user can flip from Settings without
    /// relaunching. Everything else that opens a stop reads that flag live, so without this the
    /// annotations already on screen keep answering with the rule from launch: the legacy Stop
    /// page opens on the first tap with no callout in between.
    public func refreshStopAnnotationCallouts() {
        for annotation in mapView.annotations {
            (mapView.view(for: annotation) as? StopAnnotationView)?.updateCalloutVisibility()
        }
    }

    /// Above this visible-map-rect height (map points), stop pins are too
    /// zoomed-out for their under-pin label. Shared with `MapPanelRootView`.
    public static let requiredHeightToShowExtraStopData = 7000.0

    /// Height half of the under-pin label gate. Callers combine it with the
    /// standard-map-type and "show labels" default checks.
    public static func shouldShowExtraStopData(forVisibleMapRectHeight height: Double) -> Bool {
        height <= requiredHeightToShowExtraStopData
    }

    /// The full under-pin label gate (standard map + zoomed in + user default on),
    /// shared so every map surface gates labels identically.
    public static func shouldShowStopAnnotationLabels(
        forVisibleMapRectHeight height: Double,
        isStandardMapType: Bool,
        showLabelsDefault: Bool
    ) -> Bool {
        isStandardMapType
            && shouldShowExtraStopData(forVisibleMapRectHeight: height)
            && showLabelsDefault
    }

    var shouldHideExtraStopAnnotationData: Bool {
        // Everything but hybrid/satellite (incl. muted standard) is "standard".
        let isStandardMapType = !(mapView.mapType == .hybrid || mapView.mapType == .satellite)
        return !MapRegionManager.shouldShowStopAnnotationLabels(
            forVisibleMapRectHeight: mapView.visibleMapRect.height,
            isStandardMapType: isStandardMapType,
            showLabelsDefault: application.userDefaults.bool(forKey: MapRegionManager.mapViewShowsStopAnnotationLabelsDefaultsKey)
        )
    }

    // MARK: - Map View Delegate

    private func reloadStopAnnotations() {
        // Ahead of every early return below, including the search-result guard.
        // The pill states something about the current zoom, so it has to be
        // re-derived on every settle — and a route search suppresses stop
        // reloading without ever clearing `searchResponse` on its own, so a
        // warning updated after that guard freezes until the search is
        // cancelled. Mirrors the ordering `MapPanelRootView.onMapCameraChange`
        // already uses.
        updateZoomWarningOverlay()

        if searchResponseOverridesStopLoading() {
            return
        }

        // The zoom gate applies regardless of the layer toggle: `getStops` with a
        // region-scale bounding box is exactly what the 40,000-height gate prevents.
        guard mapView.visibleMapRect.height <= MapRegionManager.requiredHeightToShowStops else {
            mapView.removeAnnotations(type: Stop.self)
            return
        }

        guard isStopsLayerEnabled else {
            removeStopAnnotationsPreservingSelection()
            // Data still loads even when annotations are hidden: other surfaces
            // (like the nearby stops list) read `stops` directly.
            regionChangeRequestTimer?.invalidate()
            regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: Self.stopsRequestDebounceInterval, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
            return
        }

        let visibleStops = mapView.annotations(in: mapView.visibleMapRect).filter(type: Stop.self)
        for s in visibleStops {
            if let stopView = mapView.view(for: s) as? StopAnnotationView {
                stopView.isHidingExtraStopAnnotationData = shouldHideExtraStopAnnotationData
            }
        }

        regionChangeRequestTimer?.invalidate()

        regionChangeRequestTimer = Timer.scheduledTimer(timeInterval: Self.stopsRequestDebounceInterval, target: self, selector: #selector(requestDataForMapRegion(_:)), userInfo: nil, repeats: false)
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
        updateMapLayers()
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
            // MKMapItemRequest and MKMapItem aren't Sendable, and Swift 6.2
            // (CI's toolchain) won't let them cross the main-actor boundary
            // around the nonisolated async `mapItem` accessor. Run the fetch in
            // a detached task, handing each value across in a box: the request
            // is one-shot and the fetched item has no other owner until the
            // transfer completes.
            let requestBox = UncheckedSendableBox(value: request)
            let mapItem = try await Task.detached {
                UncheckedSendableBox(value: try await requestBox.value.mapItem)
            }.value.value

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
        // Ahead of the layer loop: while a stop sheet is up, a receding annotation
        // gets the shared dot instead of the view its owner would have built.
        if recedesBehindStopSheet(annotation) {
            return mapView.dequeueReusableAnnotationView(
                withIdentifier: MKMapView.reuseIdentifier(for: BackgroundDotAnnotationView.self),
                for: annotation
            )
        }

        // Registered layers get first claim on their own annotation (and cluster)
        // types; everything else falls through to the built-in annotation types.
        for layer in mapLayers {
            if let layerView = layer.annotationView(for: annotation, in: mapView) {
                return layerView
            }
        }

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
        // Layers get first claim, mirroring `viewFor annotation`. This loop MUST
        // precede the `as? MKPolyline` branch below: a layer's overlay can be an
        // `MKPolyline` subclass, which that branch would otherwise claim and paint
        // as a generic 3pt brand-colored stroke.
        //
        // Deliberately unfiltered by enablement, exactly like the annotation path:
        // `deactivate()` is what removes a layer's overlays. Gating here on the
        // UserDefaults flag would leave a stale overlay falling through to the
        // generic branch instead of its own renderer.
        for layer in mapLayers {
            if let layerRenderer = layer.renderer(for: overlay, in: mapView) {
                return layerRenderer
            }
        }

        if let overlay = overlay as? MKPolyline {
            let renderer = MKPolylineRenderer(polyline: overlay)
            renderer.strokeColor = ThemeColors.shared.brand.withAlphaComponent(0.75)
            renderer.lineWidth = 3.0
            renderer.lineCap = .round

            return renderer
        }

        // Previously `fatalError()`. An unexpected overlay type is not worth
        // aborting a transit app over — log it and draw nothing.
        Logger.error("No renderer for overlay of type \(type(of: overlay)); drawing nothing.")
        return MKOverlayRenderer(overlay: overlay)
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
            // CLGeocoder invokes its completion handler on the main thread.
            MainActor.assumeIsolated {
                self?.handleGeocodeResult(annotation: annotation, placemarks: placemarks, error: error)
            }
        }
    }

    private func handleGeocodeResult(annotation: UserDroppedPin, placemarks: [CLPlacemark]?, error: Error?) {
        // Remove from active geocoders
        activeGeocoders.removeValue(forKey: annotation)

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

// MARK: - Data Loading

/// Stop fetching, caching, and publishing — the shared engine behind both the
/// UIKit region-change path and the SwiftUI map panel's debounced settles.
/// Split into an extension so the two surfaces' loading code reads as one
/// unit rather than a slab in the middle of the UIKit map-view plumbing.
extension MapRegionManager {

    /// Loads stops for an explicitly provided region and stores them in `stops`.
    ///
    /// Takes the region as a parameter rather than reading `mapView.region`, so
    /// callers that don't own this manager's `mapView` can drive it. Publishing
    /// goes through `setStops(_:)`, which diffs this manager's own `mapView`
    /// annotations — SwiftUI hosts want `scheduleStopsRequest(in:)` instead,
    /// which debounces, serves the cache first, and skips that diff.
    ///
    /// Applies the same fudge factor, cache-save, and cache-fallback behavior as
    /// the UIKit region-change path.
    func requestStops(in region: MKCoordinateRegion) async {
        let mapRegion = fudgedRegion(for: region, factor: preferredLoadDataRegionFudgeFactor)

        do {
            guard let stops = try await fetchStops(in: region) else { return }

            await MainActor.run {
                // Some UI code is dependent on this being changed on Main.
                self.setStops(stops)
            }

            // Published before caching, so the pins aren't waiting on a SQLite write.
            saveStopsToCache(stops)
        } catch {
            // A cancelled request isn't a failure. It arrives in more than one
            // shape — Swift's `CancellationError`, or a URLSession
            // `NSError`/`URLError` carrying `NSURLErrorCancelled` — so match
            // `scheduleStopsRequest` and check both rather than a typed catch.
            // Otherwise panning quickly across uncached area pops an error
            // bulletin for a request the user themselves superseded.
            if Task.isCancelled || error.isCancellation { return }

            Logger.error("API stop request failed, attempting cache fallback: \(error)")

            // On API failure, try serving from cache before showing error.
            let cachedStops = cachedStops(in: mapRegion)
            if !cachedStops.isEmpty {
                await MainActor.run {
                    self.setStops(cachedStops)
                }
                return
            }
            await self.application.displayError(error)
        }
    }

    /// Reads cached stops for `mapRegion` (already fudge-factor expanded) from
    /// `StopCacheRepository`, using a bounding-box query. Returns `[]` when the
    /// repository or current region is unavailable, or nothing is cached.
    ///
    /// See: https://github.com/OneBusAway/onebusaway-ios/issues/62
    private func cachedStops(in mapRegion: MKCoordinateRegion) -> [Stop] {
        guard
            let regionId = application.currentRegion?.regionIdentifier,
            let repository = application.stopCacheRepository
        else {
            return []
        }

        let minLat = mapRegion.center.latitude - mapRegion.span.latitudeDelta / 2.0
        let maxLat = mapRegion.center.latitude + mapRegion.span.latitudeDelta / 2.0
        let minLon = mapRegion.center.longitude - mapRegion.span.longitudeDelta / 2.0
        let maxLon = mapRegion.center.longitude + mapRegion.span.longitudeDelta / 2.0

        return repository.stopsInRegion(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon,
            regionId: regionId
        )
    }

    /// Persists `stops` to `StopCacheRepository` for offline use.
    /// See: https://github.com/OneBusAway/onebusaway-ios/issues/62
    private func saveStopsToCache(_ stops: [Stop]) {
        if let regionId = application.currentRegion?.regionIdentifier,
           let repository = application.stopCacheRepository {
            repository.saveStops(stops, regionId: regionId)
        }
    }

    /// Fetches stops, caches them, and returns the set so callers can publish it
    /// directly when the cache can't (e.g. the database failed to open). Returns
    /// `nil` when no API service is configured; rethrows network errors.
    private func refreshStopCache(in region: MKCoordinateRegion) async throws -> [Stop]? {
        guard let stops = try await fetchStops(in: region) else { return nil }
        saveStopsToCache(stops)
        return stops
    }

    /// Fetches stops for `region`, applying the shared fudge factor and bracketing
    /// the call with the loading-started/finished delegate notifications.
    ///
    /// Neither caches nor publishes: `requestStops` publishes before writing to
    /// SQLite so its pins don't wait on the write, while `refreshStopCache`
    /// caches first and republishes from the cache band. Keeping that choice with
    /// the callers is the only reason this is separate from `refreshStopCache`.
    ///
    /// Returns `nil` when no API service is configured — callers must be able to
    /// tell "nothing was attempted" from "the fetch succeeded and this region
    /// genuinely has no stops", because only the latter should be published.
    private func fetchStops(in region: MKCoordinateRegion) async throws -> [Stop]? {
        guard let apiService = application.apiService else { return nil }

        await MainActor.run {
            notifyDelegatesDataLoadingStarted()
        }
        defer {
            Task { @MainActor in
                notifyDelegatesDataLoadingFinished()
            }
        }

        let mapRegion = fudgedRegion(for: region, factor: preferredLoadDataRegionFudgeFactor)
        return try await apiService.getStops(region: mapRegion).list
    }

    /// Applies the network fudge-factor expansion to `region`, so the cache
    /// read covers the same bounds the network fetches and saves.
    private func fudgedRegion(for region: MKCoordinateRegion, factor: Double) -> MKCoordinateRegion {
        var mapRegion = region
        mapRegion.span.latitudeDelta *= factor
        mapRegion.span.longitudeDelta *= factor
        return mapRegion
    }

    /// Publishes cached stops for `region` immediately (instant revisits),
    /// publishing only the latest region — neighborhood persistence lives in
    /// `MapStopsObserver`. Returns `true` if it published a non-empty set; a
    /// cache miss or cancelled task is a no-op that returns `false`.
    @discardableResult
    private func serveCachedStops(in region: MKCoordinateRegion) async -> Bool {
        // Bail before the SQLite bounding-box query when the task is already
        // cancelled — a settle superseded by a newer one shouldn't pay for a
        // GRDB read whose result would be thrown away.
        guard !Task.isCancelled else { return false }
        let cachedStops = cachedStops(in: fudgedRegion(for: region, factor: preferredLoadDataRegionFudgeFactor))
        guard !cachedStops.isEmpty, !Task.isCancelled else { return false }

        await MainActor.run {
            self.publishStopsToDelegates(cachedStops)
        }
        return true
    }

    /// UIKit entrypoint: loads stops for the manager's own `mapView` region.
    func requestDataForMapRegion() async {
        await requestStops(in: mapView.region)
    }

    @objc func requestDataForMapRegion(_ timer: Timer) {
        Task(priority: .utility) {
            await requestDataForMapRegion()
        }
    }

    /// Debounced, fire-and-forget entrypoint for SwiftUI hosts. Coalesces rapid
    /// camera settles (on the shared `stopsRequestDebounceInterval`, same as the
    /// UIKit timer) and cancels any in-flight request before loading stops for
    /// `region`.
    func scheduleStopsRequest(in region: MKCoordinateRegion) {
        // Mirror the guard at the top of the UIKit `reloadStopAnnotations`
        // path: while a single search result is displayed, region stop-loading
        // is suppressed so the search result isn't overwritten by a camera
        // settle.
        //
        // Cancel rather than merely declining to schedule: a settle from just
        // before the search may still be sitting in its debounce, and letting
        // it land would publish the panned region's stops over the search
        // result — the exact outcome this guard exists to prevent.
        if searchResponseOverridesStopLoading() {
            cancelScheduledStopsRequest()
            return
        }

        pendingStopsRequestTask?.cancel()
        pendingStopsRequestTask = Task { [weak self] in
            guard let self else { return }

            // Publish the band around this region immediately (before the
            // debounce), so a settle over a recently-viewed area shows pins
            // without waiting on the network.
            let servedFromCache = await self.serveCachedStops(in: region)

            try? await Task.sleep(for: .seconds(Self.stopsRequestDebounceInterval))
            guard !Task.isCancelled else { return }

            do {
                // Refresh the cache, but don't publish the raw response —
                // publishing the narrower network region between two band
                // publishes flickers the band's outer pins.
                // `nil` means no API service, so nothing was fetched and there is
                // nothing to publish — bail rather than blanking a band that
                // already has pins. An *empty* result is different: the fetch
                // succeeded and this region really has no stops, so it must be
                // published so `stops` stops describing the region we left.
                guard let fetched = try await self.refreshStopCache(in: region) else { return }
                guard !Task.isCancelled else { return }

                if self.application.stopCacheRepository == nil {
                    // No cache to round-trip through, so publish directly —
                    // otherwise the map would show no pins at all.
                    await MainActor.run { self.publishStopsToDelegates(fetched) }
                } else {
                    // Re-serve the band with the fresh stops: band → band, a
                    // clean incremental add, never band → narrow → band.
                    let republished = await self.serveCachedStops(in: region)

                    // Cache reads can be empty after a successful fetch (e.g. cache write
                    // failure or missing cache key). Fall back to the fetched stops so the
                    // map isn't left blank, unless the request was cancelled by a newer one.
                    if !republished, !Task.isCancelled {
                        await MainActor.run { self.publishStopsToDelegates(fetched) }
                    }
                }
            } catch {
                // A cancelled request isn't a failure — it's the expected
                // outcome of a newer camera settle superseding this one, and it
                // arrives in several shapes (Swift `CancellationError`, or a
                // URLSession `NSError`/`URLError` with `NSURLErrorCancelled`),
                // so lean on `Error.isCancellation` plus `Task.isCancelled`
                // rather than a typed catch. Surfacing it would pop a modal
                // error bulletin every time the user pans across an uncached
                // area twice in quick succession.
                if Task.isCancelled || error.isCancellation {
                    return
                }
                Logger.error("Map panel stop refresh failed: \(error)")
                // Surface the error only when nothing is on-screen.
                if !servedFromCache {
                    await self.application.displayError(error)
                }
            }
        }
    }

    /// Cancels any stops request scheduled via `scheduleStopsRequest(in:)` that
    /// hasn't fired yet. Called by SwiftUI hosts when the camera settles zoomed
    /// out past `requiredHeightToShowStops`, so a request debounced while zoomed
    /// in doesn't land after the host has cleared its annotations.
    func cancelScheduledStopsRequest() {
        pendingStopsRequestTask?.cancel()
        pendingStopsRequestTask = nil
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
