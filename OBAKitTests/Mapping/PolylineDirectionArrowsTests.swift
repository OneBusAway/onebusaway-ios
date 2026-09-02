//
//  PolylineDirectionArrowsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreGraphics
import CoreLocation
import Testing
@testable import OBAKit

@Suite(.serialized)
struct PolylineDirectionArrowsTests {

    @Test func `Empty and single-point shapes have no arrow placements`() {
        let point = CLLocationCoordinate2D(latitude: 47, longitude: -122)

        #expect(PolylineDirectionArrows.placements(along: []).isEmpty)
        #expect(PolylineDirectionArrows.placements(along: [point]).isEmpty)
    }

    @Test func `A zero-length shape has no arrow placements`() {
        let point = CLLocationCoordinate2D(latitude: 47, longitude: -122)

        #expect(PolylineDirectionArrows.placements(along: [point, point]).isEmpty)
    }

    @Test func `A northbound line places regularly spaced northbound arrows`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47, longitude: -122),
            CLLocationCoordinate2D(latitude: 47.018, longitude: -122)
        ]

        let placements = PolylineDirectionArrows.placements(along: line, spacing: 500)

        #expect((3...4).contains(placements.count))
        #expect(placements.allSatisfy { abs($0.headingDegrees) < 3 })
    }

    @Test func `An eastbound line points arrows east`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47, longitude: -122),
            CLLocationCoordinate2D(latitude: 47, longitude: -121.973)
        ]

        let placements = PolylineDirectionArrows.placements(along: line, spacing: 500)

        #expect(!placements.isEmpty)
        #expect(placements.allSatisfy { abs($0.headingDegrees - 90) < 3 })
    }

    @Test func `Spacing longer than the line produces no arrows`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47, longitude: -122),
            CLLocationCoordinate2D(latitude: 47.001, longitude: -122)
        ]

        #expect(PolylineDirectionArrows.placements(along: line, spacing: 500).isEmpty)
    }

    @Test func `Very long lines cap their arrow count`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47, longitude: -122),
            CLLocationCoordinate2D(latitude: 48, longitude: -122)
        ]

        let placements = PolylineDirectionArrows.placements(along: line, spacing: 100)

        #expect(!placements.isEmpty)
        #expect(placements.count <= 24)
    }

    /// `chevron.up` points north at identity. UIKit view space has y down, so a
    /// positive `CGAffineTransform` rotation is clockwise — the same sense as a
    /// compass heading. East must send the up-vector to the right, not the left.
    @Test func `View transform maps compass heading onto UIKit rotation`() {
        let up = CGPoint(x: 0, y: -1)

        let north = up.applying(PolylineDirectionArrows.viewTransform(headingDegrees: 0))
        #expect(abs(north.x) < 0.001)
        #expect(north.y < -0.99)

        let east = up.applying(PolylineDirectionArrows.viewTransform(headingDegrees: 90))
        #expect(east.x > 0.99)
        #expect(abs(east.y) < 0.001)
    }
}
