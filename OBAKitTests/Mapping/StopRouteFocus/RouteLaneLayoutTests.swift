//
//  RouteLaneLayoutTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import MapKit
import Testing
@testable import OBAKit

/// Routes that share a street draw side by side instead of on top of each other (#1569).
@Suite
struct RouteLaneLayoutTests {

    /// A fixed spot in West Seattle.
    private static let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 47.5615, longitude: -122.3870))

    /// Map points per meter here, so a test can work in meters.
    private static let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(origin.coordinate.latitude)

    /// A point `east` and `north` meters from `origin`. Map points' y runs south.
    private static func point(east: Double, north: Double) -> CLLocationCoordinate2D {
        MKMapPoint(x: origin.x + east * mapPointsPerMeter, y: origin.y - north * mapPointsPerMeter).coordinate
    }

    /// How far north of `origin` `coordinate` lies, in meters.
    private static func northing(of coordinate: CLLocationCoordinate2D) -> Double {
        (origin.y - MKMapPoint(coordinate).y) / mapPointsPerMeter
    }

    /// An east–west street, 1 km long.
    private static let eastbound = [point(east: 0, north: 0), point(east: 1000, north: 0)]
    private static let westbound = Array(eastbound.reversed())

    /// Meters between two coordinates.
    private static func distance(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> CLLocationDistance {
        MKMapPoint(lhs).distance(to: MKMapPoint(rhs))
    }

    /// The point on `line` nearest to `coordinate`, in meters.
    private static func distance(from coordinate: CLLocationCoordinate2D, to line: [CLLocationCoordinate2D]) -> CLLocationDistance {
        zip(line, line.dropFirst()).map { start, end in
            RouteLaneLayout.distance(from: MKMapPoint(coordinate), toSegmentFrom: MKMapPoint(start), to: MKMapPoint(end))
        }.min().map { $0 / mapPointsPerMeter } ?? .greatestFiniteMagnitude
    }

    private static func offset(_ line: RouteLaneLayout.Line, laneWidthMeters: Double) -> [CLLocationCoordinate2D] {
        line.offsetCoordinates(laneWidth: laneWidthMeters * mapPointsPerMeter)
    }

    /// Whether `coordinate` lies within 15 m, east–west, of `east` meters along the street.
    private static func eastOf(_ coordinate: CLLocationCoordinate2D, isNear east: Double) -> Bool {
        abs(MKMapPoint(coordinate).x - MKMapPoint(point(east: east, north: 0)).x) < 15 * mapPointsPerMeter
    }

    /// The middle of an offset line: well inside any shared stretch.
    private static func middle(_ coordinates: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        coordinates[coordinates.count / 2]
    }

    // MARK: - Lanes

    @Test func `A route on its own street keeps the middle of it`() throws {
        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound)])

        let line = try #require(lines["A"])
        #expect(!line.isShared)
        #expect(line.lanes.allSatisfy { $0 == 0 })
    }

    @Test func `Two routes on the same street take a lane each`() throws {
        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound), ("B", Self.eastbound)])

        let a = try #require(lines["A"]), b = try #require(lines["B"])
        #expect(a.isShared)
        #expect(b.isShared)

        let width = 10.0
        let gap = Self.distance(Self.middle(Self.offset(a, laneWidthMeters: width)), Self.middle(Self.offset(b, laneWidthMeters: width)))
        #expect(abs(gap - width) < 0.5)
    }

    /// The case a plain "left of travel" offset gets wrong: both lines would move to
    /// the same side of the street and still overlap.
    @Test func `Two routes running opposite ways on the same street take a lane each`() throws {
        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound), ("B", Self.westbound)])

        let a = try #require(lines["A"]), b = try #require(lines["B"])
        let width = 10.0
        let aMiddle = Self.middle(Self.offset(a, laneWidthMeters: width))
        let bOffset = Self.offset(b, laneWidthMeters: width)

        #expect(abs(Self.distance(from: aMiddle, to: bOffset) - width) < 0.5)
    }

    /// Two agencies rarely trace a street through the same points.
    @Test func `Routes a few meters apart, sampled differently, still share`() throws {
        let sparse = [Self.point(east: 0, north: 4), Self.point(east: 1000, north: 4)]
        let dense = stride(from: 0.0, through: 1000, by: 37).map { Self.point(east: $0, north: 0) }

        let lines = RouteLaneLayout.lines(for: [("A", sparse), ("B", dense)])

        #expect(try #require(lines["A"]).isShared)
        #expect(try #require(lines["B"]).isShared)
    }

    @Test func `Routes that only cross keep the middle of their streets`() throws {
        let northbound = [Self.point(east: 500, north: -500), Self.point(east: 500, north: 500)]

        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound), ("B", northbound)])

        #expect(try !#require(lines["A"]).isShared)
        #expect(try !#require(lines["B"]).isShared)
    }

    @Test func `Routes on parallel streets a block apart keep the middle of their streets`() throws {
        let nextStreet = [Self.point(east: 0, north: 100), Self.point(east: 1000, north: 100)]

        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound), ("B", nextStreet)])

        #expect(try !#require(lines["A"]).isShared)
        #expect(try !#require(lines["B"]).isShared)
    }

    /// The screenshot in #1569: two routes run together for a stretch, then part.
    @Test func `A route moves over only where it shares the street`() throws {
        let joinsThenTurns = [
            Self.point(east: 0, north: 0),
            Self.point(east: 500, north: 0),
            Self.point(east: 500, north: 800)
        ]

        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound), ("B", joinsThenTurns)])
        let a = try #require(lines["A"])
        let offsetA = Self.offset(a, laneWidthMeters: 10)

        // Shared: moved half a lane off its street.
        let shared = try #require(offsetA.first { Self.eastOf($0, isNear: 250) })
        #expect(abs(Self.distance(from: shared, to: Self.eastbound) - 5) < 0.5)
        // On its own: back in the middle.
        let alone = try #require(offsetA.first { Self.eastOf($0, isNear: 800) })
        #expect(Self.distance(from: alone, to: Self.eastbound) < 0.5)
    }

    /// Regression, seen at 44th Ave SW & SW Alaska St: two routes turning the same
    /// corner pinched together into it and kinked out of it. Near the corner the
    /// nearest piece of the other route is on the cross street, and the corner
    /// itself runs diagonally, parallel to neither; both read as not sharing.
    @Test func `Routes turning the same corner stay a lane apart around it`() throws {
        let corner = { (shift: Double) in
            [Self.point(east: shift, north: 300), Self.point(east: shift, north: shift), Self.point(east: 300, north: shift)]
        }
        let lines = RouteLaneLayout.lines(for: [("A", corner(0)), ("B", corner(3))])
        let a = try #require(lines["A"]), b = try #require(lines["B"])

        #expect(a.lanes.allSatisfy { $0 != 0 })
        #expect(b.lanes.allSatisfy { $0 != 0 })

        let width = 10.0
        let offsetB = Self.offset(b, laneWidthMeters: width)
        let closest = Self.offset(a, laneWidthMeters: width).map { Self.distance(from: $0, to: offsetB) }.min() ?? 0
        #expect(closest > width * 0.6)
    }

    @Test func `Three routes on one street take three different lanes`() throws {
        let lines = RouteLaneLayout.lines(for: [("A", Self.eastbound), ("B", Self.westbound), ("C", Self.eastbound)])

        let width = 10.0
        let middles = try ["A", "B", "C"].map { Self.middle(Self.offset(try #require(lines[$0]), laneWidthMeters: width)) }
        let northings = middles.map(Self.northing).sorted()

        #expect(abs(northings[1] - northings[0] - width) < 0.5)
        #expect(abs(northings[2] - northings[1] - width) < 0.5)
    }

    // MARK: - Offsetting

    @Test func `A line with no lanes offsets to its own points`() throws {
        let line = try #require(RouteLaneLayout.lines(for: [("A", Self.eastbound)])["A"])

        let offset = Self.offset(line, laneWidthMeters: 10)

        #expect(offset.allSatisfy { Self.distance(from: $0, to: Self.eastbound) < 0.01 })
        #expect(Self.distance(offset.first!, Self.eastbound.first!) < 0.01)
        #expect(Self.distance(offset.last!, Self.eastbound.last!) < 0.01)
    }

    @Test func `A shape too short to draw gets no line`() {
        let lines = RouteLaneLayout.lines(for: [("A", [Self.point(east: 0, north: 0)])])

        #expect(lines["A"] == nil)
    }
}
