//
//  RoutePickerViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import Combine
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

/// Tests for `RoutePickerViewModel`. Covers initial state, the API-fallback load
/// path, missing-location error path, API failure surfacing, search filtering
/// (case-insensitivity, short vs long name match, empty-query reset), and sort order.
class RoutePickerViewModelTests: OBATestCase {

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

    // MARK: - Application Builder

    /// Builds an `Application` with a real API service routing through the supplied
    /// `MockDataLoader`. The location service authorizes immediately and reports
    /// the canned Seattle location.
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

        return makeApp(dataLoader: dataLoader, locationService: locationService)
    }

    /// Like `createApplication`, but with a location manager that never reports a
    /// location — used to exercise the "no current location" error path.
    private func createApplicationWithoutLocation(dataLoader: MockDataLoader) -> Application {
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        let locManager = LocationManagerMock() // notDetermined; .location stays nil
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)
        // Intentionally do NOT call startUpdates — no authorization, no location.

        return makeApp(dataLoader: dataLoader, locationService: locationService)
    }

    private func makeApp(dataLoader: MockDataLoader, locationService: LocationService) -> Application {
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

    // MARK: - Stubs

    private func stubStopsForLocation(dataLoader: MockDataLoader) {
        let data = Fixtures.loadData(file: "stops_for_location_seattle.json")
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }
    }

    private func stubStopsForLocationWithError(dataLoader: MockDataLoader) {
        // Mock with invalid JSON to force a decoding error.
        let data = "not json".data(using: .utf8)!
        dataLoader.mock(data: data) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }
    }

    // MARK: - Initial State

    /// Before `loadRoutes()` runs, the VM exposes empty lists and a `false` finished flag.
    @MainActor
    func test_initialState_isEmptyAndNotLoaded() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        expect(vm.allRoutes).to(beEmpty())
        expect(vm.filteredRoutes).to(beEmpty())
        expect(vm.didFinishLoading).to(beFalse())
        expect(vm.loadError).to(beNil())
    }

    // MARK: - API fallback load

    /// With no cached stops, the VM fetches via the API service, deduplicates and sorts
    /// routes, and flips `didFinishLoading` to `true`.
    @MainActor
    func test_loadRoutes_apiFallback_populatesFilteredRoutes() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()

        expect(vm.didFinishLoading).to(beTrue())
        expect(vm.loadError).to(beNil())
        expect(vm.allRoutes).toNot(beEmpty())
        expect(vm.filteredRoutes.count) == vm.allRoutes.count

        // Routes should be unique by ID.
        let ids = vm.allRoutes.map(\.id)
        expect(Set(ids).count) == ids.count
    }

    /// Routes are sorted alphabetically (case-insensitive) — matches the existing VC behavior
    /// via `localizedCaseInsensitiveSort()`.
    @MainActor
    func test_loadRoutes_sortsRoutesCaseInsensitively() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()
        let sorted = vm.allRoutes
        let resorted = sorted.localizedCaseInsensitiveSort()

        // VM-stored order must equal a fresh sort of the same set.
        expect(sorted.map(\.id)) == resorted.map(\.id)
    }

    /// Calling `loadRoutes()` twice with a cache miss both times produces a stable, identical
    /// result — no duplication, no error, same route set.
    @MainActor
    func test_loadRoutes_canBeCalledRepeatedly() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()
        let firstCount = vm.allRoutes.count
        let firstIDs = vm.allRoutes.map(\.id)

        await vm.loadRoutes()
        let secondCount = vm.allRoutes.count
        let secondIDs = vm.allRoutes.map(\.id)

        expect(secondCount) == firstCount
        expect(secondIDs) == firstIDs
        expect(vm.loadError).to(beNil())
    }

    // MARK: - Error paths

    /// With no current location, `loadRoutes()` surfaces a localized error message and
    /// flips `didFinishLoading` so the UI can render the error state.
    @MainActor
    func test_loadRoutes_noLocation_setsLoadError() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplicationWithoutLocation(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()

        expect(vm.loadError).toNot(beNil())
        expect(vm.didFinishLoading).to(beTrue())
        expect(vm.allRoutes).to(beEmpty())
        expect(vm.filteredRoutes).to(beEmpty())
    }

    /// An API failure (invalid response payload) is surfaced as a `loadError` rather than
    /// crashing or leaving the UI stuck in a loading state.
    @MainActor
    func test_loadRoutes_apiError_setsLoadError() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocationWithError(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()

        expect(vm.loadError).toNot(beNil())
        expect(vm.didFinishLoading).to(beTrue())
        expect(vm.allRoutes).to(beEmpty())
    }

    // MARK: - Search filtering

    /// Empty query restores all routes; a non-matching query yields zero results;
    /// a matching prefix narrows the list and stays case-insensitive across upper/lower forms.
    @MainActor
    func test_updateSearch_filtersCaseInsensitively() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()
        let total = vm.allRoutes.count
        expect(total).to(beGreaterThan(0))

        // Pick a real route to derive a guaranteed-matching substring.
        let sample = vm.allRoutes.first!
        let needle = String(sample.shortName.prefix(1))

        vm.updateSearch(needle.lowercased())
        expect(vm.filteredRoutes).toNot(beEmpty())
        let lowerCount = vm.filteredRoutes.count

        vm.updateSearch(needle.uppercased())
        expect(vm.filteredRoutes.count) == lowerCount

        vm.updateSearch("zzzz_definitely_not_a_route")
        expect(vm.filteredRoutes).to(beEmpty())

        vm.updateSearch("")
        expect(vm.filteredRoutes.count) == total
    }

    /// A query that matches only a route's long name (not its short name) still hits.
    @MainActor
    func test_updateSearch_matchesLongName() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()

        // Find a route with a longName that isn't trivially contained in its shortName.
        let candidate = vm.allRoutes.first { route in
            guard let longName = route.longName, !longName.isEmpty else { return false }
            return !route.shortName.lowercased().contains(longName.lowercased())
        }

        guard let route = candidate, let longName = route.longName else {
            // Fixture didn't have a suitable route — skip without failing the suite.
            return
        }

        // Take a chunk of the long name that doesn't appear in the short name.
        let needle = String(longName.prefix(min(longName.count, 5))).lowercased()
        guard !route.shortName.lowercased().contains(needle) else { return }

        vm.updateSearch(needle)
        expect(vm.filteredRoutes.map(\.id)).to(contain(route.id))
    }

    /// `updateSearch` called BEFORE `loadRoutes()` is a no-op (filteredRoutes stays empty),
    /// but stores the query so a later load honors it.
    @MainActor
    func test_updateSearch_beforeLoad_isHonoredAfterLoad() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        vm.updateSearch("zzzz_definitely_not_a_route")
        expect(vm.filteredRoutes).to(beEmpty())

        await vm.loadRoutes()

        // Routes loaded, but the stored query filters everything out.
        expect(vm.allRoutes).toNot(beEmpty())
        expect(vm.filteredRoutes).to(beEmpty())
    }

    // MARK: - Publisher contracts

    /// `$filteredRoutes` emits whenever the search query changes the result set.
    @MainActor
    func test_filteredRoutesPublisher_emitsOnSearchChange() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()

        var emissions: [Int] = []
        let cancellable = vm.$filteredRoutes.sink { emissions.append($0.count) }
        defer { cancellable.cancel() }

        // First emission is the current value (post-load).
        let baseline = emissions.count
        vm.updateSearch("zzzz_definitely_not_a_route")
        vm.updateSearch("")

        // We expect at least two additional emissions after the baseline.
        expect(emissions.count).to(beGreaterThanOrEqualTo(baseline + 2))
        // Final emission should match the full set (search reset to empty).
        expect(emissions.last) == vm.allRoutes.count
    }

    /// `$didFinishLoading` emits `true` after a successful load.
    @MainActor
    func test_didFinishLoadingPublisher_flipsAfterLoad() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        var seen: [Bool] = []
        let cancellable = vm.$didFinishLoading.sink { seen.append($0) }
        defer { cancellable.cancel() }

        await vm.loadRoutes()

        expect(seen.first) == false
        expect(seen.last) == true
    }

    // MARK: - loadError clear-on-retry

    /// A successful retry after a failed `loadRoutes()` clears `loadError` on the same VM.
    /// Without the `loadError = nil` clear at the top of `loadRoutes()`, the VC would
    /// short-circuit `items(for:)` to an empty list because of stale error state.
    ///
    /// Both runs operate on a single VM whose underlying `LocationService` starts with
    /// no location (error path) and then receives one (success path). This is the
    /// shape that actually exercises the clear-on-retry contract — a fresh VM would
    /// pass regardless of whether the clear line existed.
    @MainActor
    func test_loadRoutes_retryClearsPriorLoadError() async {
        let dataLoader = MockDataLoader(testName: name)
        stubStopsForLocation(dataLoader: dataLoader)
        stubRegions(dataLoader: dataLoader)
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
        Fixtures.stubAllAgencyAlerts(dataLoader: dataLoader)

        // Authorized but not yet updating — `location` is nil so `LocationService.currentLocation`
        // starts nil. The VM exits via the locationUnavailable branch on the first call.
        let locManager = MockAuthorizedLocationManager(
            updateLocation: TestData.mockSeattleLocation,
            updateHeading: TestData.mockHeading
        )
        let locationService = LocationService(userDefaults: userDefaults, locationManager: locManager)

        let app = makeApp(dataLoader: dataLoader, locationService: locationService)
        let vm = RoutePickerViewModel(application: app)

        // Run #1: no location → loadError set.
        await vm.loadRoutes()
        expect(vm.loadError).toNot(beNil())
        expect(vm.didFinishLoading).to(beTrue())

        // Start updates: the mock manager publishes its canned location, which the
        // LocationService delegate ingests as `currentLocation`.
        locationService.startUpdates()
        expect(locationService.currentLocation).toNot(beNil())

        // Run #2 on the same VM: success path clears loadError.
        await vm.loadRoutes()
        expect(vm.loadError).to(beNil())
        expect(vm.allRoutes).toNot(beEmpty())
    }

    // MARK: - Cache-first branch

    /// When `mapRegionManager.stops` is already populated, `loadRoutes()` takes the
    /// cache path and does not hit the stops API.
    @MainActor
    func test_loadRoutes_cacheFirst_doesNotHitAPI() async {
        let dataLoader = MockDataLoader(testName: name)

        // Counter wrapping the stops-for-location matcher.
        final class HitCounter: @unchecked Sendable {
            nonisolated(unsafe) var hits = 0
        }
        let counter = HitCounter()
        let data = Fixtures.loadData(file: "stops_for_location_seattle.json")
        let url = URL(string: "https://mockdataloader.example.com")!
        let response = MockDataResponse(
            data: data,
            urlResponse: HTTPURLResponse(url: url, statusCode: 200, httpVersion: "2", headerFields: ["Content-Type": "application/json"])!,
            error: nil
        ) { req in
            guard req.url?.path.contains("/api/where/stops-for-location.json") ?? false else { return false }
            counter.hits += 1
            return true
        }
        dataLoader.mock(response: response)

        let app = createApplication(dataLoader: dataLoader)

        // Prime mapRegionManager.stops via its real loading path. This hit counts
        // as #1.
        await app.mapRegionManager.requestDataForMapRegion()
        expect(app.mapRegionManager.stops).toNot(beEmpty())
        expect(counter.hits) == 1

        let vm = RoutePickerViewModel(application: app)
        await vm.loadRoutes()

        // The cache branch must populate filteredRoutes from mapRegionManager.stops
        // without issuing another stops-for-location request.
        expect(vm.didFinishLoading).to(beTrue())
        expect(vm.loadError).to(beNil())
        expect(vm.allRoutes).toNot(beEmpty())
        expect(counter.hits) == 1
    }

    // MARK: - Cancellation

    /// A cancelled `loadRoutes()` finalizes without setting `loadError`. The VM
    /// matches both `CancellationError` and `URLError(.cancelled)` so a re-observed
    /// VM doesn't get stuck on "Loading routes…".
    @MainActor
    func test_loadRoutes_cancellation_finalizesWithoutError() async {
        let dataLoader = MockDataLoader(testName: name)
        // Stub the stops endpoint to throw URLError(.cancelled) — the shape
        // URLSession surfaces when a data task is cancelled.
        let response = MockDataResponse(
            data: nil,
            urlResponse: nil,
            error: URLError(.cancelled)
        ) { req in
            req.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }
        dataLoader.mock(response: response)

        let app = createApplication(dataLoader: dataLoader)
        let vm = RoutePickerViewModel(application: app)

        await vm.loadRoutes()

        expect(vm.didFinishLoading).to(beFalse())
        expect(vm.loadError).to(beNil())
        expect(vm.allRoutes).to(beEmpty())
    }
}
