//
//  PolylineDirectionArrowsTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

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

    @Test func `Non-positive or non-finite spacing produces no arrows`() {
        let line = [
            CLLocationCoordinate2D(latitude: 47, longitude: -122),
            CLLocationCoordinate2D(latitude: 47.018, longitude: -122)
        ]

        #expect(PolylineDirectionArrows.placements(along: line, spacing: 0).isEmpty)
        #expect(PolylineDirectionArrows.placements(along: line, spacing: -500).isEmpty)
        #expect(PolylineDirectionArrows.placements(along: line, spacing: .infinity).isEmpty)
        #expect(PolylineDirectionArrows.placements(along: line, spacing: .nan).isEmpty)
    }

    @Test func `Consecutive identical coordinates are skipped without breaking placements`() {
        let p1 = CLLocationCoordinate2D(latitude: 47, longitude: -122)
        let p2 = CLLocationCoordinate2D(latitude: 47.018, longitude: -122)
        let lineWithDuplicates = [p1, p1, p2, p2]

        let placements = PolylineDirectionArrows.placements(along: lineWithDuplicates, spacing: 500)
        #expect(!placements.isEmpty)
        #expect(placements.allSatisfy { abs($0.headingDegrees) < 3 })
    }

    @Test func `PolylineArrowPlacement equality checks coordinate and heading`() {
        let coord1 = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
        let coord2 = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.4)

        let a = PolylineArrowPlacement(coordinate: coord1, headingDegrees: 90)
        let b = PolylineArrowPlacement(coordinate: coord1, headingDegrees: 90)
        let differentCoord = PolylineArrowPlacement(coordinate: coord2, headingDegrees: 90)
        let differentHeading = PolylineArrowPlacement(coordinate: coord1, headingDegrees: 180)

        #expect(a == b)
        #expect(a != differentCoord)
        #expect(a != differentHeading)
    }
}
