//
//  BookmarksViewModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import Combine
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast force_try

/// Tests for `BookmarksViewModel`. Verifies that the `sortByGroup` preference is read
/// from and written to UserDefaults under the documented key.
@Suite(.serialized)
final class BookmarksViewModelTests: OBATestCase {
    private let sortByGroupKey = "OBABookmarksController_SortBookmarksByGroup"
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

    @MainActor
    private final class DisplayErrorSpyApplication: Application {
        private(set) var displayErrorCallCount = 0

        override func displayError(_ error: Error) async {
            displayErrorCallCount += 1
        }
    }

    private func createSpyApplication(dataLoader: MockDataLoader) -> DisplayErrorSpyApplication {
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

        return DisplayErrorSpyApplication(config: config)
    }

    private func addTripBookmark(to app: Application) throws -> Bookmark {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(
            name: "Route 49",
            regionIdentifier: pugetSoundRegionIdentifier,
            arrivalDeparture: arrivalDep
        )
        app.userDataStore.add(bookmark, to: nil)
        return bookmark
    }

    // MARK: - Tests

    /// `init` defaults to `true` (set via `register(defaults:)`) on a clean UserDefaults.
    @Test @MainActor
    func `Init defaults sort by group to true`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        #expect(viewModel.sortByGroup)
    }

    /// `init` reads the persisted value back out of UserDefaults.
    @Test @MainActor
    func `Init reads sort by group from user defaults`() {
        userDefaults.set(false, forKey: sortByGroupKey)

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        #expect(!viewModel.sortByGroup)
    }

    /// `updateSortType` writes the new value to UserDefaults under the documented key
    /// and updates the published property.
    @Test @MainActor
    func `Update sort type persists to user defaults`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        viewModel.updateSortType(byGroup: false)

        #expect(!viewModel.sortByGroup)
        #expect(!self.userDefaults.bool(forKey: self.sortByGroupKey))
    }

    // MARK: - isLoading

    /// `isLoading` starts `false` before any refresh.
    @Test @MainActor
    func `Is loading defaults to false`() {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)

        #expect(!viewModel.isLoading)
    }

    /// A refresh that finds no eligible bookmarks must not leave `isLoading` stuck on `true`.
    /// `beginBatch(count: 0)` is the zero-fetch edge case in `BookmarkDataLoader` — the
    /// loader still has to report a clean `false` transition so consumer UI can recover.
    @Test @MainActor
    func `Is loading remains false when no bookmarks to load`() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        // userDataStore has zero bookmarks in this test's fresh UserDefaults suite.

        viewModel.refresh()
        // beginBatch is dispatched via `Task { @MainActor }` inside loadData() —
        // yield enough times for it to run and emit the delegate callback.
        for _ in 0..<5 { await Task.yield() }

        #expect(!viewModel.isLoading)
    }

    // MARK: - Section Building

    /// Pins the section ID vocabulary: group sections use the group's UUID
    /// string, ungrouped bookmarks land in `"unknown_group"`, and distance
    /// sorting uses `"distance_sorted_group"`. These IDs key users' persisted
    /// collapse state — renaming any of them silently orphans that state.
    @Test @MainActor
    func `Rebuild sections section IDs match legacy vocabulary`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)

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

        #expect(viewModel.sections.map(\.id) == [group.id.uuidString, "unknown_group"])
        #expect(viewModel.sections.map { $0.rows.map(\.name) } == [["Grouped"], ["Ungrouped"]])

        viewModel.updateSortType(byGroup: false)
        #expect(viewModel.sections.map(\.id) == ["distance_sorted_group"])
        #expect(viewModel.sections.first?.rows.count == 2)
    }

    /// Bookmarks from other regions must not appear, and a section whose
    /// bookmarks are all filtered out is omitted entirely — with the standard
    /// empty state shown rather than a blank list.
    @Test @MainActor
    func `Rebuild sections filters bookmarks from other regions`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)

        app.userDataStore.add(
            Bookmark(name: "Elsewhere", regionIdentifier: pugetSoundRegionIdentifier + 1, arrivalDeparture: arrivalDep),
            to: nil
        )

        let viewModel = BookmarksViewModel(application: app)
        viewModel.rebuildSections()

        #expect(viewModel.sections.isEmpty)
        #expect(viewModel.emptyState.title == Strings.emptyBookmarkTitle)
        #expect(viewModel.emptyState.body == Strings.emptyBookmarkBody)
    }

    // MARK: - refreshAndWait

    /// A pull-to-refresh with zero eligible bookmarks must return promptly
    /// rather than suspending forever (the spinner would never dismiss).
    @Test @MainActor
    func `Refresh and wait returns for empty batch`() async {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        #expect(!viewModel.isLoading)
    }

    /// `refreshAndWait` resumes only after its own batch completes, with the
    /// fetched arrival data already applied to `sections`.
    @Test @MainActor
    func `Refresh and wait waits for its batch and applies data`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        app.userDataStore.add(
            Bookmark(name: "Route 49", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep),
            to: nil
        )
        dataLoader.mock(
            data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        ) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        #expect(!viewModel.isLoading)
        let row = try #require(viewModel.sections.first?.rows.first)
        #expect(row.hasLoadedArrivalData)
        #expect(!row.arrivalDepartures.isEmpty)
    }

    // MARK: - Collapse State

    /// Collapse state persisted by the legacy `BookmarksViewController` (same
    /// key, same `Set<String>` encoding) must survive into the rewrite, and
    /// toggling must round-trip back to UserDefaults.
    @Test @MainActor
    func `Collapsed sections persistence round trip`() throws {
        let key = "collapsedBookmarkSections"
        try userDefaults.encodeUserDefaultsObjects(Set(["unknown_group"]), key: key)

        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)
        let viewModel = BookmarksViewModel(application: app)

        #expect(viewModel.collapsedSectionIDs == ["unknown_group"])

        viewModel.toggleSectionCollapsed("distance_sorted_group")
        #expect(viewModel.collapsedSectionIDs == ["unknown_group", "distance_sorted_group"])

        viewModel.toggleSectionCollapsed("unknown_group")
        #expect(viewModel.collapsedSectionIDs == ["distance_sorted_group"])

        let persisted = try userDefaults.decodeUserDefaultsObjects(type: Set<String>.self, key: key)
        #expect(persisted == ["distance_sorted_group"])
    }

    // MARK: - BookmarkRowViewModel Equality

    /// `BookmarkRowViewModel.==` gates the `sections` publish in
    /// `rebuildSections()` — any display-relevant field omitted from `==`
    /// means a permanently stale row on screen.
    @Test @MainActor
    func `Bookmark row view model equality covers display fields`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(name: "Route 49", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)

        let base = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [])

        // Same inputs → equal, even though `bookmark` is a reference type.
        #expect(base == BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: []))

        // Arrival data and highlights are display state → unequal.
        #expect(base != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDep], highlightedTripIDs: []))
        #expect(base != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: [arrivalDep.tripID]))

        // Mutable Bookmark fields (name, favorite) are display state → unequal.
        bookmark.name = "Renamed"
        #expect(base != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: []))
        bookmark.name = "Route 49"
        bookmark.isFavorite = true
        #expect(base != BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [], highlightedTripIDs: []))
    }

    /// The init clamp: whole-stop bookmarks never carry arrival data, even if
    /// a caller passes some.
    @Test @MainActor
    func `Bookmark row view model clamps arrivals for stop bookmarks`() throws {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let stopBookmark = Bookmark(name: "Stop", regionIdentifier: pugetSoundRegionIdentifier, stop: arrivalDep.stop)

        let row = BookmarkRowViewModel(bookmark: stopBookmark, arrivalDepartures: [arrivalDep], highlightedTripIDs: [])

        #expect(!row.isTripBookmark)
        #expect(row.arrivalDepartures.isEmpty)
        #expect(row.routesSubtitle != nil)
    }

    // MARK: - Accessibility value

    /// The bookmark card renders the corrected time with the schedule struck
    /// through (`DepartureTimeText`); VoiceOver can't perceive a strikethrough,
    /// so the correction must arrive in words — appended as its own sentence,
    /// because the base value ends with terminal punctuation. The fixture's
    /// arrival is predicted 156 s off its timetable, which lands in a
    /// different clock minute and therefore renders (and must speak) the
    /// correction.
    @Test @MainActor
    func `Accessibility value speaks corrected time clause when prediction moves off schedule`() throws {
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(name: "Route 49", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: arrivalDep)
        let row = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [arrivalDep], highlightedTripIDs: [])

        let value = try #require(formatters.accessibilityValue(for: row))

        // Build the clause the same way production does (`DepartureTimeDisplay`),
        // not by re-assembling the English format string. Hardcoding the English
        // template disagrees with `OBALoc` whenever the test host's preferred
        // language is not English — which is how this assertion flakes on CI.
        let timeDisplay = DepartureTimeDisplay(arrivalDeparture: arrivalDep, formatters: formatters)
        #expect(timeDisplay.scheduledTimeText != nil)
        #expect(value == formatters.accessibilityValue(for: arrivalDep) + " " + timeDisplay.accessibilityTimeDescription + ".")
    }

    /// Without a rendered correction there's nothing the strikethrough shows
    /// that the base value doesn't already say — the clause must be absent,
    /// not repeating the expected time. The RVTD fixture's arrival declares
    /// `predicted: false`, so no correction ever renders.
    @Test @MainActor
    func `Accessibility value omits time clause without a correction`() throws {
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1739-rvtd.json"
        )
        let unpredicted = try #require(stopArrivals.arrivalsAndDepartures.first)
        let bookmark = Bookmark(name: "RVTD", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: unpredicted)
        let row = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: [unpredicted], highlightedTripIDs: [])

        let value = try #require(formatters.accessibilityValue(for: row))

        #expect(value == formatters.accessibilityValue(for: unpredicted))
    }

    /// With follow-up departures present, the corrected-time clause slots
    /// between the first arrival's base value and the "Following …" sentence.
    /// That relative order is user-facing VoiceOver output — a refactor must
    /// not silently reorder it.
    @Test @MainActor
    func `Accessibility value speaks clause before followup departures`() throws {
        let formatters = Formatters(locale: Locale(identifier: "en_US"), calendar: Calendar(identifier: .gregorian), themeColors: ThemeColors.shared)
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914-duplicates.json"
        )
        let arrivals = Array(stopArrivals.arrivalsAndDepartures.prefix(2))
        let first = try #require(arrivals.first)
        let bookmark = Bookmark(name: "Route 49", regionIdentifier: pugetSoundRegionIdentifier, arrivalDeparture: first)
        let row = BookmarkRowViewModel(bookmark: bookmark, arrivalDepartures: arrivals, highlightedTripIDs: [])

        let value = try #require(formatters.accessibilityValue(for: row))

        let timeDisplay = DepartureTimeDisplay(arrivalDeparture: first, formatters: formatters)
        #expect(timeDisplay.scheduledTimeText != nil)
        let prefix = formatters.accessibilityValue(for: first) + " " + timeDisplay.accessibilityTimeDescription + "."
        #expect(value.hasPrefix(prefix), "clause must directly follow the base value: \(value)")
        #expect(value.dropFirst(prefix.count).contains("Following"), "follow-up sentence must come after the clause: \(value)")
    }

    // MARK: - lastRefreshHadError

    /// A failed batch sets `lastRefreshHadError` to `true`; a subsequent clean batch resets it.
    ///
    /// Regression test for the `lastBatchHadError` → `lastRefreshHadError` plumbing added in
    /// `BookmarkDataLoader` and `BookmarksViewModel`. Requires a region-eligible trip bookmark so
    /// the loader dispatches a real per-bookmark fetch that can fail.
    @Test @MainActor
    func `Refresh sets and resets last refresh had error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createApplication(dataLoader: dataLoader)

        // Add a region-eligible trip bookmark so the loader dispatches one fetch.
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDep = try #require(stopArrivals.arrivalsAndDepartures.first)
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
        #expect(!viewModel.lastRefreshHadError)

        // Wait for the batch to fully complete (isLoading: false → true → false).
        var errBatchDone = false
        var seenLoading = false
        var cancellables = Set<AnyCancellable>()
        viewModel.$isLoading.sink { isLoading in
            if isLoading { seenLoading = true }
            if seenLoading && !isLoading { errBatchDone = true }
        }.store(in: &cancellables)

        viewModel.refresh()
        // Timeout sized for GitHub Actions runner headroom, not local speed —
        // the batch's `Task { @MainActor }` chain lands well under a second
        // locally but has flaked at 2s on CI under load.
        await poll(until: { errBatchDone }, timeout: .seconds(10), "error batch never finished")
        cancellables.removeAll()

        #expect(viewModel.lastRefreshHadError)

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

        var cleanBatchDone = false
        var seenLoading2 = false
        viewModel.$isLoading.sink { isLoading in
            if isLoading { seenLoading2 = true }
            if seenLoading2 && !isLoading { cleanBatchDone = true }
        }.store(in: &cancellables)

        viewModel.refresh()
        await poll(until: { cleanBatchDone }, timeout: .seconds(10), "clean batch never finished")

        #expect(!viewModel.lastRefreshHadError)
    }

    // MARK: - Request not found (404)

    /// A literal HTTP 404 on a bookmarked stop must not surface a bulletin — the
    /// stop no longer resolves. Empty HTTP 200 is a different case (see below).
    @Test @MainActor
    func `Request not found does not call display error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createSpyApplication(dataLoader: dataLoader)
        _ = try addTripBookmark(to: app)

        dataLoader.mock(data: Data(), statusCode: 404) {
            $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let viewModel = BookmarksViewModel(application: app)
        #expect(app.displayErrorCallCount == 0)

        var batchDone = false
        var seenLoading = false
        var cancellables = Set<AnyCancellable>()
        viewModel.$isLoading.sink { isLoading in
            if isLoading { seenLoading = true }
            if seenLoading && !isLoading { batchDone = true }
        }.store(in: &cancellables)

        viewModel.refresh()
        await poll(until: { batchDone }, timeout: .seconds(10), "404 batch never finished")
        cancellables.removeAll()

        #expect(app.displayErrorCallCount == 0)
        #expect(!viewModel.lastRefreshHadError)

        // 404 is a terminal empty result, not perpetual loading (#1181 review).
        let rows = viewModel.sections.flatMap(\.rows)
        let row = try #require(rows.first)
        #expect(row.hasLoadedArrivalData)
    }

    /// Non-404 fetch failures must still surface via `displayError`.
    @Test @MainActor
    func `Server error still calls display error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createSpyApplication(dataLoader: dataLoader)
        _ = try addTripBookmark(to: app)

        dataLoader.mock(data: Data(), statusCode: 500) {
            $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let viewModel = BookmarksViewModel(application: app)

        var batchDone = false
        var seenLoading = false
        var cancellables = Set<AnyCancellable>()
        viewModel.$isLoading.sink { isLoading in
            if isLoading { seenLoading = true }
            if seenLoading && !isLoading { batchDone = true }
        }.store(in: &cancellables)

        viewModel.refresh()
        await poll(until: { batchDone }, timeout: .seconds(10), "500 batch never finished")
        cancellables.removeAll()

        #expect(app.displayErrorCallCount == 1)
        #expect(viewModel.lastRefreshHadError)
    }

    /// `APIService+GetData` maps HTTP 200 + `Content-Length: 0` to
    /// `APIError.requestNotFound` as well as a literal 404. A live San Diego
    /// stop (`MTS_11589`) returns HTTP 200 with a full JSON body, so an empty
    /// 200 is a transient blip, not a missing stop — it must still bulletin.
    @Test @MainActor
    func `Empty 200 still calls display error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createSpyApplication(dataLoader: dataLoader)
        _ = try addTripBookmark(to: app)

        dataLoader.mock(data: Data(), statusCode: 200) {
            $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        #expect(app.displayErrorCallCount == 1)
        #expect(viewModel.lastRefreshHadError)
    }

    /// OBA servers that cannot 404 a missing stop answer HTTP 200 with the
    /// literal body `null`. `APIService+GetData` throws that as
    /// `invalidContentType(..., "json", "nothing")` — the copy riders see as
    /// "Expected to receive json data from the server, but we received
    /// nothing instead." Same terminal outcome as a literal 404: the stop
    /// is gone, so the Bookmarks tab must not bulletin (#1331).
    @Test @MainActor
    func `JSON null body does not call display error`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createSpyApplication(dataLoader: dataLoader)
        _ = try addTripBookmark(to: app)

        dataLoader.mock(data: Data("null".utf8), statusCode: 200) {
            $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
        }

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        #expect(app.displayErrorCallCount == 0)
        #expect(!viewModel.lastRefreshHadError)

        let rows = viewModel.sections.flatMap(\.rows)
        let row = try #require(rows.first)
        #expect(row.hasLoadedArrivalData)
    }

    /// A 404 after a successful fetch must drop the previous departures rather
    /// than leave a frozen countdown on the card.
    @Test @MainActor
    func `HTTP 404 after success clears stale departures`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createSpyApplication(dataLoader: dataLoader)
        _ = try addTripBookmark(to: app)

        dataLoader.mock(
            data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        ) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        let loaded = try #require(viewModel.sections.flatMap(\.rows).first)
        #expect(!loaded.arrivalDepartures.isEmpty)

        dataLoader.replaceMappedResponses { staging in
            stubRegions(dataLoader: staging)
            stubAgenciesWithCoverage(dataLoader: staging, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
            Fixtures.stubAllAgencyAlerts(dataLoader: staging)
            staging.mock(data: Data(), statusCode: 404) {
                $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            }
        }

        await viewModel.refreshAndWait()

        #expect(app.displayErrorCallCount == 0)
        #expect(!viewModel.lastRefreshHadError)
        let row = try #require(viewModel.sections.flatMap(\.rows).first)
        #expect(row.hasLoadedArrivalData)
        #expect(row.arrivalDepartures.isEmpty)
    }

    /// JSON `null` after a successful fetch must drop the previous departures
    /// the same way a later 404 does (#1331).
    @Test @MainActor
    func `JSON null after success clears stale departures`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let app = createSpyApplication(dataLoader: dataLoader)
        _ = try addTripBookmark(to: app)

        dataLoader.mock(
            data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_10914.json")
        ) { $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false }

        let viewModel = BookmarksViewModel(application: app)
        await viewModel.refreshAndWait()

        let loaded = try #require(viewModel.sections.flatMap(\.rows).first)
        #expect(!loaded.arrivalDepartures.isEmpty)

        dataLoader.replaceMappedResponses { staging in
            stubRegions(dataLoader: staging)
            stubAgenciesWithCoverage(dataLoader: staging, baseURL: Fixtures.pugetSoundRegion.OBABaseURL)
            Fixtures.stubAllAgencyAlerts(dataLoader: staging)
            staging.mock(data: Data("null".utf8), statusCode: 200) {
                $0.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            }
        }

        await viewModel.refreshAndWait()

        #expect(app.displayErrorCallCount == 0)
        #expect(!viewModel.lastRefreshHadError)
        let row = try #require(viewModel.sections.flatMap(\.rows).first)
        #expect(row.hasLoadedArrivalData)
        #expect(row.arrivalDepartures.isEmpty)
    }
}
