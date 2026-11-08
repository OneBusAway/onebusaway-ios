//
//  LiveActivityLookupTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

#if os(iOS)

import Foundation
import Testing
@testable import OBAKitCore

/// Tests for `TripAttributes.StaticData.tracksSameTrip(as:)` equivalence relation.
///
/// Verifies identity matching across stop ID, route short name, headsign,
/// wildcard empty trip IDs, and presentation field exclusions (color, region).
@Suite(.serialized)
struct LiveActivityLookupTests {

    private func makeStaticData(
        stopID: String = "1_75403",
        routeShortName: String = "44",
        routeHeadsign: String = "UW Station",
        tripID: String = "1_trip_123",
        routeColorHex: String? = "#0055AA",
        regionID: Int = 1
    ) -> TripAttributes.StaticData {
        TripAttributes.StaticData(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            stopID: stopID,
            routeColorHex: routeColorHex,
            regionID: regionID,
            tripID: tripID
        )
    }

    // MARK: - Exact Identity Matches

    @Test func `tracksSameTrip returns true for identical StaticData`() {
        let first = makeStaticData()
        let second = makeStaticData()

        #expect(first.tracksSameTrip(as: second))
        #expect(second.tracksSameTrip(as: first))
    }

    // MARK: - Wildcard Empty Trip ID

    @Test func `tracksSameTrip treats empty tripID as wildcard`() {
        let concrete = makeStaticData(tripID: "1_concrete_trip")
        let wildcard = makeStaticData(tripID: "")

        // Bookmark Track leaves tripID empty, so it reconciles with concrete card
        #expect(concrete.tracksSameTrip(as: wildcard))
        #expect(wildcard.tracksSameTrip(as: concrete))

        // Two wildcards match each other
        let anotherWildcard = makeStaticData(tripID: "")
        #expect(wildcard.tracksSameTrip(as: anotherWildcard))
    }

    @Test func `tracksSameTrip returns false when both have different concrete trip IDs`() {
        let tripA = makeStaticData(tripID: "1_trip_A")
        let tripB = makeStaticData(tripID: "1_trip_B")

        #expect(!tripA.tracksSameTrip(as: tripB))
        #expect(!tripB.tracksSameTrip(as: tripA))
    }

    // MARK: - Stop, Route, and Headsign Mismatches

    @Test func `tracksSameTrip returns false when stop IDs differ`() {
        let a = makeStaticData(stopID: "stop_1")
        let b = makeStaticData(stopID: "stop_2")

        #expect(!a.tracksSameTrip(as: b))
    }

    @Test func `tracksSameTrip returns false when routeShortNames differ`() {
        let a = makeStaticData(routeShortName: "10")
        let b = makeStaticData(routeShortName: "44")

        #expect(!a.tracksSameTrip(as: b))
    }

    @Test func `tracksSameTrip returns false when routeHeadsigns differ`() {
        let a = makeStaticData(routeHeadsign: "Downtown")
        let b = makeStaticData(routeHeadsign: "Capitol Hill")

        #expect(!a.tracksSameTrip(as: b))
    }

    // MARK: - Ignored Presentation Metadata

    @Test func `tracksSameTrip ignores color hex differences`() {
        let withBlue = makeStaticData(routeColorHex: "#0000FF")
        let withRed = makeStaticData(routeColorHex: "#FF0000")
        let withoutColor = makeStaticData(routeColorHex: nil)

        #expect(withBlue.tracksSameTrip(as: withRed))
        #expect(withBlue.tracksSameTrip(as: withoutColor))
    }

    @Test func `tracksSameTrip ignores region ID differences`() {
        let region1 = makeStaticData(regionID: 1)
        let region2 = makeStaticData(regionID: 2)

        #expect(region1.tracksSameTrip(as: region2))
    }
}

#endif // os(iOS)
