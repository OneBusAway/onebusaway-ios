//
//  ShapeLineTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKitCore

@Suite(.serialized)
struct ShapeLineTests {
    typealias F = EstimationFixtures

    @Test func `A shape needs two points and some length`() {
        #expect(ShapeLine(coordinates: []) == nil)
        #expect(ShapeLine(coordinates: [F.origin]) == nil)
        #expect(ShapeLine(coordinates: [F.origin, F.origin]) == nil)
        #expect(ShapeLine(coordinates: [F.origin, F.point(north: 1)]) != nil)
    }

    @Test func `Length is the sum of its segments`() {
        expectClose(F.straightLine(length: 1000).length, 1000, within: 0.01)
    }

    @Test func `A point along the shape lies that far along it, heading the shape's way`() {
        let line = F.straightLine()
        let located = line.point(at: 250)
        expectClose(located.coordinate.latitude, F.point(north: 250).latitude, within: 1e-9)
        expectClose(located.bearingDegrees, 0, within: 0.01)
    }

    @Test func `A point beyond either end clamps to it`() {
        let line = F.straightLine()
        expectClose(line.point(at: -50).coordinate.latitude, F.origin.latitude, within: 1e-9)
        expectClose(line.point(at: 5000).coordinate.latitude, F.point(north: 1000).latitude, within: 1e-9)
    }

    @Test func `Bearing is clockwise from north`() {
        let east = ShapeLine(coordinates: [F.origin, F.point(north: 0, east: 100)])!
        expectClose(east.point(at: 50).bearingDegrees, 90, within: 0.01)
        let south = ShapeLine(coordinates: [F.point(north: 100), F.origin])!
        expectClose(south.point(at: 50).bearingDegrees, 180, within: 0.01)
    }

    @Test func `A nearby point projects onto the shape`() throws {
        let projection = try #require(F.straightLine().project(F.point(north: 300, east: 10), maxOffset: 40, hint: nil, maxBackwardJump: 100))
        expectClose(projection.distanceAlongShape, 300, within: 0.1)
        expectClose(projection.offsetMeters, 10, within: 0.1)
    }

    @Test func `A point too far from the shape does not project`() {
        #expect(F.straightLine().project(F.point(north: 300, east: 41), maxOffset: 40, hint: nil, maxBackwardJump: 100) == nil)
    }

    @Test func `A point past a corner projects onto the corner`() throws {
        let corner = ShapeLine(coordinates: [F.origin, F.point(north: 100), F.point(north: 100, east: 100)])!
        let projection = try #require(corner.project(F.point(north: 110, east: -10), maxOffset: 40, hint: nil, maxBackwardJump: 100))
        expectClose(projection.distanceAlongShape, 100, within: 0.1)
    }

    /// Out 1000 m north, across 10 m, and back down a parallel street: every point
    /// between the two legs is near both.
    static let outAndBack = ShapeLine(coordinates: [
        F.point(north: 0), F.point(north: 1000), F.point(north: 1000, east: 10), F.point(north: 0, east: 10)
    ])!

    @Test func `On a shape that doubles back, the hint picks the leg the vehicle is on`() throws {
        let between = F.point(north: 300, east: 5)

        let outbound = try #require(Self.outAndBack.project(between, maxOffset: 40, hint: 280, maxBackwardJump: 100))
        expectClose(outbound.distanceAlongShape, 300, within: 0.1)

        let inbound = try #require(Self.outAndBack.project(between, maxOffset: 40, hint: 1650, maxBackwardJump: 100))
        expectClose(inbound.distanceAlongShape, 1710, within: 0.1)
    }

    @Test func `A hint does not pull a vehicle back onto a leg it has passed`() throws {
        // Hint 1300 on the return leg; the outbound candidate at 300 is a kilometre
        // behind it, so the return leg wins even though it is the farther match.
        let projection = try #require(Self.outAndBack.project(F.point(north: 300, east: 4), maxOffset: 40, hint: 1300, maxBackwardJump: 100))
        expectClose(projection.distanceAlongShape, 1710, within: 0.1)
    }

    @Test func `Without a hint, the nearest leg wins`() throws {
        let projection = try #require(Self.outAndBack.project(F.point(north: 300, east: 8), maxOffset: 40, hint: nil, maxBackwardJump: 100))
        expectClose(projection.distanceAlongShape, 1710, within: 0.1)
    }
}
