//
//  TripRouteOverlayTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Testing
@testable import OBAKit

/// The classic `TripViewController` map used to draw one route-colored polyline
/// for the whole trip. These tests lock the split the UIKit map must apply so
/// the travelled half is a separate overlay from the half still ahead.
///
/// See: https://github.com/OneBusAway/onebusaway-ios/issues/444
@MainActor
@Suite(.serialized)
struct TripRouteOverlayTests {

    private func parallel(from startLon: Double, to endLon: Double, points: Int) -> [CLLocationCoordinate2D] {
        precondition(points >= 2)
        return (0..<points).map { index in
            let t = Double(index) / Double(points - 1)
            return CLLocationCoordinate2D(latitude: 47, longitude: startLon + (endLon - startLon) * t)
        }
    }

    @Test func `No reported progress draws the whole shape as ahead`() {
        let line = parallel(from: -122, to: -121.99, points: 4)
        let overlays = TripRouteOverlays.make(coordinates: line, fraction: nil)

        #expect(overlays.count == 1)
        #expect(overlays[0].isSpent == false)
        #expect(overlays[0].pointCount == 4)
    }

    @Test func `Mid-trip progress yields a spent overlay and an ahead overlay`() {
        let line = parallel(from: -122, to: -121.99, points: 2)
        let overlays = TripRouteOverlays.make(coordinates: line, fraction: 0.5)

        #expect(overlays.count == 2)
        #expect(overlays[0].isSpent == true)
        #expect(overlays[1].isSpent == false)
        #expect(overlays[0].pointCount == 2)
        #expect(overlays[1].pointCount == 2)
    }

    @Test func `A trip that has not started has no spent overlay`() {
        let line = parallel(from: -122, to: -121.99, points: 4)
        let overlays = TripRouteOverlays.make(coordinates: line, fraction: 0)

        #expect(overlays.count == 1)
        #expect(overlays[0].isSpent == false)
        #expect(overlays[0].pointCount == 4)
    }

    @Test func `A finished trip has no ahead overlay`() {
        let line = parallel(from: -122, to: -121.99, points: 4)
        let overlays = TripRouteOverlays.make(coordinates: line, fraction: 1)

        #expect(overlays.count == 1)
        #expect(overlays[0].isSpent == true)
        #expect(overlays[0].pointCount == 4)
    }

    @Test func `Spent stroke is gray and thinner than the live half`() {
        let spent = TripRouteOverlayAppearance.make(
            isSpent: true,
            routeColor: .red,
            needsIncreasedVisibility: false
        )
        let ahead = TripRouteOverlayAppearance.make(
            isSpent: false,
            routeColor: .red,
            needsIncreasedVisibility: false
        )

        #expect(spent.lineWidth < ahead.lineWidth)
        #expect(spent.strokeColor != ahead.strokeColor)
    }
}
