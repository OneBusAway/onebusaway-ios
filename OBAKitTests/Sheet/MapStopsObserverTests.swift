//
//  MapStopsObserverTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import MapKit
import Combine
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class MapStopsObserverTests: OBATestCase {

    private var queue: OperationQueue!

    override init() async throws {
        try await super.init()

        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    isolated deinit {
        queue.cancelAllOperations()
    }

    @Test func `Observer publishes stops when the manager loads`() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        // The stop cache is a shared file that outlives the test bundle; clear
        // it so this test's stops come from its own mocked fetch.
        clearStopCache(for: application)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(application: application)
        #expect(observer.stops.isEmpty)

        let region = MKCoordinateRegion(
            center: TestData.mockSeattleLocation.coordinate,
            latitudinalMeters: 5000,
            longitudinalMeters: 5000
        )
        await application.mapRegionManager.requestStops(in: region)

        #expect(!observer.stops.isEmpty)
    }

    @Test func `Observer skips republish when the stop set is unchanged`() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        // Both loads below must see the same cache state, so the publish count
        // reflects the observer's dedupe and not leftover rows from elsewhere.
        clearStopCache(for: application)

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
        #expect(!firstStops.isEmpty)
        #expect(publishCount == 1)

        // Re-loading the same region returns the same stop set; the observer must
        // not republish, so the SwiftUI map doesn't tear down and re-add pins.
        await application.mapRegionManager.requestStops(in: region)
        #expect(publishCount == 1)
        // Stop instances are preserved (identity stable), not swapped for new decodes.
        #expect(observer.stops.first === firstStops.first)
    }

    @Test func `Observer accumulates across regions without a viewport`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try #require(allStops.count >= 4, "Need at least 4 fixture stops")
        let regionA = Array(allStops.prefix(2))
        let regionB = Array(allStops.dropFirst(2).prefix(2))

        // No updateViewport → no prune reference → the accumulator only grows.
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionA)
        #expect(Set(observer.stops.map(\.id)) == Set(regionA.map(\.id)))

        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionB)
        #expect(Set(observer.stops.map(\.id)) == Set((regionA + regionB).map(\.id)))
    }

    @Test func `Observer preserves the instance for a retained ID`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try #require(allStops.count >= 3, "Need at least 3 fixture stops")
        let first = Array(allStops.prefix(2))

        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: first)
        let retained = observer.stops.first { $0.id == first[0].id }

        // Feed an overlapping set (first[0] again + a new stop). The retained
        // stop keeps its instance so its on-screen pin isn't rebuilt.
        let overlapping = [first[0], allStops[2]]
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: overlapping)
        #expect(observer.stops.first { $0.id == first[0].id } === retained)
    }

    @Test func `Reset clears stops`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let stops = try Fixtures.loadSomeStops()
        try #require(!stops.isEmpty, "Need fixture stops")
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: stops)
        #expect(!observer.stops.isEmpty)

        observer.reset()
        #expect(observer.stops.isEmpty)
    }

    @Test func `Observer evicts stops beyond the prune radius`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try #require(allStops.count >= 3, "Need fixture stops")
        let anchor = try #require(allStops.first)
        let farStop = try #require(
            allStops.max {
                observer.squaredDistance($0, to: anchor.coordinate) < observer.squaredDistance($1, to: anchor.coordinate)
            }
        )
        try #require(farStop.id != anchor.id, "Need two fixture stops at distinct coordinates")

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

        #expect(observer.stops.map(\.id).contains(anchor.id))
        #expect(!observer.stops.map(\.id).contains(farStop.id))
        #expect(observer.stops.count < allStops.count)
    }

    @Test func `Observer evicts the farthest stops beyond the render cap`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        // Cap of 3 so the fixture set (26) exceeds it.
        let observer = MapStopsObserver(application: application, renderCap: 3)

        let allStops = try Fixtures.loadSomeStops()
        try #require(allStops.count > 3, "Need more fixture stops than the cap")
        let anchor = try #require(allStops.first)

        // A wide viewport so the distance band keeps everything — only the cap
        // evicts, dropping the farthest from the anchor.
        observer.updateViewport(
            MKCoordinateRegion(
                center: anchor.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        )
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: allStops)

        #expect(observer.stops.count == 3)
        // The three nearest to the anchor survive (anchor itself is nearest).
        #expect(observer.stops.map(\.id).contains(anchor.id))
        let nearest3 = allStops
            .sorted {
                observer.squaredDistance($0, to: anchor.coordinate) < observer.squaredDistance($1, to: anchor.coordinate)
            }
            .prefix(3)
            .map(\.id)
        #expect(Set(observer.stops.map(\.id)) == Set(nearest3))
    }

    /// Panning to a far area emits no `stopsUpdated` (the manager publishes no
    /// empty set), so pruning must run on the viewport change alone — otherwise
    /// the previous area's pins linger outside the bound.
    @Test func `Update viewport prunes far stops without a new stops update`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(application: application)

        let allStops = try Fixtures.loadSomeStops()
        try #require(!allStops.isEmpty, "Need fixture stops")
        let anchor = try #require(allStops.first)

        // Accumulate the fixtures under a viewport that contains them.
        observer.updateViewport(
            MKCoordinateRegion(
                center: anchor.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        )
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: allStops)
        #expect(!observer.stops.isEmpty)

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
        #expect(observer.stops.isEmpty)
    }

    // MARK: - Bookmarks

    @Test func `Observer publishes bookmarks and reloads on change`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let stops = try Fixtures.loadSomeStops()
        try #require(stops.count >= 2, "Need at least 2 fixture stops")
        let regionID = try #require(application.currentRegion?.regionIdentifier)

        // A bookmark saved before the observer exists is seeded at init.
        let seeded = Bookmark(name: "Seeded", regionIdentifier: regionID, stop: stops[0])
        application.userDataStore.add(seeded, to: nil)

        let observer = MapStopsObserver(application: application)
        #expect(observer.bookmarks.map(\.stopID) == [stops[0].id])
        #expect(observer.bookmarkedStopIDs == [stops[0].id])

        // Adding a bookmark posts `.bookmarksDidChange`, delivered on an
        // unspecified queue, and the observer reloads through a main-actor hop.
        // Poll rather than yielding a fixed number of times — the latter is a
        // timing assumption, not a synchronization point.
        let added = Bookmark(name: "Added", regionIdentifier: regionID, stop: stops[1])
        application.userDataStore.add(added, to: nil)
        await poll(
            until: { observer.bookmarkedStopIDs == [stops[0].id, stops[1].id] },
            "the added bookmark never reached bookmarkedStopIDs"
        )
        #expect(observer.bookmarkedStopIDs == [stops[0].id, stops[1].id])

        // Deleting one removes it from the published set.
        application.userDataStore.delete(bookmark: added)
        await poll(
            until: { observer.bookmarkedStopIDs == [stops[0].id] },
            "the deleted bookmark was never removed from bookmarkedStopIDs"
        )
        #expect(observer.bookmarkedStopIDs == [stops[0].id])
    }

    @Test func `Observer dedupes bookmarks by stop`() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        let stops = try Fixtures.loadSomeStops()
        try #require(!stops.isEmpty, "Need fixture stops")
        let regionID = try #require(application.currentRegion?.regionIdentifier)

        // Two bookmarks for the same stop must yield one annotation; the last
        // one wins, matching the UIKit path's `bookmarksHash`.
        application.userDataStore.add(Bookmark(name: "First", regionIdentifier: regionID, stop: stops[0]), to: nil)
        application.userDataStore.add(Bookmark(name: "Second", regionIdentifier: regionID, stop: stops[0]), to: nil)

        let observer = MapStopsObserver(application: application)
        #expect(observer.bookmarks.count == 1)
        #expect(observer.bookmarks.first?.name == "Second")
    }
}
