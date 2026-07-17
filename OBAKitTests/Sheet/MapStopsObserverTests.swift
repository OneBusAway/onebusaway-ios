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
}
