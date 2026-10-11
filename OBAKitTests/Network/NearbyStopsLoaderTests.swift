//
//  NearbyStopsLoaderTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class NearbyStopsLoaderTests: OBATestCase {

    private let stopsPath = "/api/where/stops-for-location.json"

    /// 15th Ave NE & NE Campus Pkwy, stop 1_10914 in the Seattle fixture.
    private let campusParkway = CLLocationCoordinate2D(latitude: 47.656422, longitude: -122.312164)

    private func mockStops(_ dataLoader: MockDataLoader, fixture: String = "stops_for_location_seattle.json", statusCode: Int = 200) {
        dataLoader.mock(data: Fixtures.loadData(file: fixture), statusCode: statusCode) { [stopsPath] request in
            request.url?.path.contains(stopsPath) ?? false
        }
    }

    @Test func `Stops come back sorted by distance from the coordinate`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)
        let service = buildRESTService(dataLoader: dataLoader)

        let stops = try await NearbyStopsLoader().stops(near: campusParkway, using: service)

        #expect(stops.first?.id == "1_10914")
        let origin = CLLocation(latitude: campusParkway.latitude, longitude: campusParkway.longitude)
        let distances = stops.map { $0.location.distance(from: origin) }
        #expect(distances == distances.sorted())
    }

    @Test func `The list is capped at the limit`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader)
        let service = buildRESTService(dataLoader: dataLoader)

        #expect(try await NearbyStopsLoader().stops(near: campusParkway, using: service).count == 20)
        #expect(try await NearbyStopsLoader(limit: 5).stops(near: campusParkway, using: service).count == 5)
    }

    @Test func `An empty response is an empty list`() async throws {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader, fixture: "stops_for_location_queryfail.json")
        let service = buildRESTService(dataLoader: dataLoader)

        let stops = try await NearbyStopsLoader().stops(near: campusParkway, using: service)

        #expect(stops.isEmpty)
    }

    @Test func `A server error propagates`() async {
        let dataLoader = MockDataLoader(testName: name)
        mockStops(dataLoader, statusCode: 500)
        let service = buildRESTService(dataLoader: dataLoader)

        await #expect(throws: (any Error).self) {
            _ = try await NearbyStopsLoader().stops(near: campusParkway, using: service)
        }
    }
}
