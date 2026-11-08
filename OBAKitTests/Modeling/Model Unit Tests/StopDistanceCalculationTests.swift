//
//  StopDistanceCalculationTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

@Suite(.serialized)
final class StopDistanceCalculationTests {

    private func makeStop(id: String, latitude: Double, longitude: Double) throws -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "name": "Stop \(id)",
            "lat": latitude,
            "lon": longitude,
            "locationType": 0,
            "routeIds": ["1_10"]
        ]
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dict)
    }

    @Test func `squaredDistance orders by proximity correctly`() throws {
        let center = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)

        // Stop A: Very close (0.001 deg north)
        let stopClose = try makeStop(id: "close", latitude: 47.6072, longitude: -122.3321)

        // Stop B: Further away (0.01 deg north)
        let stopFar = try makeStop(id: "far", latitude: 47.6162, longitude: -122.3321)

        let dClose = Stop.squaredDistance(stopClose, to: center)
        let dFar = Stop.squaredDistance(stopFar, to: center)

        #expect(dClose < dFar)
    }

    @Test func `squaredDistance scales longitude delta by cosine of latitude`() throws {
        // High latitude: 60 degrees N (cos(60 deg) = 0.5)
        let center = CLLocationCoordinate2D(latitude: 60.0, longitude: 0.0)

        // 1 degree latitude delta vs 1 degree longitude delta
        // dLat^2 = 1.0
        // dLon^2 * cos(60)^2 = 1.0 * 0.25 = 0.25
        let stopNorth = try makeStop(id: "north", latitude: 61.0, longitude: 0.0)
        let stopEast = try makeStop(id: "east", latitude: 60.0, longitude: 1.0)

        let dNorth = Stop.squaredDistance(stopNorth, to: center)
        let dEast = Stop.squaredDistance(stopEast, to: center)

        expectClose(dNorth, 1.0, within: 0.0001)
        expectClose(dEast, 0.25, within: 0.0001)
        #expect(dEast < dNorth)
    }

    @Test func `nearest returns stops in closest first order limited to count`() throws {
        let center = CLLocationCoordinate2D(latitude: 47.6000, longitude: -122.3300)

        let s1 = try makeStop(id: "s1", latitude: 47.6005, longitude: -122.3300) // ~55m
        let s2 = try makeStop(id: "s2", latitude: 47.6020, longitude: -122.3300) // ~220m
        let s3 = try makeStop(id: "s3", latitude: 47.6050, longitude: -122.3300) // ~550m
        let s4 = try makeStop(id: "s4", latitude: 47.6100, longitude: -122.3300) // ~1100m

        let unsorted = [s4, s2, s1, s3]

        let top2 = Stop.nearest(unsorted, to: center, limit: 2)
        #expect(top2.count == 2)
        #expect(top2.map(\.id) == ["s1", "s2"])

        let top3 = Stop.nearest(unsorted, to: center, limit: 3)
        #expect(top3.count == 3)
        #expect(top3.map(\.id) == ["s1", "s2", "s3"])
    }

    @Test func `nearest with non-positive limit returns empty list`() throws {
        let center = CLLocationCoordinate2D(latitude: 47.6000, longitude: -122.3300)
        let s1 = try makeStop(id: "s1", latitude: 47.6005, longitude: -122.3300)

        #expect(Stop.nearest([s1], to: center, limit: 0).isEmpty)
        #expect(Stop.nearest([s1], to: center, limit: -5).isEmpty)
    }

    @Test func `nearest with empty list returns empty list`() {
        let center = CLLocationCoordinate2D(latitude: 47.6000, longitude: -122.3300)
        #expect(Stop.nearest([], to: center, limit: 5).isEmpty)
    }
}
