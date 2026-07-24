//
//  MapStopsObserverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import MapKit
import Combine
import Nimble
@testable import OBAKit
@testable import OBAKitCore

final class MapStopsObserverTests: OBATestCase {

    private var queue: OperationQueue!

    override func setUp() async throws {
        try await super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() async throws {
        try await super.tearDown()
        queue.cancelAllOperations()
    }

    @MainActor
    func test_observer_publishesStopsWhenManagerLoads() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        expect(observer.stops).to(beEmpty())

        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)

        expect(observer.stops).toNot(beEmpty())
    }

    @MainActor
    func test_observer_skipsRepublishWhenStopSetUnchanged() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)

        var publishCount = 0
        let cancellable = observer.$stops.dropFirst().sink { _ in publishCount += 1 }
        defer { cancellable.cancel() }

        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )

        // First load populates the stops (one publish).
        await application.mapRegionManager.requestStops(in: region)
        let firstStops = observer.stops
        expect(firstStops).toNot(beEmpty())
        expect(publishCount) == 1

        // Re-loading the same region returns the same stop set; the observer must
        // not republish, so the SwiftUI map doesn't tear down and re-add pins.
        await application.mapRegionManager.requestStops(in: region)
        expect(publishCount) == 1
        // Stop instances are preserved (identity stable), not swapped for new decodes.
        expect(observer.stops.first) === firstStops.first
    }

    @MainActor
    func test_observer_accumulatesAcrossRegionsWithoutViewport() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(allStops.count < 4, "Need at least 4 fixture stops")
        let regionA = Array(allStops.prefix(2))
        let regionB = Array(allStops.dropFirst(2).prefix(2))

        // No updateViewport → no prune reference → the accumulator only grows.
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionA)
        expect(Set(observer.stops.map(\.id))) == Set(regionA.map(\.id))

        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionB)
        expect(Set(observer.stops.map(\.id))) == Set((regionA + regionB).map(\.id))
    }

    @MainActor
    func test_observer_preservesInstanceForRetainedID() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(allStops.count < 3, "Need at least 3 fixture stops")
        let first = Array(allStops.prefix(2))

        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: first)
        let retained = observer.stops.first { $0.id == first[0].id }

        // Feed an overlapping set (first[0] again + a new stop). The retained
        // stop keeps its instance so its on-screen pin isn't rebuilt.
        let overlapping = [first[0], allStops[2]]
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: overlapping)
        expect(observer.stops.first { $0.id == first[0].id }) === retained
    }

    @MainActor
    func test_reset_clearsStops() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let stops = try Fixtures.loadSomeStops()
        try XCTSkipIf(stops.isEmpty, "Need fixture stops")
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: stops)
        expect(observer.stops).toNot(beEmpty())

        observer.reset()
        expect(observer.stops).to(beEmpty())
    }

    /// Squared planar distance with longitude scaled by `cos(latitude)` —
    /// mirrors `MapStopsObserver.squaredDistance` so the test's "nearest N"
    /// ordering matches the count-cap eviction under review. Ordering only.
    private func squaredDistance(_ stop: Stop, to center: CLLocationCoordinate2D) -> Double {
        let dLat = stop.coordinate.latitude - center.latitude
        let dLon = (stop.coordinate.longitude - center.longitude) * cos(center.latitude * .pi / 180)
        return dLat * dLat + dLon * dLon
    }

    @MainActor
    func test_observer_evictsStopsBeyondPruneRadius() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(allStops.count < 3, "Need fixture stops")
        let anchor = try XCTUnwrap(allStops.first)
        let farStop = try XCTUnwrap(
            allStops.max { squaredDistance($0, to: anchor.coordinate) < squaredDistance($1, to: anchor.coordinate) }
        )
        try XCTSkipIf(farStop.id == anchor.id, "Need two fixture stops at distinct coordinates")

        // A tiny viewport at the anchor → 4× band is far smaller than the
        // fixture's spread, so the farthest stop is outside it.
        let tiny = 0.0005
        observer.updateViewport(
            MKCoordinateRegion(
                center: anchor.coordinate,
                span: MKCoordinateSpan(latitudeDelta: tiny, longitudeDelta: tiny)
            )
        )
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: allStops)

        expect(observer.stops.map(\.id)).to(contain(anchor.id))
        expect(observer.stops.map(\.id)).toNot(contain(farStop.id))
        expect(observer.stops.count) < allStops.count
    }

    @MainActor
    func test_observer_evictsFarthestBeyondRenderCap() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        // Cap of 3 so the fixture set (26) exceeds it.
        let observer = MapStopsObserver(application: application, renderCap: 3)

        let allStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(allStops.count <= 3, "Need more fixture stops than the cap")
        let anchor = try XCTUnwrap(allStops.first)

        // A wide viewport so the distance band keeps everything — only the cap
        // evicts, dropping the farthest from the anchor.
        observer.updateViewport(
            MKCoordinateRegion(
                center: anchor.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        )
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: allStops)

        expect(observer.stops.count) == 3
        // The three nearest to the anchor survive (anchor itself is nearest).
        expect(observer.stops.map(\.id)).to(contain(anchor.id))
        let nearest3 = allStops
            .sorted { squaredDistance($0, to: anchor.coordinate) < squaredDistance($1, to: anchor.coordinate) }
            .prefix(3)
            .map(\.id)
        expect(Set(observer.stops.map(\.id))) == Set(nearest3)
    }

    /// Panning to a far area emits no `stopsUpdated` (the manager publishes no
    /// empty set), so pruning must run on the viewport change alone — otherwise
    /// the previous area's pins linger outside the bound.
    @MainActor
    func test_updateViewport_prunesFarStopsWithoutNewStopsUpdate() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(allStops.isEmpty, "Need fixture stops")
        let anchor = try XCTUnwrap(allStops.first)

        // Accumulate the fixtures under a viewport that contains them.
        observer.updateViewport(
            MKCoordinateRegion(
                center: anchor.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        )
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: allStops)
        expect(observer.stops).toNot(beEmpty())

        // Pan ~10° away with a tight viewport and NO new stopsUpdated. The
        // prune must run on the viewport change and evict the now-far pins.
        let farCenter = CLLocationCoordinate2D(
            latitude: anchor.coordinate.latitude + 10,
            longitude: anchor.coordinate.longitude + 10
        )
        observer.updateViewport(
            MKCoordinateRegion(
                center: farCenter,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        )
        expect(observer.stops).to(beEmpty())
    }

    // MARK: - Bookmarks

    @MainActor
    func test_observer_publishesBookmarksAndReloadsOnChange() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let stops = try Fixtures.loadSomeStops()
        try XCTSkipIf(stops.count < 2, "Need at least 2 fixture stops")
        let regionID = try XCTUnwrap(application.currentRegion?.regionIdentifier)

        // A bookmark saved before the observer exists is seeded at init.
        let seeded = Bookmark(name: "Seeded", regionIdentifier: regionID, stop: stops[0])
        application.userDataStore.add(seeded, to: nil)

        let observer = MapStopsObserver(application: application)
        expect(observer.bookmarks.map(\.stopID)) == [stops[0].id]
        expect(observer.bookmarkedStopIDs) == [stops[0].id]

        // Adding a bookmark posts `.bookmarksDidChange`; the observer reloads via
        // a main-actor hop, so yield to let it land.
        let added = Bookmark(name: "Added", regionIdentifier: regionID, stop: stops[1])
        application.userDataStore.add(added, to: nil)
        for _ in 0..<5 { await Task.yield() }
        expect(observer.bookmarkedStopIDs) == [stops[0].id, stops[1].id]

        // Deleting one removes it from the published set.
        application.userDataStore.delete(bookmark: added)
        for _ in 0..<5 { await Task.yield() }
        expect(observer.bookmarkedStopIDs) == [stops[0].id]
    }

    @MainActor
    func test_observer_dedupesBookmarksByStop() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let stops = try Fixtures.loadSomeStops()
        try XCTSkipIf(stops.isEmpty, "Need fixture stops")
        let regionID = try XCTUnwrap(application.currentRegion?.regionIdentifier)

        // Two bookmarks for the same stop must yield one annotation; the last
        // one wins, matching the UIKit path's `bookmarksHash`.
        application.userDataStore.add(Bookmark(name: "First", regionIdentifier: regionID, stop: stops[0]), to: nil)
        application.userDataStore.add(Bookmark(name: "Second", regionIdentifier: regionID, stop: stops[0]), to: nil)

        let observer = MapStopsObserver(application: application)
        expect(observer.bookmarks).to(haveCount(1))
        expect(observer.bookmarks.first?.name) == "Second"
    }
}
