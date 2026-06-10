//
//  BookmarksViewModelTests.swift
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

// swiftlint:disable force_cast force_try

/// Tests for `BookmarksViewModel`. Verifies that the `sortByGroup` preference is read
/// from and written to UserDefaults under the documented key.
class BookmarksViewModelTests: OBATestCase {
    private let sortByGroupKey = "OBABookmarksController_SortBookmarksByGroup"
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

    // MARK: - Tests

    /// `init` defaults to `true` (set via `register(defaults:)`) on a clean UserDefaults.
    @MainActor
    func test_init_defaultsSortByGroupToTrue() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        expect(viewModel.sortByGroup).to(beTrue())
    }

    /// `init` reads the persisted value back out of UserDefaults.
    @MainActor
    func test_init_readsSortByGroupFromUserDefaults() {
        userDefaults.set(false, forKey: sortByGroupKey)

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        expect(viewModel.sortByGroup).to(beFalse())
    }

    /// `updateSortType` writes the new value to UserDefaults under the documented key
    /// and updates the published property.
    @MainActor
    func test_updateSortType_persistsToUserDefaults() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        viewModel.updateSortType(byGroup: false)

        expect(viewModel.sortByGroup).to(beFalse())
        expect(self.userDefaults.bool(forKey: self.sortByGroupKey)).to(beFalse())
    }

    // MARK: - isLoading

    /// `isLoading` starts `false` before any refresh.
    @MainActor
    func test_isLoading_defaultsToFalse() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        expect(viewModel.isLoading).to(beFalse())
    }

    /// A refresh that finds no eligible bookmarks must not leave `isLoading` stuck on `true`.
    /// `beginBatch(count: 0)` is the zero-fetch edge case in `BookmarkDataLoader` — the
    /// loader still has to report a clean `false` transition so consumer UI can recover.
    @MainActor
    func test_isLoading_remainsFalseWhenNoBookmarksToLoad() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        // userDataStore has zero bookmarks in this test's fresh UserDefaults suite.

        viewModel.refresh()
        // beginBatch is dispatched via `Task { @MainActor }` inside loadData() —
        // yield enough times for it to run and emit the delegate callback.
        for _ in 0..<5 { await Task.yield() }

        expect(viewModel.isLoading).to(beFalse())
    }

    // MARK: - lastRefreshHadError

    /// A failed batch sets `lastRefreshHadError` to `true`; a subsequent clean batch resets it.
    ///
    /// Regression test for the `lastBatchHadError` → `lastRefreshHadError` plumbing added in
    /// `BookmarkDataLoader` and `BookmarksViewModel`. Requires a region-eligible trip bookmark so
    /// the loader dispatches a real per-bookmark fetch that can fail.
    @MainActor
    func test_refresh_setsAndResetsLastRefreshHadError() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        // Add a region-eligible trip bookmark so the loader dispatches one fetch.
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(
            name: "Route 49",
            regionIdentifier: pugetSoundRegionIdentifier,
            arrivalDeparture: arrivalDep
        )
        app.userDataStore.add(bookmark, to: nil)

        // Stub the arrivals endpoint to return an error.
        dataLoader.mock(response: MockDataResponse(
            data: nil, urlResponse: nil,
            error: URLError(.badServerResponse)
        ) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false })

        let viewModel = BookmarksViewModel(application: app)
        expect(viewModel.lastRefreshHadError).to(beFalse())

        // Wait for the batch to fully complete (isLoading: false → true → false).
        let errBatchDone = expectation(description: "error batch finishes")
        var seenLoading = false
        var cancellables = Set<AnyCancellable>()
        viewModel.$isLoading.sink { isLoading in
            if isLoading { seenLoading = true }
            if seenLoading && !isLoading { errBatchDone.fulfill() }
        }.store(in: &cancellables)

        viewModel.refresh()
        await fulfillment(of: [errBatchDone], timeout: 2.0)
        cancellables.removeAll()

        expect(viewModel.lastRefreshHadError).to(beTrue())

        // Swap to a success stub — a clean batch must reset the flag. The swap is
        // atomic so in-flight background requests can never hit an empty mock table.
        dataLoader.replaceMappedResponses { staging in
            staging.mock(
                data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
            ) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }
        }

        let cleanBatchDone = expectation(description: "clean batch finishes")
        var seenLoading2 = false
        viewModel.$isLoading.sink { isLoading in
            if isLoading { seenLoading2 = true }
            if seenLoading2 && !isLoading { cleanBatchDone.fulfill() }
        }.store(in: &cancellables)

        viewModel.refresh()
        await fulfillment(of: [cleanBatchDone], timeout: 2.0)

        expect(viewModel.lastRefreshHadError).to(beFalse())
    }
}
