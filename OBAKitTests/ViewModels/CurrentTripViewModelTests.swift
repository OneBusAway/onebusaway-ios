//
//  CurrentTripViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `CurrentTripViewModel`.
class CurrentTripViewModelTests: OBATestCase {
    /// Near stop 1_10020 in the fixture (NE 55th & 37th Ave NE).
    private let userLocation = CLLocation(latitude: 47.6685, longitude: -122.2883)

    private var queue: OperationQueue!

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    // MARK: - Application Builder

    /// Builds an `Application` whose REST API service routes through the supplied `MockDataLoader`.
    /// When `withLocation` is false, the location service has no current location — useful for
    /// driving the `.noLocation` branch.
    private func createApplication(dataLoader: MockDataLoader, withLocation: Bool = true) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locationService: LocationService
        if withLocation {
            let locManager = MockAuthorizedLocationManager(
                updateLocation: userLocation,
                updateHeading: TestData.mockHeading
            )
            locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
            locationService.startUpdates()
        } else {
            // Plain mock — `startUpdatingLocation` flips a bool but never assigns a location,
            // so `currentLocation` stays `nil`.
            let locManager = LocationManagerMock()
            locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        }

        let config = AppConfig(
            regionsBaseURL: regionsURL,
            apiKey: apiKey,
            appVersion: appVersion,
            userDefaults: userDefaults,
            analytics: AnalyticsMock(),
            queue: queue,
            locationService: locationService,
            bundledRegionsFilePath: bundledRegionsPath,
            regionsAPIPath: regionsAPIPath,
            dataLoader: dataLoader,
            fixedRegionName: Fixtures.pugetSoundRegion.name
        )

        return Application(config: config)
    }

    // MARK: - Fixtures

    private let arrivalsFixture = "arrivals_and_departures_for_stop_1_10020.json"

    private func stopsFromArrivalsFixture() -> [Stop] {
        let response = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: arrivalsFixture)
        return [response.stop]
    }

    private func route30() -> Route {
        let stops = stopsFromArrivalsFixture()
        return stops.flatMap(\.routes).first { $0.id == "1_30" }!
    }

    private func makeMatchResult() -> NearbyTripMatcher.MatchResult {
        let arrivals = try! Fixtures.loadRESTAPIPayload(type: StopArrivals.self, fileName: arrivalsFixture)
        return NearbyTripMatcher.MatchResult(
            arrivalDeparture: arrivals.arrivalsAndDepartures[0],
            distanceFromUser: 50
        )
    }

    // MARK: - Initial State

    @MainActor
    func test_initialState_isLoading() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        guard case .loading = viewModel.state else {
            XCTFail("Expected initial state .loading, got \(viewModel.state)")
            return
        }
        expect(viewModel.matchResults).to(beEmpty())
        expect(viewModel.pendingNavigation).to(beNil())
    }

    // MARK: - handle(results:)

    @MainActor
    func test_handleResults_empty_setsNoResults() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.handle(results: [])

        guard case .noResults = viewModel.state else {
            XCTFail("Expected .noResults, got \(viewModel.state)")
            return
        }
        expect(viewModel.matchResults).to(beEmpty())
        expect(viewModel.pendingNavigation).to(beNil())
    }

    @MainActor
    func test_handleResults_single_setsPendingNavigation() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let result = makeMatchResult()
        viewModel.handle(results: [result])

        expect(viewModel.pendingNavigation).toNot(beNil())
        expect(viewModel.pendingNavigation?.tripID) == result.arrivalDeparture.tripID
        expect(viewModel.matchResults.count) == 1
        // State remains `.loading` — the consumer is expected to navigate away.
        guard case .loading = viewModel.state else {
            XCTFail("State should stay .loading for single match, got \(viewModel.state)")
            return
        }
    }

    @MainActor
    func test_handleResults_multiple_setsMultipleResults() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let first = makeMatchResult()
        let second = makeMatchResult()
        viewModel.handle(results: [first, second])

        guard case .multipleResults = viewModel.state else {
            XCTFail("Expected .multipleResults, got \(viewModel.state)")
            return
        }
        expect(viewModel.matchResults.count) == 2
        expect(viewModel.pendingNavigation).to(beNil())
    }

    // MARK: - handle(error:)

    @MainActor
    func test_handleError_noRealtimeData_setsNoRealtime() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.handle(error: NearbyTripMatcher.MatchError.noRealtimeData)

        guard case .noRealtime = viewModel.state else {
            XCTFail("Expected .noRealtime, got \(viewModel.state)")
            return
        }
    }

    @MainActor
    func test_handleError_genericError_setsErrorState() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let underlying = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "boom"])
        viewModel.handle(error: underlying)

        guard case .error(let surfaced) = viewModel.state else {
            XCTFail("Expected .error, got \(viewModel.state)")
            return
        }
        expect((surfaced as NSError).code) == 42
    }

    /// `noStopsNearby` is a `MatchError` but not `noRealtimeData` — it must fall through
    /// to the generic `.error` branch, not be silently mapped to `.noRealtime`.
    @MainActor
    func test_handleError_noStopsNearby_fallsThroughToError() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.handle(error: NearbyTripMatcher.MatchError.noStopsNearby)

        guard case .error = viewModel.state else {
            XCTFail("Expected .error for .noStopsNearby, got \(viewModel.state)")
            return
        }
    }

    // MARK: - pendingNavigationUnavailable()

    /// When the UIKit consumer cannot perform single-match navigation (no embedded
    /// `UINavigationController`), the VM falls back to the disambiguation list so
    /// the user can still tap through. `matchResults` is preserved from `handle(results:)`.
    @MainActor
    func test_pendingNavigationUnavailable_fallsBackToMultipleResults() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        let result = makeMatchResult()
        viewModel.handle(results: [result])
        expect(viewModel.pendingNavigation).toNot(beNil())
        expect(viewModel.matchResults.count) == 1

        viewModel.pendingNavigationUnavailable()

        guard case .multipleResults = viewModel.state else {
            XCTFail("Expected .multipleResults, got \(viewModel.state)")
            return
        }
        expect(viewModel.pendingNavigation).to(beNil())
        // The single match must still be available so the user can tap through.
        expect(viewModel.matchResults.count) == 1
    }

    // MARK: - findVehicle()

    @MainActor
    func test_findVehicle_noLocation_setsNoLocationState() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader, withLocation: false)
        let viewModel = CurrentTripViewModel(application: app, route: route30())

        viewModel.findVehicle()
        for _ in 0..<5 { await Task.yield() }

        guard case .noLocation = viewModel.state else {
            XCTFail("Expected .noLocation, got \(viewModel.state)")
            return
        }
    }

}
