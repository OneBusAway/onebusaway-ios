//
//  TripViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `TripViewModel`. Regression coverage for the `catch is CancellationError`
/// branch added in the VM refactor.
@Suite(.serialized)
final class TripViewModelTests: OBATestCase {
    var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func createApplication(dataLoader: MockDataLoader) -> Application {
        stubCommonEndpoints(dataLoader: dataLoader)

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

    /// Everything `createApplication` needs answered. Separate so a test can
    /// re-register it inside `MockDataLoader.replaceMappedResponses`.
    private func stubCommonEndpoints(dataLoader: MockDataLoader) {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)
        stubTripEndpoints(dataLoader: dataLoader)
        stubSurveys(dataLoader: dataLoader)
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
    @Test @MainActor
    func `Load data does not surface cancellation error`() async throws {
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

        #expect(viewModel.operationError == nil)
    }

    // MARK: - Shared destination (#449)

    // The two fixtures do not share a trip. The arrival is on trip 1_40989208,
    // and the details the broad stub serves are trip 1_18196913, so the
    // boarding stop has no row in them. The destination is then found by
    // searching the whole trip, which puts stop 1_29930 at row 10.

    /// Arrivals for a trip opened from a shared link: the boarding stop's, and
    /// the destination's, which can be made to fail. Register these before
    /// `createApplication`'s broad stubs: `MockDataLoader` serves the first
    /// stub that matches.
    private func stubSharedTripArrivals(dataLoader: MockDataLoader, destinationFails: Bool) {
        let boardingPath = "/arrival-and-departure-for-stop/1_11420.json"
        dataLoader.mock(data: Fixtures.loadData(file: "arrival-and-departure-for-stop-1_11420.json")) { request in
            request.url?.path.hasSuffix(boardingPath) ?? false
        }

        let destinationPath = "/arrival-and-departure-for-stop/1_29930.json"
        let destinationData = destinationFails ? Data() : Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        dataLoader.mock(data: destinationData, statusCode: destinationFails ? 404 : 200) { request in
            request.url?.path.hasSuffix(destinationPath) ?? false
        }
    }

    private func boardingTrip() throws -> TripConvertible {
        let arrivalDeparture = try Fixtures.loadRESTAPIPayload(
            type: ArrivalDeparture.self,
            fileName: "arrival-and-departure-for-stop-1_11420.json"
        )
        return TripConvertible(arrivalDeparture: arrivalDeparture)
    }

    private func destinationRequests(in dataLoader: MockDataLoader) -> [URL] {
        dataLoader.recordedRequestURLs.filter { $0.path.hasSuffix("/arrival-and-departure-for-stop/1_29930.json") }
    }

    /// A trip opened from a shared link asks for the destination's own arrival,
    /// for the destination's row and on the boarding arrival's trip, and
    /// publishes it.
    @Test @MainActor
    func `A shared destination's arrival is loaded for its row`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubSharedTripArrivals(dataLoader: dataLoader, destinationFails: false)
        let app = createApplication(dataLoader: dataLoader)
        try #require(app.apiService != nil)
        let trip = try boardingTrip()
        let viewModel = TripViewModel(application: app, tripConvertible: trip, destinationStopID: "1_29930")

        viewModel.loadData()
        await poll(until: { viewModel.destinationArrivalDeparture != nil }, timeout: .seconds(10), "the destination's arrival never loaded")

        // The payload served for the destination, not the boarding stop's.
        #expect(viewModel.destinationArrivalDeparture?.stopID == "MTS_11589")

        let request = try #require(destinationRequests(in: dataLoader).last)
        let query = try #require(URLComponents(url: request, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.first(where: { $0.name == "stopSequence" })?.value == "10")
        #expect(query.first(where: { $0.name == "tripId" })?.value == "1_40989208")
    }

    /// Every other trip makes the one arrival request it always made, for the
    /// boarding stop.
    @Test @MainActor
    func `Without a shared destination only the boarding arrival is requested`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubSharedTripArrivals(dataLoader: dataLoader, destinationFails: false)
        let app = createApplication(dataLoader: dataLoader)
        try #require(app.apiService != nil)
        let trip = try boardingTrip()
        let viewModel = TripViewModel(application: app, tripConvertible: trip)

        viewModel.loadData()
        await poll(until: { viewModel.tripDetails != nil && !viewModel.isLoading }, timeout: .seconds(10), "the trip never finished loading")

        let arrivalRequests = dataLoader.recordedRequestURLs.filter { $0.path.contains("/arrival-and-departure-for-stop/") }
        #expect(arrivalRequests.map(\.lastPathComponent) == ["1_11420.json"])
        #expect(viewModel.destinationArrivalDeparture == nil)
    }

    /// A refresh that fails to load the destination's arrival clears the
    /// countdown rather than leave the last prediction on screen, and raises
    /// no error alert: the trip itself still loaded.
    @Test @MainActor
    func `A failed refresh clears the destination's arrival without an error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        stubSharedTripArrivals(dataLoader: dataLoader, destinationFails: false)
        let app = createApplication(dataLoader: dataLoader)
        try #require(app.apiService != nil)
        let trip = try boardingTrip()
        let viewModel = TripViewModel(application: app, tripConvertible: trip, destinationStopID: "1_29930")
        viewModel.loadData()
        await poll(until: { viewModel.destinationArrivalDeparture != nil }, timeout: .seconds(10), "the first load never published the destination's arrival")

        dataLoader.replaceMappedResponses { staging in
            stubSharedTripArrivals(dataLoader: staging, destinationFails: true)
            stubCommonEndpoints(dataLoader: staging)
        }
        dataLoader.resetRecordedRequestURLs()
        viewModel.refresh()
        await poll(
            until: { !destinationRequests(in: dataLoader).isEmpty && !viewModel.isLoading },
            timeout: .seconds(10),
            "the refresh never finished asking for the destination's arrival"
        )

        #expect(viewModel.destinationArrivalDeparture == nil)
        #expect(viewModel.operationError == nil)
        #expect(viewModel.tripDetails != nil)
    }
}
