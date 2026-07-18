//
//  AddBookmarkViewControllerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
@testable import OBAKit
@testable import OBAKitCore

/// Locks down the `preloadedArrivals` short-circuit on `AddBookmarkViewController.loadData()`:
/// when the parent screen already has arrivals in hand, the controller must reuse them and
/// skip the `arrivals-and-departures-for-stop` REST call.
class AddBookmarkViewControllerTests: OBATestCase {
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

    // MARK: - Helpers

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        locationService.startUpdates()

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

    private func makeStop() throws -> Stop {
        try Fixtures.loadSomeStops().first!
    }

    private func makeArrivalDeparture() throws -> ArrivalDeparture {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        return try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
    }

    /// Returns the count of recorded requests whose path identifies the
    /// `arrivals-and-departures-for-stop` REST endpoint.
    private func arrivalsRequestCount(_ dataLoader: MockDataLoader) -> Int {
        dataLoader.recordedRequestURLs
            .filter { $0.path.contains("arrivals-and-departures-for-stop") }
            .count
    }

    // MARK: - Preloaded short-circuit

    @MainActor
    func test_loadData_withPreloadedArrivals_returnsThemWithoutNetworkFetch() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let stop = try makeStop()
        let preloaded = [try makeArrivalDeparture()]

        // Intentionally do NOT stub the arrivals endpoint. If the controller bypasses
        // the preloaded short-circuit and hits the network, MockDataLoader fatalErrors.
        let vc = AddBookmarkViewController(application: app, stop: stop, preloadedArrivals: preloaded, delegate: nil)

        dataLoader.resetRecordedRequestURLs()
        let result = try await vc.loadData()

        expect(result.count) == preloaded.count
        expect(result.first?.tripID) == preloaded.first?.tripID
        expect(self.arrivalsRequestCount(dataLoader)) == 0
    }

    // MARK: - Fallback to API

    @MainActor
    func test_loadData_withoutPreloadedArrivals_fetchesFromAPI() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let stop = try makeStop()

        let arrivalsURL = "https://api.pugetsound.onebusaway.org/api/where/arrivals-and-departures-for-stop/\(stop.id).json"
        dataLoader.mock(
            URLString: arrivalsURL,
            with: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        )

        let vc = AddBookmarkViewController(application: app, stop: stop, preloadedArrivals: nil, delegate: nil)

        dataLoader.resetRecordedRequestURLs()
        let result = try await vc.loadData()

        expect(result).toNot(beEmpty())
        expect(self.arrivalsRequestCount(dataLoader)) == 1
    }
}
