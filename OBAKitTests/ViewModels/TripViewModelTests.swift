//
//  TripViewModelTests.swift
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

// swiftlint:disable force_cast force_try

/// Tests for `TripViewModel`. Regression coverage for the `catch is CancellationError`
/// branch added in the VM refactor.
class TripViewModelTests: OBATestCase {
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
        stubTripEndpoints(dataLoader: dataLoader)
        stubSurveys(dataLoader: dataLoader)

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

    /// Broad-match stubs for the three endpoints `TripViewModel.loadData()` may hit.
    /// Even though the test cancels before completion, the mocks must be in place to
    /// avoid `fatalError` on URL mismatch if the task races past the cancel point.
    private func stubTripEndpoints(dataLoader: MockDataLoader) {
        let trip = Fixtures.loadData(file: "trip_details_1_18196913.json")
        dataLoader.mock(data: trip) { request in
            request.url?.path.contains("/api/where/trip-details") ?? false
        }
        // Use the same payload for arrival-and-departure-for-stop calls. The path matcher
        // only checks host+path, not the exact stop id.
        dataLoader.mock(data: trip) { request in
            request.url?.path.contains("/api/where/arrival-and-departure-for-stop") ?? false
        }
        // Empty shape — VM only checks for non-nil; an empty payload is fine.
        let emptyShape = #"{"data":{"entry":{"length":0,"points":"","levels":""}},"code":200,"version":2,"text":"OK","currentTime":1700000000000}"#.data(using: .utf8)!
        dataLoader.mock(data: emptyShape) { request in
            request.url?.path.contains("/api/where/shape") ?? false
        }
    }

    private func stubSurveys(dataLoader: MockDataLoader) {
        let emptySurveys = #"{"surveys":[]}"#.data(using: .utf8)!
        dataLoader.mock(data: emptySurveys) { request in
            request.url?.path.contains("/surveys.json") ?? false
        }
    }

    private func makeTripConvertible() throws -> TripConvertible {
        let data = Fixtures.loadData(file: "trip_details_1_18196913.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<TripDetails>.self, from: data)
        return TripConvertible(tripDetails: response.entry)
    }

    // MARK: - Tests

    /// A cancelled `loadData()` task must not surface a user-facing error. The `catch is
    /// CancellationError { return }` branch in `loadData()` handles this; if it's removed,
    /// the cancellation would fall through to the generic `catch { operationError = error }`.
    @MainActor
    func test_loadData_doesNotSurfaceCancellationError() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let tripConvertible = try makeTripConvertible()
        let viewModel = TripViewModel(application: app, tripConvertible: tripConvertible)

        // Spawn the load and immediately cancel it. `deactivate()` calls
        // `loadDataTask?.cancel()` synchronously, before the task body has had a chance
        // to run, so the first `await` inside the task observes the cancellation.
        viewModel.loadData()
        viewModel.deactivate()

        // Yield enough times for the cancelled task to settle.
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.operationError).to(beNil())
    }
}
