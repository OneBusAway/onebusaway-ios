//
//  StopDistanceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
final class StopDistanceTests: OBATestCase {

    /// Stops are returned nearest-first, and the list is truncated to `limit`.
    @Test func `Nearest returns the closest stops in order`() throws {
        let stops = try Fixtures.loadSomeStops()
        let anchor = try #require(stops.first).location.coordinate

        let nearest = Stop.nearest(stops, to: anchor, limit: 3)

        #expect(nearest.count == 3)
        // The anchor stop is zero distance from itself, so it must come first.
        #expect(nearest.first?.id == stops.first?.id)

        let distances = nearest.map { Stop.squaredDistance($0, to: anchor) }
        #expect(distances == distances.sorted())
    }

    /// A limit larger than the input returns everything, still ordered.
    @Test func `Nearest returns everything when the limit exceeds the input`() throws {
        let stops = try Fixtures.loadSomeStops()
        let anchor = try #require(stops.first).location.coordinate

        let nearest = Stop.nearest(stops, to: anchor, limit: stops.count + 10)

        #expect(nearest.count == stops.count)
    }

    /// Degenerate inputs return empty rather than trapping.
    @Test func `Nearest returns empty for empty input or a non positive limit`() throws {
        let stops = try Fixtures.loadSomeStops()
        let anchor = try #require(stops.first).location.coordinate

        #expect(Stop.nearest([], to: anchor, limit: 4).isEmpty)
        #expect(Stop.nearest(stops, to: anchor, limit: 0).isEmpty)
        #expect(Stop.nearest(stops, to: anchor, limit: -1).isEmpty)
    }

    /// Longitude is scaled by cos(latitude), so a degree of longitude counts
    /// for less than a degree of latitude away from the equator. Without the
    /// scaling these two would compare equal.
    @Test func `Squared distance scales longitude by latitude`() throws {
        let stops = try Fixtures.loadSomeStops()
        let reference = try #require(stops.first)
        let anchor = reference.location.coordinate

        let latOffset = CLLocationCoordinate2D(latitude: anchor.latitude + 1, longitude: anchor.longitude)
        let lonOffset = CLLocationCoordinate2D(latitude: anchor.latitude, longitude: anchor.longitude + 1)

        let latDistance = Stop.squaredDistance(reference, to: latOffset)
        let lonDistance = Stop.squaredDistance(reference, to: lonOffset)

        // Seattle is well north of the equator, so cos(lat) < 1.
        #expect(lonDistance < latDistance)
    }

    /// At high latitudes (e.g. 60°), longitude delta is scaled by cos(60°) = 0.5 before squaring,
    /// so a stop with larger raw longitude offset is ranked closer than a stop with smaller latitude offset.
    @Test func `Nearest orders stops using cosine-scaled longitude at high latitude`() throws {
        let center = CLLocationCoordinate2D(latitude: 60.0, longitude: 0.0)
        let stopLonDict: [String: Any] = [
            "id": "stop_lon_closer_when_scaled",
            "name": "Stop Lon",
            "lat": 60.0,
            "lon": 1.5,
            "direction": "N",
            "code": "101",
            "locationType": 0,
            "routeIds": ["1_10"],
            "staticRouteIds": ["1_10"],
            "wheelchairBoarding": "UNKNOWN"
        ]
        let stopLatDict: [String: Any] = [
            "id": "stop_lat_further_when_scaled",
            "name": "Stop Lat",
            "lat": 60.9,
            "lon": 0.0,
            "direction": "N",
            "code": "102",
            "locationType": 0,
            "routeIds": ["1_10"],
            "staticRouteIds": ["1_10"],
            "wheelchairBoarding": "UNKNOWN"
        ]
        let stopLon = try Fixtures.dictionaryToModel(type: Stop.self, dictionary: stopLonDict)
        let stopLat = try Fixtures.dictionaryToModel(type: Stop.self, dictionary: stopLatDict)

        let ranked = Stop.nearest([stopLat, stopLon], to: center, limit: 2)
        #expect(ranked.count == 2)
        #expect(ranked[0].id == "stop_lon_closer_when_scaled")
        #expect(ranked[1].id == "stop_lat_further_when_scaled")
    }
}