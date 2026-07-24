//
//  TripAttributesIdentityTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
@testable import OBAKitCore

/// Covers the identity rule behind the duplicate-Live-Activity guard.
///
/// The guard itself (`Activity.running(matching:)`) can't be unit-tested —
/// ActivityKit's static `activities` isn't injectable — so these tests pin the
/// comparison it delegates to, which is where the actual decision lives.
@MainActor
class TripAttributesIdentityTests: XCTestCase {

    private func staticData(
        routeShortName: String = "49",
        routeHeadsign: String = "Downtown",
        stopID: String = "1_75403",
        routeColorHex: String? = nil,
        regionID: Int = 1
    ) -> TripAttributes.StaticData {
        TripAttributes.StaticData(
            routeShortName: routeShortName,
            routeHeadsign: routeHeadsign,
            stopID: stopID,
            routeColorHex: routeColorHex,
            regionID: regionID
        )
    }

    func testMatchesWhenStopRouteAndHeadsignAreEqual() {
        XCTAssertTrue(staticData().tracksSameTrip(as: staticData()))
    }

    func testDoesNotMatchOnDifferentStop() {
        XCTAssertFalse(staticData().tracksSameTrip(as: staticData(stopID: "1_99999")))
    }

    func testDoesNotMatchOnDifferentRoute() {
        XCTAssertFalse(staticData().tracksSameTrip(as: staticData(routeShortName: "8")))
    }

    /// Two directions of the same route at one stop are different trips, so
    /// tracking one must not suppress starting the other.
    func testDoesNotMatchOnDifferentHeadsign() {
        XCTAssertFalse(staticData().tracksSameTrip(as: staticData(routeHeadsign: "University District")))
    }

    /// The route colour arrives with the first arrivals payload and is nil until
    /// then. If it were part of identity, a second tap before data loaded would
    /// be treated as a different trip and would start a duplicate — the exact
    /// case the guard exists to prevent.
    func testMatchesWhenOnlyRouteColorDiffers() {
        XCTAssertTrue(staticData(routeColorHex: nil).tracksSameTrip(as: staticData(routeColorHex: "FF0000")))
    }

    /// `regionID` is routing metadata for the widget deep link, not identity —
    /// and excluding it keeps this rule identical to the stop/route/headsign
    /// match `updateRunningLiveActivities()` already uses.
    func testMatchesWhenOnlyRegionDiffers() {
        XCTAssertTrue(staticData(regionID: 1).tracksSameTrip(as: staticData(regionID: 5)))
    }

    /// Symmetry is pinned with concrete values in both directions — asserting
    /// the two calls equal each other would also pass if both directions were
    /// wrong in the same way.
    func testIsSymmetric() {
        let a = staticData()
        let b = staticData(routeShortName: "8")
        XCTAssertFalse(a.tracksSameTrip(as: b))
        XCTAssertFalse(b.tracksSameTrip(as: a))

        let plain = staticData(routeColorHex: nil)
        let colored = staticData(routeColorHex: "FF0000")
        XCTAssertTrue(plain.tracksSameTrip(as: colored))
        XCTAssertTrue(colored.tracksSameTrip(as: plain))
    }

    /// Empty headsign is the fallback both start paths use when a bookmark or
    /// departure has none, so it has to compare cleanly rather than being
    /// treated as "unknown, therefore different".
    func testMatchesWhenBothHeadsignsAreEmpty() {
        XCTAssertTrue(staticData(routeHeadsign: "").tracksSameTrip(as: staticData(routeHeadsign: "")))
    }

    /// A record with no stored headsign ("" after the `tripHeadsign ?? ""`
    /// fallback) is deliberately not treated as the same trip as one with a
    /// specific headsign — that's the boundary of the guard's cross-screen
    /// dedupe, pinned here so it can't change silently.
    func testDoesNotMatchWhenOneHeadsignIsEmpty() {
        XCTAssertFalse(staticData(routeHeadsign: "").tracksSameTrip(as: staticData(routeHeadsign: "Downtown")))
    }
}
