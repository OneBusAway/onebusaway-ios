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

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
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
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        // Rapid succession: only the last should survive the debounce.
        mgr.scheduleStopsRequest(in: region)
        mgr.scheduleStopsRequest(in: region)

        // Debounce is 250ms; poll up to Nimble's default timeout for the load.
        await expect(mgr.stops).toEventuallyNot(beEmpty())
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
}
