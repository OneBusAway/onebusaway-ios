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
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        // Added oldest-first; the store inserts each at index 0, so the last
        // one added is the first one out.
        for stop in stops.prefix(6) {
            application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        }

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
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let stops = try Fixtures.loadSomeStops()

        let model = HomeRecentStopsSectionModel(application: application, limit: 4)
        #expect(model.stops.isEmpty)

        let stop = try #require(stops.first)
        application.userDataStore.addRecentStop(stop, region: Fixtures.pugetSoundRegion)
        model.reload()

        #expect(model.stops.map(\.id) == [stop.id])
    }
}
