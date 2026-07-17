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

    override func setUp() {
        super.setUp()
        queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
    }

    override func tearDown() {
        super.tearDown()
        queue.cancelAllOperations()
    }

    @MainActor
    func test_observer_publishesStopsWhenManagerLoads() async {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)

        dataLoader.mock(data: Fixtures.loadData(file: "stops_for_location_seattle.json")) { request in
            request.url?.path.contains("/api/where/stops-for-location.json") ?? false
        }

        let observer = MapStopsObserver(mapRegionManager: application.mapRegionManager)
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

        let observer = MapStopsObserver(mapRegionManager: application.mapRegionManager)

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
    func test_observer_accumulatesStopsAcrossRegionsAndSkipsRevisits() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(mapRegionManager: application.mapRegionManager)

        let allStops = try Fixtures.loadSomeStops()
        try XCTSkipIf(allStops.count < 4, "Need at least 4 fixture stops")
        let regionA = Array(allStops.prefix(2))
        let regionB = Array(allStops.dropFirst(2).prefix(2))

        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionA)
        expect(Set(observer.stops.map(\.id))) == Set(regionA.map(\.id))

        // Panning to a new area adds its stops without dropping region A's — like
        // UIKit, which accumulates stop annotations as you pan.
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionB)
        expect(Set(observer.stops.map(\.id))) == Set((regionA + regionB).map(\.id))

        // Returning to region A adds nothing new, so the pins already on the map
        // stay put (identity preserved) — no flicker.
        let before = observer.stops
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: regionA)
        expect(observer.stops.count) == before.count
        expect(observer.stops.first) === before.first
    }

    @MainActor
    func test_reset_clearsAccumulatedStops() throws {
        let dataLoader = MockDataLoader(testName: name)
        let application = buildApplication(queue: queue, dataLoader: dataLoader)
        let observer = MapStopsObserver(mapRegionManager: application.mapRegionManager)

        let stops = try Fixtures.loadSomeStops()
        try XCTSkipIf(stops.isEmpty, "Need fixture stops")
        observer.mapRegionManager(application.mapRegionManager, stopsUpdated: stops)
        expect(observer.stops).toNot(beEmpty())

        observer.reset()
        expect(observer.stops).to(beEmpty())
    }
}
