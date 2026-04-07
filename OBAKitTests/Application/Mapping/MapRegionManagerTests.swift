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
@testable import OBAKit
@testable import OBAKitCore
import Nimble

// swiftlintXdisable force_try

class MapRegionManagerTests: OBATestCase {
    private var regionsFilePath: String { Bundle.main.path(forResource: "regions", ofType: "json")! }

    private func makeConfig(locationService: LocationService, bundledRegionsPath: String, dataLoader: MockDataLoader) -> AppConfig {
        AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: OperationQueue(),
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

    func test_stopVisibility_hysteresis_staysVisibleWithinBand() {
        let staysVisible = MapRegionManager.shouldShowStopAnnotations(
            previouslyShowing: true,
            mapHeight: 41000
        )

        expect(staysVisible).to(beTrue())
    }

    func test_stopVisibility_hysteresis_staysHiddenWithinBand() {
        let staysHidden = MapRegionManager.shouldShowStopAnnotations(
            previouslyShowing: false,
            mapHeight: 39000
        )

        expect(staysHidden).to(beFalse())
    }

    func test_stopVisibility_hysteresis_transitionsAtThresholds() {
        let hides = MapRegionManager.shouldShowStopAnnotations(
            previouslyShowing: true,
            mapHeight: 42500
        )
        let shows = MapRegionManager.shouldShowStopAnnotations(
            previouslyShowing: false,
            mapHeight: 37500
        )

        expect(hides).to(beFalse())
        expect(shows).to(beTrue())
    }

    func test_zoomWarning_matchesVisibilityState() {
        let showPins = MapRegionManager.shouldShowStopAnnotations(
            previouslyShowing: true,
            mapHeight: 37000
        )
        let hidePins = MapRegionManager.shouldShowStopAnnotations(
            previouslyShowing: true,
            mapHeight: 43000
        )

        expect(!showPins).to(beFalse())
        expect(!hidePins).to(beTrue())
    }

    func test_mapView_viewForStop_resetsClusteringIdentifierOnReuse() {
        let dataLoader = MockDataLoader(testName: name)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        dataLoader.mock(data: Fixtures.loadData(file: "puget_sound_alerts.pb")) { request in
            request.url!.absoluteString.contains("api/gtfs_realtime/alerts-for-agency")
        }

        let locManager = AuthorizableLocationManagerMock(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: UserDefaults(), locationManager: locManager)
        let config = makeConfig(locationService: locationService, bundledRegionsPath: regionsFilePath, dataLoader: dataLoader)
        let application = Application(config: config)
        let manager = MapRegionManager(application: application)

        let stop = makeStop(id: "test-stop", name: "Pine")

        guard let firstView = manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView else {
            XCTFail("Expected StopAnnotationView")
            return
        }
        expect(firstView.clusteringIdentifier).to(equal(StopAnnotationView.stopClusterIdentifier))

        firstView.clusteringIdentifier = nil

        guard let reusedView = manager.mapView(manager.mapView, viewFor: stop) as? StopAnnotationView else {
            XCTFail("Expected StopAnnotationView on reuse")
            return
        }
        expect(reusedView.clusteringIdentifier).to(equal(StopAnnotationView.stopClusterIdentifier))
    }

    private func makeStop(id: String, name: String) -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "code": id,
            "name": name,
            "lat": 47.6,
            "lon": -122.3,
            "direction": "N",
            "locationType": 0,
            "routeIds": [],
            "wheelchairBoarding": "unknown"
        ]

        let data = try! JSONSerialization.data(withJSONObject: dict) // swiftlint:disable:this force_try
        let stop = try! JSONDecoder().decode(Stop.self, from: data) // swiftlint:disable:this force_try
        stop.routes = []
        return stop
    }

}
