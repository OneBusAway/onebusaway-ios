//
//  MapRegionManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
import MapKit
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore
import Nimble

// swiftlintXdisable force_try

class MapRegionManagerTests: OBATestCase {
    var queue: OperationQueue!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()
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

    func test_init() {
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

        expect(mgr.mapView).toNot(beNil())
        expect(mgr.mapView.showsScale).to(beTrue())

        // Disable traffic in the Simulator to work around a bug in Xcode 11 and 12
        // where the console spews hundreds of error messages that read:
        // "Compiler error: Invalid library file"
        //
        // https://stackoverflow.com/a/63176707
        #if targetEnvironment(simulator)
        expect(mgr.mapView.showsTraffic).to(beFalse())
        #else
        expect(mgr.mapView.showsTraffic).to(beTrue())
        #endif
    }

    /// When `currentRegion` is nil, `visibleMapRect` also returns `nil`.
    func test_visibleMapRect_nilRegion() {
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
        expect(application.currentRegion).to(beNil())
        expect(mgr.lastVisibleMapRect).to(beNil())
    }

    @MainActor
    func test_requestStops_inRegion_populatesStops() async {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        // Any stops-for-location request returns the Seattle fixture.
        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

        // Inline config with fixedRegionName since this test needs a specific region
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

        let application = Application(config: config)
        let mgr = MapRegionManager(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        await mgr.requestStops(in: region)

        expect(mgr.stops).toNot(beEmpty())
    }

    @MainActor
    func test_scheduleStopsRequest_debouncedLoadPopulatesStops() async {
        let dataLoader = MockDataLoader(testName: name)
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

        // Inline config with fixedRegionName since this test needs a specific region
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

        let application = Application(config: config)
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

        // Debounce is 250ms; poll up to Nimble's default timeout for the load.
        await expect(mgr.stops).toEventuallyNot(beEmpty())
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

    /// A settle over a recently-viewed area serves persisted stops immediately
    /// (before the debounce), then the network response refreshes them — so the
    /// first delivery is the cached subset and the last is the full network set.
    @MainActor
    func test_scheduleStopsRequest_servesCachedStopsBeforeNetwork() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)

        let regionId = try XCTUnwrap(application.currentRegion?.regionIdentifier)
        // The cache DB is file-backed and shared across tests; start clean.
        application.stopCacheRepository?.clearCache(regionId: regionId)

        // Seed the cache with a distinguishable subset so the cache-served
        // delivery is tellable apart from the full network set.
        let fixtureStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(fixtureStops.count < 4, "Need at least 4 fixture stops")
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
        await expect(mgr.stops.count).toEventually(equal(fixtureStops.count))

        // First delivery came from the cache, before the network landed.
        let firstDelivery = try XCTUnwrap(recorder.deliveries.first)
        expect(Set(firstDelivery.map(\.id))) == Set(cachedStops.map(\.id))
        expect(Set(mgr.stops.map(\.id))) == Set(fixtureStops.map(\.id))
    }

    /// A cache miss is a no-op: the previously-loaded stops stay on the map until
    /// the network refresh repopulates the cache — no empty set is ever
    /// published (which would flash the map blank between the settle and the
    /// network response).
    @MainActor
    func test_scheduleStopsRequest_cacheMissKeepsExistingStops() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = makeSeattleApplication(dataLoader: dataLoader)
        let mgr = MapRegionManager(application: application)

        let regionId = try XCTUnwrap(application.currentRegion?.regionIdentifier)
        application.stopCacheRepository?.clearCache(regionId: regionId)

        // Pre-populate stops so the map has existing pins to preserve.
        // Centered on the fixture stops so the region-width cache serve covers them.
        let seattleRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 47.653, longitude: -122.308),
            latitudinalMeters: 8000,
            longitudinalMeters: 8000
        )
        await mgr.requestStops(in: seattleRegion)
        expect(mgr.stops).toNot(beEmpty())

        // Clear the cache so the upcoming settle is a genuine miss, while the
        // manager still holds the pre-populated stops.
        application.stopCacheRepository?.clearCache(regionId: regionId)

        let recorder = StopsRecorder()
        mgr.addDelegate(recorder)

        mgr.scheduleStopsRequest(in: seattleRegion)

        // The immediate band serve finds an empty cache and publishes nothing;
        // the network refresh repopulates the cache and the band re-serve then
        // delivers the stops.
        await expect(recorder.deliveries).toEventuallyNot(beEmpty())
        // No delivery in the sequence was ever an empty set: the cache miss left
        // the map's stops untouched until the refresh arrived.
        expect(recorder.deliveries.allSatisfy { !$0.isEmpty }).to(beTrue())
        expect(mgr.stops).toNot(beEmpty())
    }

    // MARK: - Zoom-In Warning Threshold

    /// The shared zoom-in-warning predicate (used by both the UIKit map's
    /// `zoomInStatus` and the SwiftUI `MapPanelRootView`) shows the warning only
    /// when the visible map rect is taller than the stop-loading threshold.
    func test_shouldShowZoomInWarning_thresholdBehavior() {
        // Comfortably above the 40,000-point threshold → warn.
        expect(MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: 100_000)) == true
        // Comfortably below → no warning.
        expect(MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: 10_000)) == false
        // Exactly at the threshold is not "too far out".
        expect(MapRegionManager.shouldShowZoomInWarning(forVisibleMapRectHeight: 40_000)) == false
    }

    /// The under-pin label height gate (routes served / bookmark name), shared
    /// by the UIKit `shouldHideExtraStopAnnotationData` and the SwiftUI
    /// `MapPanelRootView` — labels show only at/below the 7,000-point threshold.
    func test_shouldShowExtraStopData_thresholdBehavior() {
        // Zoomed in close → show labels.
        expect(MapRegionManager.shouldShowExtraStopData(forVisibleMapRectHeight: 1_000)) == true
        // At the threshold → still show.
        expect(MapRegionManager.shouldShowExtraStopData(forVisibleMapRectHeight: 7_000)) == true
        // Zoomed out past it → hide.
        expect(MapRegionManager.shouldShowExtraStopData(forVisibleMapRectHeight: 7_001)) == false
    }
}
