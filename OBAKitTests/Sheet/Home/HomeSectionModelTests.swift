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

    @MainActor
    private func seedBookmarks(count: Int, application: Application) throws -> [Bookmark] {
        let stops = try Fixtures.loadSomeStops()
        // sortOrder is assigned in reverse so the test proves the model sorts
        // rather than accidentally matching insertion order.
        return (0..<count).map { index in
            let bookmark = Bookmark(
                name: "Bookmark \(index)",
                regionIdentifier: Fixtures.pugetSoundRegion.regionIdentifier,
                stop: stops[index % stops.count]
            )
            bookmark.sortOrder = count - index
            application.userDataStore.add(bookmark, to: nil)
            return bookmark
        }
    }

    /// The four shown are chosen by `sortOrder`, not by insertion order —
    /// `findBookmarks(in:)` returns raw persisted order, so the model must sort.
    @Test @MainActor
    func `Bookmarks section selects by sort order up to the limit`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplicationWithRegion(queue: queue, dataLoader: dataLoader)
        _ = try seedBookmarks(count: 6, application: application)

        try #require(application.currentRegion != nil)
        let model = HomeBookmarksSectionModel(application: application, limit: 4)

        #expect(model.rows.count == 4)
        let sortOrders = model.rows.map(\.bookmark.sortOrder)
        #expect(sortOrders == sortOrders.sorted())
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
}
