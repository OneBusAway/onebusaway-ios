//
//  MapRegionManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore
import Testing

// swiftlintXdisable force_try

@Suite(.serialized)
final class MapRegionManagerTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    private var regionsFilePath: String { Bundle.main.path(forResource: "regions", ofType: "json")! }

    private func makeConfig(locationService: LocationService, bundledRegionsPath: String, dataLoader: MockDataLoader) -> AppConfig {
        AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsPath,
            dataLoader: dataLoader
        )
    }

    @Test func initialization() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let agencyAlertsData = Fixtures.loadData(file: "puget_sound_alerts.pb")
        dataLoader.mock(data: agencyAlertsData) { (request) -> Bool in
            request.url!.absoluteString.contains("api/gtfs_realtime/alerts-for-agency")
        }

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)

        let config = makeConfig(locationService: locationService, bundledRegionsPath: regionsFilePath, dataLoader: dataLoader)

        let application = Application(config: config)
        let mgr = MapRegionManager(application: application)

        #expect(mgr.mapView.showsScale)

        // Disable traffic in the Simulator to work around a bug in Xcode 11 and 12
        // where the console spews hundreds of error messages that read:
        // "Compiler error: Invalid library file"
        //
        // https://stackoverflow.com/a/63176707
        #if targetEnvironment(simulator)
        #expect(!mgr.mapView.showsTraffic)
        #else
        #expect(mgr.mapView.showsTraffic)
        #endif
    }

    /// When `currentRegion` is nil, `visibleMapRect` also returns `nil`.
    @Test func `Visible map rect nil region`() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)

        let locManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)

        dataLoader.mock(data: Fixtures.loadData(file: "puget_sound_alerts.pb")) { (request) -> Bool in
            request.url!.absoluteString.contains("api/gtfs_realtime/alerts-for-agency")
        }

        let config = makeConfig(locationService: locationService, bundledRegionsPath: regionsFilePath, dataLoader: dataLoader)

        let application = Application(config: config)
        let mgr = MapRegionManager(application: application)
        #expect(application.currentRegion == nil)
        #expect(mgr.lastVisibleMapRect == nil)
    }

    // MARK: - Zoom-In Warning Threshold

    /// The shared zoom-in-warning predicate (used by both the UIKit map's
    /// `zoomInStatus` and the SwiftUI `MapPanelRootView`) shows the warning only
    /// when the visible map rect is taller than the stop-loading threshold.
    @Test func `Should show zoom in warning threshold behavior`() {
        // Comfortably above the 40,000-point threshold → warn.
        #expect(MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: 100_000) == true)
        // Comfortably below → no warning.
        #expect(MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: 10_000) == false)
        // Exactly at the threshold is not "too far out".
        #expect(MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: 40_000) == false)
    }

    // MARK: - Zoom-In Warning Delivery

    /// Records what the map told its delegates about the zoom warning.
    @MainActor
    private final class ZoomStatusRecorder: NSObject, MapRegionDelegate {
        var statuses: [Bool] = []
        func mapRegionManagerShowZoomInStatus(_ manager: MapRegionManager, showStatus: Bool) {
            statuses.append(showStatus)
        }
    }

    /// A manager whose map is a real size — `visibleMapRect` is meaningless on a
    /// zero-frame map view.
    private func makeSizedManager() -> MapRegionManager {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = AuthorizableLocationManagerMock(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = makeConfig(locationService: locationService, bundledRegionsPath: regionsFilePath, dataLoader: dataLoader)

        let manager = MapRegionManager(application: Application(config: config))
        manager.mapView.frame = CGRect(x: 0, y: 0, width: 390, height: 700)
        return manager
    }

    /// Puts the manager into the state a route search leaves it in: exactly one
    /// result, which suppresses stop reloading. A bare object rather than a real
    /// `StopsForRoute` — every concrete result type either moves the camera or
    /// clears `searchResponse` on the next run loop, and neither is what this
    /// test is about. The `results.count == 1` shape is the whole trigger.
    private func displaySingleSearchResult(on manager: MapRegionManager) {
        manager.searchResponse = SearchResponse(
            request: SearchRequest(query: "10", type: .route),
            results: [NSObject()],
            boundingRegion: nil,
            error: nil
        )
    }

    /// The pill states something about the current zoom, so it has to be
    /// re-derived on every camera settle — including while a search result is
    /// displayed.
    ///
    /// A route search suppresses stop reloading and never clears
    /// `searchResponse` on its own (unlike the stop and map-item cases, which
    /// clear it on the next run loop). So a warning updated *after* that
    /// suppression guard freezes at whatever it was when the search began, and
    /// "Zoom in for stops" sits over a fully zoomed-in map showing the route's
    /// own stops. The SwiftUI map already orders this correctly; see
    /// `MapPanelRootView.onMapCameraChange`.
    @MainActor
    @Test func `A camera settle updates the zoom warning even while a search result is displayed`() {
        let manager = makeSizedManager()
        let recorder = ZoomStatusRecorder()
        manager.addDelegate(recorder)
        displaySingleSearchResult(on: manager)

        // Zoomed in far enough that stops load: the warning must come down.
        manager.mapView.visibleMapRect = MKMapRect(
            origin: MKMapPoint(TestData.mockSeattleLocation.coordinate),
            size: MKMapSize(width: 10_000, height: 10_000)
        )
        manager.mapView(manager.mapView, regionDidChangeAnimated: false)

        #expect(recorder.statuses.last == false)
    }

    /// The same ordering in the other direction: panning out to region scale
    /// while a search result is up must still raise the warning.
    @MainActor
    @Test func `A settle past the threshold raises the zoom warning while a search result is displayed`() {
        let manager = makeSizedManager()
        let recorder = ZoomStatusRecorder()
        manager.addDelegate(recorder)
        displaySingleSearchResult(on: manager)

        manager.mapView.visibleMapRect = MKMapRect(
            origin: MKMapPoint(TestData.mockSeattleLocation.coordinate),
            size: MKMapSize(width: 500_000, height: 500_000)
        )
        manager.mapView(manager.mapView, regionDidChangeAnimated: false)

        #expect(recorder.statuses.last == true)
    }

    // MARK: - Explicit-region stop loading

    @Test func `Request stops in region populates stops`() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        // The stop cache is a shared file; start clean so the assertion below
        // can only be satisfied by this test's own network fetch.
        clearStopCache(for: application)
        let mgr = MapRegionManager(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        await mgr.requestStops(in: region)

        #expect(!mgr.stops.isEmpty)
    }

    @Test func `Schedule stops request debounced load populates stops`() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        // Start clean, so reaching a non-empty `stops` below proves the
        // debounced fetch ran rather than a sibling test's leftover cache rows
        // being served before the debounce even elapsed.
        clearStopCache(for: application)
        let mgr = MapRegionManager(application: application)
        // Centered on the fixture stops (~2.8km north of the mock device
        // location) so the region-width cache serve actually covers them.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.653, longitude: -122.308),
            latitudinalMeters: 8000,
            longitudinalMeters: 8000
        )

        // Rapid succession: only the last should survive the debounce.
        mgr.scheduleStopsRequest(in: region)
        mgr.scheduleStopsRequest(in: region)

        await poll(until: { !mgr.stops.isEmpty }, "debounced stop load never landed")
        #expect(!mgr.stops.isEmpty)
    }

    // MARK: - Cache-First Serve

    /// Records every `stopsUpdated` delivery so a test can inspect the order in
    /// which stop sets are published (cache-first, then network).
    @MainActor
    private final class StopsRecorder: NSObject, MapRegionDelegate {
        var deliveries: [[Stop]] = []
        func mapRegionManager(_ manager: MapRegionManager, stopsUpdated stops: [Stop]) {
            deliveries.append(stops)
        }
    }

    /// Builds an application whose `currentRegion` is Puget Sound (regionId 1),
    /// with the Seattle stops fixture mocked for any stops-for-location request.
    private func makeSeattleApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: regionsFilePath,
            regionsAPIPath: regionsPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )
        return Application(config: config)
    }

    /// A region that genuinely has no stops must publish the empty set rather
    /// than leaving the previous region's stops in place. `mapRegionManager.stops`
    /// is read directly by `RoutePickerViewModel` (which skips its own API
    /// fallback when the set is non-empty) and `CurrentTripViewModel`, so a stale
    /// set doesn't just look wrong on the map — it feeds those two the wrong
    /// region's stops. Distinct from a nil `apiService`, where nothing was
    /// fetched and nothing should be published.
    @Test func `Schedule stops request publishes an empty set for a region with no stops`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)
        clearStopCache(for: application)

        let populated = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.653, longitude: -122.308),
            latitudinalMeters: 8000,
            longitudinalMeters: 8000
        )
        await mgr.requestStops(in: populated)
        #expect(!mgr.stops.isEmpty)

        // Now answer every stops request with an empty list, as the server does
        // for a region with no transit, and settle somewhere far from the cache.
        // `replaceMappedResponses` swaps atomically — clearing then re-mocking
        // would leave a window in which an in-flight request hits `fatalError`.
        dataLoader.replaceMappedResponses { loader in
            self.stubRegions(dataLoader: loader)
            self.stubAgenciesWithCoverage(dataLoader: loader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
            Fixtures.stubAllAgencyAlerts(dataLoader: loader)
            loader.mock(data: Fixtures.loadData(file: "stops_for_location_outofrange.json")) { request in
                request.url?.path.contains("/api/where/stops-for-location.json") ?? false
            }
        }
        let empty = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 46.5, longitude: -123.5),
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        mgr.scheduleStopsRequest(in: empty)

        await poll(until: { mgr.stops.isEmpty }, "stale stops were never cleared for the empty region")
        #expect(mgr.stops.isEmpty)
    }

    /// A settle over a recently-viewed area serves persisted stops immediately
    /// (before the debounce), then the network response refreshes them — so the
    /// first delivery is the cached subset and the last is the full network set.
    @Test func `Schedule stops request serves cached stops before network`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)

        let regionId = try #require(application.currentRegion?.regionIdentifier)
        // The cache DB is file-backed and shared across tests; start clean.
        clearStopCache(for: application)

        // Seed the cache with a distinguishable subset so the cache-served
        // delivery is tellable apart from the full network set.
        let fixtureStops = try Fixtures.loadSomeStops()
        try #require(fixtureStops.count >= 4, "Need at least 4 fixture stops")
        let cachedStops = Array(fixtureStops.prefix(3))
        application.stopCacheRepository?.saveStops(cachedStops, regionId: regionId)

        let recorder = StopsRecorder()
        mgr.addDelegate(recorder)

        // Centered on the fixture stops (not the mock device location, which sits
        // ~3km south of them) so the cache bounding-box query actually covers them.
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.653, longitude: -122.308),
            latitudinalMeters: 8000,
            longitudinalMeters: 8000
        )

        mgr.scheduleStopsRequest(in: region)

        // Network eventually replaces the cache set with the full fixture.
        await poll(until: { mgr.stops.count == fixtureStops.count }, "network refresh never replaced the cached subset")
        #expect(mgr.stops.count == fixtureStops.count)

        // First delivery came from the cache, before the network landed.
        let firstDelivery = try #require(recorder.deliveries.first)
        #expect(Set(firstDelivery.map(\.id)) == Set(cachedStops.map(\.id)))
        #expect(Set(mgr.stops.map(\.id)) == Set(fixtureStops.map(\.id)))
    }

    /// A cache miss is a no-op: the previously-loaded stops stay on the map until
    /// the network refresh repopulates the cache — no empty set is ever
    /// published (which would flash the map blank between the settle and the
    /// network response).
    @Test func `Schedule stops request cache miss keeps existing stops`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)

        clearStopCache(for: application)

        // Pre-populate stops so the map has existing pins to preserve.
        // Centered on the fixture stops so the region-width cache serve covers them.
        let seattleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.653, longitude: -122.308),
            latitudinalMeters: 8000,
            longitudinalMeters: 8000
        )
        await mgr.requestStops(in: seattleRegion)
        #expect(!mgr.stops.isEmpty)

        // Clear the cache so the upcoming settle is a genuine miss, while the
        // manager still holds the pre-populated stops.
        clearStopCache(for: application)

        let recorder = StopsRecorder()
        mgr.addDelegate(recorder)

        mgr.scheduleStopsRequest(in: seattleRegion)

        // The immediate band serve finds an empty cache and publishes nothing;
        // the network refresh repopulates the cache and the band re-serve then
        // delivers the stops.
        await poll(until: { !recorder.deliveries.isEmpty }, "no stops were ever delivered after the cache miss")
        #expect(!recorder.deliveries.isEmpty)
        // No delivery in the sequence was ever an empty set: the cache miss left
        // the map's stops untouched until the refresh arrived.
        #expect(recorder.deliveries.allSatisfy { !$0.isEmpty })
        #expect(!mgr.stops.isEmpty)
    }

    /// A settle whose band re-serve comes back empty even though the network
    /// fetch succeeded still publishes the fetched stops. This models the
    /// production gap where `currentRegion`/`regionId` is momentarily
    /// unavailable or the cache write silently no-ops, so the fresh stops would
    /// otherwise be dropped and the map left blank despite a successful fetch.
    @Test func `Schedule stops request publishes fetched stops when cache re-serve is empty`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)

        clearStopCache(for: application)

        // The mock returns the Seattle fixture for any stops request, but this
        // settle is centered ~70km south of those stops. So nothing is cached in
        // this band (first serve empty), the network fetch succeeds and saves the
        // Seattle stops, and the band re-serve — querying this far box — still
        // finds nothing. The repository is non-nil, so without the fallback the
        // fetched stops would be discarded and `mgr.stops` left empty.
        let farRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.308),
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        mgr.scheduleStopsRequest(in: farRegion)

        let fixtureStops = try Fixtures.loadSomeStops()
        try #require(!fixtureStops.isEmpty, "Need a non-empty stops fixture")
        await poll(until: { mgr.stops.count == fixtureStops.count }, "fetched stops were never published after the empty cache re-serve")
        #expect(mgr.stops.count == fixtureStops.count)
    }

    /// Cancelling stops a debounced request from landing after the host has
    /// moved on. `MapPanelRootView` relies on this when the camera settles
    /// zoomed out past the stop threshold: the in-flight request from the
    /// previous, zoomed-in settle must not repopulate the annotations the host
    /// just cleared. `scheduleStopsRequest` uses the same cancellation when a
    /// search result takes over the map.
    @Test func `Cancel scheduled stops request keeps a debounced load from landing`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)

        // An empty cache means the pre-debounce band serve publishes nothing,
        // so anything that shows up in `stops` can only have come from the
        // debounced fetch we're cancelling.
        clearStopCache(for: application)

        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.653, longitude: -122.308),
            latitudinalMeters: 8000,
            longitudinalMeters: 8000
        )

        mgr.scheduleStopsRequest(in: region)
        mgr.cancelScheduledStopsRequest()

        // Well past the 250ms debounce: had the request survived, it would have
        // fetched and published by now.
        try await Task.sleep(for: .milliseconds(600))
        #expect(mgr.stops.isEmpty)
    }

    /// The under-pin label height gate (routes served / bookmark name), shared
    /// by the UIKit `shouldHideExtraStopAnnotationData` and the SwiftUI
    /// `MapPanelRootView` — labels show only at/below the 7,000-point threshold.
    @Test func `Should show extra stop data threshold behavior`() {
        // Zoomed in close → show labels.
        #expect(MapRegionManager.shouldShowExtraStopData(forVisibleMapRectHeight: 1_000) == true)
        // At the threshold → still show.
        #expect(MapRegionManager.shouldShowExtraStopData(forVisibleMapRectHeight: 7_000) == true)
        // Zoomed out past it → hide.
        #expect(MapRegionManager.shouldShowExtraStopData(forVisibleMapRectHeight: 7_001) == false)
    }
}
