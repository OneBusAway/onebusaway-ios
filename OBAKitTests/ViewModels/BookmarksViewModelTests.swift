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

    // MARK: - Section Building

    /// Pins the section ID vocabulary: group sections use the group's UUID
    /// string, ungrouped bookmarks land in `"unknown_group"`, and distance
    /// sorting uses `"distance_sorted_group"`. These IDs key users' persisted
    /// collapse state — renaming any of them silently orphans that state.
    @MainActor
    func test_rebuildSections_sectionIDsMatchLegacyVocabulary() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)

        let group = BookmarkGroup(name: "Work", sortOrder: 0)
        app.userDataStore.upsert(bookmarkGroup: group)
        app.userDataStore.add(
            Bookmark(name: "Grouped", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep),
            to: group
        )
        app.userDataStore.add(
            Bookmark(name: "Ungrouped", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep),
            to: nil
        )

        let viewModel = BookmarksViewModel(application: app)
        viewModel.rebuildSections()

        expect(viewModel.sections.map(\.id)) == [group.id.uuidString, "unknown_group"]
        expect(viewModel.sections.map { $0.rows.map(\.name) }) == [["Grouped"], ["Ungrouped"]]

        viewModel.updateSortType(byGroup: false)
        expect(viewModel.sections.map(\.id)) == ["distance_sorted_group"]
        expect(viewModel.sections.first?.rows.count) == 2
    }

    /// Bookmarks from other regions must not appear, and a section whose
    /// bookmarks are all filtered out is omitted entirely — with the standard
    /// empty state shown rather than a blank list.
    @MainActor
    func test_rebuildSections_filtersBookmarksFromOtherRegions() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)

        app.userDataStore.add(
            Bookmark(name: "Elsewhere", regionIdentifier: pugetSoundRegionIdentifier + 1, arrivalDeparture: arrivalDep),
            to: nil
        )

        let viewModel = BookmarksViewModel(application: app)
        viewModel.rebuildSections()

        expect(viewModel.sections).to(beEmpty())
        expect(viewModel.emptyState.title) == Strings.emptyBookmarkTitle
        expect(viewModel.emptyState.body) == Strings.emptyBookmarkBody
    }

    // MARK: - refreshAndWait

    /// A pull-to-refresh with zero eligible bookmarks must return promptly
    /// rather than suspending forever (the spinner would never dismiss).
    @MainActor
    func test_refreshAndWait_returnsForEmptyBatch() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        expect(viewModel.isLoading).to(beFalse())
    }

    /// `refreshAndWait` resumes only after its own batch completes, with the
    /// fetched arrival data already applied to `sections`.
    @MainActor
    func test_refreshAndWait_waitsForItsBatchAndAppliesData() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
        app.userDataStore.add(
            Bookmark(name: "Route 49", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep),
            to: nil
        )
        dataLoader.mock(
            data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        ) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        expect(viewModel.isLoading).to(beFalse())
        let row = try XCTUnwrap(viewModel.sections.first?.rows.first)
        expect(row.hasLoadedArrivalData).to(beTrue())
        expect(row.arrivalDepartures).toNot(beEmpty())
    }

    // MARK: - Collapse State

    /// Collapse state persisted by the legacy `BookmarksViewController` (same
    /// key, same `Set<String>` encoding) must survive into the rewrite, and
    /// toggling must round-trip back to UserDefaults.
    @MainActor
    func test_collapsedSections_persistenceRoundTrip() throws {
        let key = "collapsedBookmarkSections"
        try userDefaults.encodeUserDefaultsObjects(Set(["unknown_group"]), key: key)

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = BookmarksViewModel(application: app)

        expect(viewModel.collapsedSectionIDs) == ["unknown_group"]

        viewModel.toggleSectionCollapsed("distance_sorted_group")
        expect(viewModel.collapsedSectionIDs) == ["unknown_group", "distance_sorted_group"]

        viewModel.toggleSectionCollapsed("unknown_group")
        expect(viewModel.collapsedSectionIDs) == ["distance_sorted_group"]

        let persisted = try userDefaults.decodeUserDefaultsObjects(type: Set<String>.self, key: key)
        expect(persisted) == ["distance_sorted_group"]
    }

    // MARK: - BookmarkRowViewModel Equality

    /// `BookmarkRowViewModel.==` gates the `sections` publish in
    /// `rebuildSections()` — any display-relevant field omitted from `==`
    /// means a permanently stale row on screen.
    @MainActor
    func test_bookmarkRowViewModel_equalityCoversDisplayFields() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(name: "Route 49", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)

        let base = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [])

        // Same inputs → equal, even though `bookmark` is a reference type.
        expect(base) == BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [])

        // Arrival data and highlights are display state → unequal.
        expect(base) != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDep], highlightedTripIDs: [])
        expect(base) != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [arrivalDep.tripID])

        // Mutable Bookmark fields (name, favorite) are display state → unequal.
        bookmark.name = "Renamed"
        expect(base) != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [])
        bookmark.name = "Route 49"
        bookmark.isFavorite = true
        expect(base) != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [])
    }

    /// The init clamp: whole-stop bookmarks never carry arrival data, even if
    /// a caller passes some.
    @MainActor
    func test_bookmarkRowViewModel_clampsArrivalsForStopBookmarks() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try XCTUnwrap(stopArrivals.arrivalsAndDepartures.first)
        let stopBookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: arrivalDep.stop)

        let row = BookmarkRowViewModel(bookmark: stopBookmark, arrivalDepartures: [arrivalDep], highlightedTripIDs: [])

        expect(row.isTripBookmark).to(beFalse())
        expect(row.arrivalDepartures).to(beEmpty())
        expect(row.routesSubtitle).toNot(beNil())
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
        // Timeout sized for GitHub Actions runner headroom, not local speed —
        // the batch's `Task { @MainActor }` chain lands well under a second
        // locally but has flaked at 2s on CI under load.
        await fulfillment(of: [errBatchDone], timeout: 10.0)
        cancellables.removeAll()

        expect(viewModel.lastRefreshHadError).to(beTrue())

        // Swap to a success stub — a clean batch must reset the flag. The swap is
        // atomic so in-flight background requests can never hit an empty mock table.
        // replaceMappedResponses replaces the *entire* table, so re-register the
        // regions/agencies/alerts mocks that the Application's background tasks rely on.
        dataLoader.replaceMappedResponses { staging in
            stubRegions(dataLoader: staging)
            stubAgenciesWithCoverage(dataLoader: staging, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
            Fixtures.stubAllAgencyAlerts(dataLoader: staging)
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
        await fulfillment(of: [cleanBatchDone], timeout: 10.0)

        expect(viewModel.lastRefreshHadError).to(beFalse())
    }
}
