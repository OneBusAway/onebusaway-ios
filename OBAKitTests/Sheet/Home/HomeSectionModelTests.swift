//
//  HomeSectionModelTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class HomeSectionModelTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    // MARK: - Helpers

    private func buildApplicationWithRegion(queue: OperationQueue, dataLoader: MockDataLoader) -> Application {
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

    // MARK: - Nearby

    /// The section caps at its limit and orders by the observer's viewport center.
    @Test @MainActor
    func `Nearby section publishes the nearest stops up to the limit`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        observer.updateViewport(region)

        let model = HomeNearbyStopsSectionModel(observer: observer, limit: 4)

        #expect(model.stops.count == 4)
        let expected = Stop.nearest(observer.stops, to: region.center, limit: 4).map(\.id)
        #expect(model.stops.map(\.id) == expected)
    }

    /// Zooming out resets the observer, and the section empties with it.
    @Test @MainActor
    func `Nearby section empties when the observer resets`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        observer.updateViewport(region)

        let model = HomeNearbyStopsSectionModel(observer: observer, limit: 4)
        #expect(!model.stops.isEmpty)

        observer.reset()

        #expect(model.stops.isEmpty)
    }

    /// Before the first settle there is no center to sort by, so the section
    /// shows the observer's own ordering rather than nothing at all.
    @Test @MainActor
    func `Nearby section falls back to observer order before the first settle`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)
        // Deliberately no updateViewport — viewportCenter stays nil.

        let model = HomeNearbyStopsSectionModel(observer: observer, limit: 4)

        #expect(model.stops.map(\.id) == observer.stops.prefix(4).map(\.id))
    }

    // MARK: - Recent

    /// The section caps at its limit and preserves the store's MRU ordering.
    @Test @MainActor
    func `Recent section caps at the limit in most recently used order`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        // Added oldest-first; the store inserts each at index 0, so the last
        // one added is the first one out.
        for stop in stops.prefix(6) {
            // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
            // fixture stops bypass that path, so we assign it here to match production state.
            stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }

        try #require(application.currentRegion != nil)
        try #require(!application.userDataStore.recentStops(in: application.currentRegion).isEmpty)
        let model = HomeRecentStopsSectionModel(application: application, limit: 4)

        #expect(model.stops.count == 4)
        let expected = application.userDataStore
            .recentStops(in: application.currentRegion)
            .prefix(4)
            .map(\.id)
        #expect(model.stops.map(\.id) == Array(expected))
    }

    /// `reload()` picks up a stop added after construction.
    @Test @MainActor
    func `Recent section reload picks up newly added stops`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        try #require(application.currentRegion != nil)
        let model = HomeRecentStopsSectionModel(application: application, limit: 4)
        #expect(model.stops.isEmpty)

        let stop = try #require(stops.first)
        // Production stops receive regionIdentifier from RESTAPIResponse.loadReferences;
        // fixture stops bypass that path, so we assign it here to match production state.
        stop.regionIdentifier = Fixtures.pugetSoundRegion.regionIdentifier
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        try #require(!application.userDataStore.recentStops(in: application.currentRegion).isEmpty)
        model.reload()

        #expect(model.stops.map(\.id) == [stop.id])
    }

    // MARK: - Bookmarks

    /// A fixed clock for creation dates. Bookmarks seeded later get later dates,
    /// so "newest" is a property of the test rather than of how fast it runs —
    /// `Date()` inside a loop can land several bookmarks on the same instant.
    private static let seedEpoch = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor
    private func seedBookmarks(count: Int, application: Application, startingAt offset: Int = 0) throws -> [Bookmark] {
        let stops = try Fixtures.loadSomeStops()
        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(offset + index)",
                regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
                stop: stops[(offset + index) % stops.count],
                // One minute apart, ascending: the last one seeded is the newest.
                dateCreated: Self.seedEpoch.addingTimeInterval(Double(offset + index) * 60)
            )
            // Deliberately the inverse of creation order, so a test that passes
            // can't be passing because the two happen to agree.
            bookmark.sortOrder = count - index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// Thread-safe counter — `MockDataLoader` matches requests off the main actor.
    private final class RequestCounter {
        private let lock = NSLock()
        nonisolated(unsafe) private(set) var count: Int = 0

        nonisolated func increment() {
            lock.lock()
            defer { lock.unlock() }
            count += 1
        }
    }

    /// Real *trip* bookmarks. `BookmarkDataLoader` skips anything that isn't one
    /// without issuing a request, so the stop bookmarks `seedBookmarks` builds
    /// would silently zero out any request-count assertion.
    @MainActor
    private func makeTripBookmarks(count: Int, application: Application, startingAt offset: Int = 0) throws -> [Bookmark] {
        let stopArrivals = try Fixtures.loadRESTAPIPayload(
            type: StopArrivals.self,
            fileName: "arrivals-and-departures-for-stop-1_10914.json"
        )
        let arrivalDeparture = try #require(stopArrivals.arrivalsAndDepartures.first)

        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Trip Bookmark \(offset + index)",
                regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
                arrivalDeparture: arrivalDeparture,
                dateCreated: Self.seedEpoch.addingTimeInterval(Double(offset + index) * 60)
            )
            bookmark.sortOrder = offset + index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// The preview shows the `limit` most recently created bookmarks, newest
    /// first — not the first `limit` of the user's manual order.
    ///
    /// `seedBookmarks` assigns `sortOrder` as the inverse of creation order, so
    /// this can't pass by the two agreeing.
    @Test @MainActor
    func `Bookmarks section shows the most recently created first`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let seeded = try seedBookmarks(count: 6, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        #expect(model.rows.count == 4)
        // Bookmarks 5, 4, 3, 2 — the four newest, newest first.
        let expected = seeded.suffix(4).reversed().map(\.id)
        #expect(model.rows.map(\.bookmark.id) == Array(expected))
    }

    /// The whole point of the change: a bookmark created *after* the preview is
    /// already full still shows up, because it's newest — under the old
    /// `sortOrder` ascending rule it was appended last and fell past the cut.
    @Test @MainActor
    func `A newly created bookmark enters an already full preview`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 4, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        try #require(model.rows.count == 4)

        let newest = try #require(try seedBookmarks(count: 1, application: application, startingAt: 9).first)
        model.refreshSelection()

        #expect(model.rows.first?.bookmark.id == newest.id)
        #expect(model.rows.count == 4)
    }

    /// Pinned bookmarks lead, then the newest unpinned fill up to the limit.
    @Test @MainActor
    func `Pinned bookmarks come first and unpinned fill the rest`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let seeded = try seedBookmarks(count: 6, application: application)

        // Pin the two *oldest*, which newest-first would otherwise never show.
        let pinned = Array(seeded.prefix(2))
        for bookmark in pinned {
            application.userDataStore.setPinned(true, for: bookmark)
        }

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        #expect(model.rows.count == 4)
        // Pins first, newest pin first among them.
        #expect(model.rows.prefix(2).map(\.bookmark.id) == pinned.reversed().map(\.id))
        #expect(model.rows.prefix(2).map(\.isPinned) == [true, true])
        // Then the two newest unpinned.
        #expect(model.rows.dropFirst(2).map(\.bookmark.id) == seeded.suffix(2).reversed().map(\.id))
    }

    /// `limit` is a floor, not a cap: pin more than it and every pin still shows.
    @Test @MainActor
    func `More pinned than the limit shows all of them`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let seeded = try seedBookmarks(count: 8, application: application)

        let pinned = Array(seeded.prefix(6))
        for bookmark in pinned {
            application.userDataStore.setPinned(true, for: bookmark)
        }

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        // All six pins, and no unpinned — the limit is already exceeded.
        #expect(model.rows.count == 6)
        #expect(model.rows.map(\.isPinned) == Array(repeating: true, count: 6))
        #expect(Set(model.rows.map(\.bookmark.id)) == Set(pinned.map(\.id)))
    }

    /// Pinning from the row reorders the section without anyone calling reload —
    /// the store posts `.bookmarksDidChange` and the model is already listening.
    @Test @MainActor
    func `Toggling a pin reorders the section through the notification`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let seeded = try seedBookmarks(count: 6, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        // The oldest starts out below the cut.
        let oldest = try #require(seeded.first)
        try #require(!model.rows.contains { $0.bookmark.id == oldest.id })

        model.togglePin(oldest)

        await poll(
            until: { model.rows.first?.bookmark.id == oldest.id },
            "Pinning did not move the bookmark to the top of the section"
        )
        #expect(model.rows.first?.isPinned == true)
    }

    /// Bookmarks stored before `dateCreated` existed all decode as `.distantPast`.
    /// Among those the user's manual order is the only signal left, so the tie
    /// break is `sortOrder` ascending — not reversed along with the dates.
    @Test @MainActor
    func `Legacy bookmarks without a creation date keep their manual order`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        // `.distantPast` for every one, as a pre-`dateCreated` decode produces.
        let legacy = (0..<3).map { index -> Bookmark in
            let bookmark = Bookmark(
                name: "Legacy \(index)",
                regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
                stop: stops[index % stops.count],
                dateCreated: .distantPast
            )
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        let sortOrders = model.rows.map(\.bookmark.sortOrder)
        #expect(sortOrders == sortOrders.sorted(), "Same-date bookmarks must stay in manual order")
        #expect(model.rows.map(\.bookmark.id) == legacy.map(\.id))
    }

    /// Whole-stop bookmarks have no trip to fetch, so they never report as
    /// having loaded arrival data and never carry departures.
    @Test @MainActor
    func `Bookmarks section leaves stop bookmarks without arrival data`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        for row in model.rows {
            #expect(row.isTripBookmark == false)
            #expect(row.arrivalDepartures.isEmpty)
            #expect(row.hasLoadedArrivalData == false)
        }
    }

    /// A second activation inside the staleness window does not re-fetch.
    @Test @MainActor
    func `Bookmarks section skips a repeat load inside the staleness window`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()

        #expect(model.loadIfNeeded(now: start, staleAfter: 30))
        #expect(model.loadIfNeeded(now: start.addingTimeInterval(5), staleAfter: 30) == false)
    }

    /// Once the window lapses, the next activation re-fetches.
    @Test @MainActor
    func `Bookmarks section reloads after the staleness window lapses`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()

        #expect(model.loadIfNeeded(now: start, staleAfter: 30))
        #expect(model.loadIfNeeded(now: start.addingTimeInterval(31), staleAfter: 30))
    }

    /// A changed selection re-fetches even inside the staleness window —
    /// otherwise a newly added bookmark would show blank until the window lapsed.
    @Test @MainActor
    func `Bookmarks section reloads when the selection changes`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()
        #expect(model.loadIfNeeded(now: start, staleAfter: 30))

        _ = try seedBookmarks(count: 1, application: application)

        #expect(model.loadIfNeeded(now: start.addingTimeInterval(1), staleAfter: 30))
    }

    /// A newly added bookmark reaches the section without anyone re-activating
    /// the sheet.
    ///
    /// `UserDefaultsStore.add(_:to:)` posts `.bookmarksDidChange` itself, so
    /// seeding is the trigger — the test doesn't synthesize the notification.
    /// That matters now that the model observes `object: application.userDataStore`
    /// rather than `object: nil`: a hand-rolled global post wouldn't reach it, and
    /// wouldn't be exercising the real path either. Delivery hops to the main
    /// actor, so poll rather than assert immediately.
    @Test @MainActor
    func `Bookmarks section updates when bookmarks did change notification is posted`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 2, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let initialRowCount = model.rows.count
        #expect(initialRowCount == 2)

        _ = try seedBookmarks(count: 1, application: application, startingAt: 2)

        await poll(until: {
            model.rows.count == initialRowCount + 1
        }, "Bookmarks section did not pick up the newly added bookmark after notification")

        #expect(model.rows.count == 3)
    }

    /// Bookmarking a stop while the home sheet is open has to *fetch arrivals*
    /// for the new bookmark, not just add a blank row.
    ///
    /// Regression test. `bookmarksDidChange()` used to call `refreshSelection()`
    /// before `loadIfNeeded()`, which advanced `selection` ahead of the snapshot
    /// `loadIfNeeded()` compares against — so `selectionChanged` was always false
    /// on this path and a bookmark added inside the 30-second staleness window
    /// never got a fetch. Counting requests is what pins it: the row count test
    /// above passes either way, because `refreshSelection()` rebuilds rows on its
    /// own.
    @Test @MainActor
    func `Bookmarks section fetches arrivals for a bookmark added while active`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)

        let requestCounter = RequestCounter()
        dataLoader.mock(data: Fixtures.loadData(file: "arrivals-and-departures-for-stop-1_75414.json")) { request in
            let matches = request.url?.path.contains("/api/where/arrivals-and-departures-for-stop") ?? false
            if matches { requestCounter.increment() }
            return matches
        }

        _ = try makeTripBookmarks(count: 2, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        #expect(model.loadIfNeeded())
        await poll(until: { requestCounter.count == 2 }, "Initial activation did not fetch both bookmarks")

        // A third bookmark arrives while the sheet is up and well inside the
        // staleness window. `add(_:to:)` posts `.bookmarksDidChange`.
        _ = try makeTripBookmarks(count: 1, application: application, startingAt: 2)

        await poll(
            until: { requestCounter.count > 2 },
            "Adding a bookmark did not fetch arrivals — the notification path lost the selection change"
        )
    }

    /// A region switch re-fetches even inside the staleness window.
    ///
    /// Seeded with no bookmarks on purpose: with bookmarks present, moving region
    /// also empties the selection, so `selectionChanged` would carry the test and
    /// the region branch would never be the thing under test.
    @Test @MainActor
    func `Bookmarks section reloads when the region changes`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        // Selecting a region re-resolves agencies against the new server, and an
        // unstubbed request is a fatal error in `MockDataLoader`.
        stubAgenciesWithCoverage(dataLoader: dataLoader, baseURL: Fixtures.tampaRegion.OBABaseURL)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)
        let start = Date()

        #expect(model.loadIfNeeded(now: start, staleAfter: 30))
        #expect(model.selection.isEmpty)
        // Nothing changed, still fresh.
        #expect(model.loadIfNeeded(now: start.addingTimeInterval(1), staleAfter: 30) == false)

        application.regionsService.currentRegion = Fixtures.tampaRegion

        // Selection is still empty, so only the region branch can carry this.
        #expect(model.selection.isEmpty)
        #expect(model.loadIfNeeded(now: start.addingTimeInterval(2), staleAfter: 30))
    }
}
