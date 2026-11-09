//
//  PolylineDirectionArrowsExtendedTests.swift
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

/// Tests for `PolylineDirectionArrows` heading calculations, southbound/westbound
/// directions, and custom spacing intervals.
@Suite(.serialized)
struct PolylineDirectionArrowsExtendedTests {

    // MARK: - Southbound Heading

    @Test func `A southbound line points arrows south`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47.018, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0)
        ]

        let placements = PolylineDirectionArrows.placements(along: line, spacing: 500)

        #expect(!placements.isEmpty)
        for placement in placements {
            // South is ~180 degrees
            #expect(abs(placement.headingDegrees - 180.0) < 5.0)
        }
    }

    // MARK: - Westbound Heading

    @Test func `A westbound line points arrows west`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47.0, longitude: -121.973),
            CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0)
        ]

        let placements = PolylineDirectionArrows.placements(along: line, spacing: 500)

        #expect(!placements.isEmpty)
        for placement in placements {
            // West is ~270 degrees
            #expect(abs(placement.headingDegrees - 270.0) < 5.0)
        }
    }

    // MARK: - Spacing Bounds

    @Test func `Short line with large spacing yields zero placements`() {
        let shortLine = [
            CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 47.0001, longitude: -122.0) // ~11 meters
        ]

        let placements = PolylineDirectionArrows.placements(along: shortLine, spacing: 1000)
        #expect(placements.isEmpty)
    }

    @Test func `Placements are strictly positioned along the polyline path`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            CLLocationCoordinate2D(latitude: 47.018, longitude: -122.0)
        ]

        let placements = PolylineDirectionArrows.placements(along: line, spacing: 500)
        #expect(placements.count >= 2)

        for placement in placements {
            #expect(placement.coordinate.latitude >= 47.0)
            #expect(placement.coordinate.latitude <= 47.018)
            #expect(abs(placement.coordinate.longitude - (-122.0)) < 0.001)
        }
    }
}
