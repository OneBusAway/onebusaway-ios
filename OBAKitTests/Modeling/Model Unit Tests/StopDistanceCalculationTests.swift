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

/// Tests for `Stop.squaredDistance(_:to:)` and `Stop.nearest(_:to:limit:)` spatial metric algorithms.
///
/// Verifies longitude cosine-scaling at different latitudes, identical coordinate zeroes,
/// negative or zero limit guards, and nearest neighbor ranking order.
@Suite(.serialized)
final class StopDistanceCalculationTests: OBATestCase {

    private func makeStop(id: String, latitude: Double, longitude: Double) throws -> Stop {
        let dict: [String: Any] = [
            "id": id,
            "name": "Stop \(id)",
            "lat": latitude,
            "lon": longitude,
            "direction": "N",
            "code": "100",
            "locationType": 0,
            "routeIds": ["1_10"],
            "staticRouteIds": ["1_10"],
            "wheelchairBoarding": "UNKNOWN"
        ]
        return try Fixtures.dictionaryToModel(type: Stop.self, dictionary: dict)
    }

    // MARK: - squaredDistance

    @Test func `squaredDistance returns zero for stop at identical coordinate`() throws {
        let center = CLLocationCoordinate2D(latitude: 47.6062, longitude: -122.3321)
        let stop = try makeStop(id: "same_point", latitude: center.latitude, longitude: center.longitude)

        let distance = Stop.squaredDistance(stop, to: center)
        #expect(abs(distance - 0.0) < 0.0000001)
    }

    @Test func `squaredDistance scales longitude with cosine of latitude`() throws {
        // At equator (lat = 0), cos(0) == 1, so 1 degree lon == 1 degree lat
        let equatorCenter = CLLocationCoordinate2D(latitude: 0.0, longitude: 0.0)
        let stopEquatorLat = try makeStop(id: "eq_lat", latitude: 1.0, longitude: 0.0)
        let stopEquatorLon = try makeStop(id: "eq_lon", latitude: 0.0, longitude: 1.0)

        let dLat = Stop.squaredDistance(stopEquatorLat, to: equatorCenter)
        let dLon = Stop.squaredDistance(stopEquatorLon, to: equatorCenter)
        #expect(abs(dLat - dLon) < 0.0001)

        // At latitude 60 degrees, cos(60 deg) == 0.5, so lon difference is halved before squaring
        let polarCenter = CLLocationCoordinate2D(latitude: 60.0, longitude: 0.0)
        let stopPolarLat = try makeStop(id: "polar_lat", latitude: 61.0, longitude: 0.0)
        let stopPolarLon = try makeStop(id: "polar_lon", latitude: 60.0, longitude: 1.0)

        let distLat60 = Stop.squaredDistance(stopPolarLat, to: polarCenter) // 1.0^2 = 1.0
        let distLon60 = Stop.squaredDistance(stopPolarLon, to: polarCenter) // (1.0 * 0.5)^2 = 0.25
        #expect(abs(distLat60 - 1.0) < 0.001)
        #expect(abs(distLon60 - 0.25) < 0.001)
    }

    // MARK: - nearest

    @Test func `nearest returns empty array when limit is zero or negative`() throws {
        let center = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        let stop = try makeStop(id: "s1", latitude: 47.61, longitude: -122.33)

        #expect(Stop.nearest([stop], to: center, limit: 0).isEmpty)
        #expect(Stop.nearest([stop], to: center, limit: -5).isEmpty)
    }

    @Test func `nearest returns empty array when candidate list is empty`() {
        let center = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)
        #expect(Stop.nearest([], to: center, limit: 10).isEmpty)
    }

    @Test func `nearest orders stops by proximity and respects limit`() throws {
        let center = CLLocationCoordinate2D(latitude: 47.6097, longitude: -122.3331)

        let closest = try makeStop(id: "closest", latitude: 47.6098, longitude: -122.3332)
        let medium = try makeStop(id: "medium", latitude: 47.6150, longitude: -122.3331)
        let farthest = try makeStop(id: "farthest", latitude: 47.6500, longitude: -122.3331)

        let stops = [farthest, closest, medium]

        let topTwo = Stop.nearest(stops, to: center, limit: 2)
        #expect(topTwo.count == 2)
        #expect(topTwo[0].id == "closest")
        #expect(topTwo[1].id == "medium")

        let allThree = Stop.nearest(stops, to: center, limit: 10)
        #expect(allThree.count == 3)
        #expect(allThree.map(\.id) == ["closest", "medium", "farthest"])
    }

    @Test func `nearest orders stops using cosine-scaled longitude at high latitude`() throws {
        // At latitude 60, cos(60 deg) == 0.5.
        // center: (60.0, 0.0)
        // stopLon: (60.0, 1.5) -> lon delta = 1.5, scaled delta = 0.75, squaredDist = 0.5625
        // stopLat: (60.9, 0.0) -> lat delta = 0.9, squaredDist = 0.81
        // Without cosine scaling, stopLat (delta 0.9) would be ranked closer than stopLon (delta 1.5).
        // With cosine scaling, stopLon (scaled 0.75) is closer than stopLat (0.90).
        let center = CLLocationCoordinate2D(latitude: 60.0, longitude: 0.0)
        let stopLon = try makeStop(id: "stop_lon_closer_when_scaled", latitude: 60.0, longitude: 1.5)
        let stopLat = try makeStop(id: "stop_lat_further_when_scaled", latitude: 60.9, longitude: 0.0)

        let ranked = Stop.nearest([stopLat, stopLon], to: center, limit: 2)
        #expect(ranked.count == 2)
        #expect(ranked[0].id == "stop_lon_closer_when_scaled")
        #expect(ranked[1].id == "stop_lat_further_when_scaled")
    }
}
