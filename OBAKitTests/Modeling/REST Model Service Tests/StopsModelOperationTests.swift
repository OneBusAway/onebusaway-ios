//
//  StopsModelOperationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_cast

@Suite(.serialized)
final class StopsModelOperationTests: OBATestCase {
    let coordinate = CLLocationCoordinate2D(latitude: 47.6230999, longitude: -122.3132122)
    let urlString = "https://www.example.com/api/where/stops-for-location.json"

    var dataLoader: MockDataLoader!

    override init() async throws {
        try await super.init()

        dataLoader = (restService.dataLoader as! MockDataLoader)
    }

    func stubApiCall() {
        dataLoader.mock(
            URLString: urlString,
            with: Fixtures.loadData(file: "stops_for_location_seattle.json")
        )

        dataLoader.mock(
            URLString: "https://www.example.com/api/where/stop/1_29270.json",
            with: Fixtures.loadData(file: "stop_1_29270.json")
        )
    }

    func checkExpectations(_ response: RESTAPIResponse<[Stop]>) {
        let stops = response.list

        #expect(stops.count == 26)

        let stop = stops.first!

        #expect(stop.code == "10914")
        #expect(stop.direction == .s)
        #expect(stop.id == "1_10914")
        expectClose(stop.location.coordinate.latitude, 47.656422)
        expectClose(stop.location.coordinate.longitude, -122.312164)
        #expect(stop.locationType == .stop)
        #expect(stop.name == "15th Ave NE & NE Campus Pkwy")
        #expect(stop.routes.count == 12)
        #expect(stop.routes.first!.id == "1_100059")  // Test that routes get sorted by ID.
        #expect(stop.wheelchairBoarding == .unknown)
        #expect(stop.regionIdentifier == pugetSoundRegionIdentifier)
    }

    @Test func `Loading coordinate success`() async throws {
        stubApiCall()

        self.checkExpectations(try await restService.getStops(coordinate: coordinate))
    }

    @Test func `Loading region success`() async throws {
        stubApiCall()

        let region = MKCoordinateRegion(center: self.coordinate, span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        self.checkExpectations(try await restService.getStops(region: region))
    }

    @Test func `Loading circular region success`() async throws {
        stubApiCall()

        let circularRegion = CLCircularRegion(center: self.coordinate, radius: 100.0, identifier: "query")
        self.checkExpectations(try await restService.getStops(circularRegion: circularRegion, query: "query"))
    }

    @Test func `Loading specific ID success`() async throws {
        stubApiCall()

        let stop = try await restService.getStop(id: "1_29270").entry
        #expect(stop.code == "29270")
        #expect(stop.direction == .e)
        #expect(stop.id == "1_29270")
        expectClose(stop.location.coordinate.latitude, 47.619846)
        expectClose(stop.location.coordinate.longitude, -122.320473)
        #expect(stop.locationType == .stop)
        #expect(stop.name == "E John St & Broadway  E")
        #expect(stop.routes.count == 4)
        // Test that routes get sorted by ID.
        #expect(stop.routes.map(\.id) == [
            "1_100002",
            "1_100223",
            "1_100275",
            "1_102650"
        ])
        #expect(stop.wheelchairBoarding == .unknown)
        #expect(stop.regionIdentifier == pugetSoundRegionIdentifier)

    }
}
