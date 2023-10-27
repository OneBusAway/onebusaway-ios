//
//  StopsTests.swift
//  OBAKitCoreTests
// 
//  Copyright © 2023 Open Transit Software Foundation.
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import MapKit
import CoreLocation
@testable import OBAKitCore

final class StopsTests: OBAKitCoreTestCase {
    let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)
    let urlString = "https://www.example.com/api/where/stops-for-location.json"

    override func setUp() async throws {
        try await super.setUp()

        dataLoader.mock(
            URLString: urlString,
            with: try Fixtures.loadData(file: "stops_for_location_seattle.json")
        )

        dataLoader.mock(
            URLString: "https://www.example.com/api/where/stop/1_29270.json",
            with: try Fixtures.loadData(file: "stop_1_29270.json")
        )
    }

    func testLoadingByCoordinate() async throws {
        try checkExpectations(try await restAPIService.getStops(coordinate: coordinate))
    }

    func testLoadingByRegion() async throws {
        let region = MKCoordinateRegion(center: self.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        try checkExpectations(try await restAPIService.getStops(region: region))
    }

    func testLoadingByID() async throws {
        let stop = try await restAPIService.getStop(id: "1_29270").entry
        XCTAssertEqual(stop.code, "29270")
        XCTAssertEqual(stop.direction, .e)
        XCTAssertEqual(stop.id, "1_29270")
        XCTAssertEqual(stop.location.coordinate.latitude, 47.619846, accuracy: 0.000001)
        XCTAssertEqual(stop.location.coordinate.longitude, -122.320473, accuracy: 0.000001)
        XCTAssertEqual(stop.locationType, .stop)
        XCTAssertEqual(stop.name, "E John St & Broadway  E")
        XCTAssertEqual(stop.routeIDs.count, 4)
        XCTAssertEqual(stop.wheelchairBoarding, .unknown)
    }

    private func checkExpectations(_ response: RESTAPIResponse<[Stop]>) throws {
        let stops = response.list
        XCTAssertEqual(stops.count, 26)

        let stop = try XCTUnwrap(stops.first)
        XCTAssertEqual(stop.code, "10914")
        XCTAssertEqual(stop.direction, .s)
        XCTAssertEqual(stop.id, "1_10914")
        XCTAssertEqual(stop.location.coordinate.latitude, 47.656422, accuracy: 0.000001)
        XCTAssertEqual(stop.location.coordinate.longitude, -122.312164, accuracy: 0.000001)
        XCTAssertEqual(stop.locationType, .stop)
        XCTAssertEqual(stop.name, "15th Ave NE & NE Campus Pkwy")
        XCTAssertEqual(stop.routeIDs.count, 12)
        XCTAssertEqual(stop.wheelchairBoarding, .unknown)
    }
}

