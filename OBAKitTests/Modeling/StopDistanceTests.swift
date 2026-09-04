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
}
