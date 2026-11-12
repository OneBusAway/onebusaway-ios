//
//  RouteLanesTests.swift
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

/// `RouteLanes`: one stop's routes laid out across the streets they share (#1569),
/// drawn at the zoom the map is at. Both maps draw from it: `StopRouteFocusMapLayer`
/// on the map tab and `StopFocusMapDisplayModel` on the panel.
@MainActor
@Suite
struct RouteLanesTests {

    private static let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 47.5615, longitude: -122.3870))
    private static let mapPointsPerMeter = MKMapPointsPerMeterAtLatitude(origin.coordinate.latitude)

    private static func point(east: Double, north: Double) -> CLLocationCoordinate2D {
        MKMapPoint(x: origin.x + east * mapPointsPerMeter, y: origin.y - north * mapPointsPerMeter).coordinate
    }

    /// An east–west street, 1 km long, and another a kilometer north of it.
    private static let street = [point(east: 0, north: 0), point(east: 1000, north: 0)]
    private static let otherStreet = [point(east: 0, north: 1000), point(east: 1000, north: 1000)]

    /// About zoom 16: two map points per screen point would be far too coarse, so
    /// a realistic scale keeps the lane a few meters wide.
    private static let screenScale: CGFloat = 1 / (0.3 * mapPointsPerMeter)

    private static func middle(_ coordinates: [CLLocationCoordinate2D]) -> MKMapPoint {
        MKMapPoint(coordinates[coordinates.count / 2])
    }

    @Test func `Routes sharing a street draw a lane width apart on screen`() throws {
        let lanes = RouteLanes(shapes: ["A": Self.street, "B": Self.street])

        let a = try #require(lanes.coordinates(for: "A", screenScale: Self.screenScale))
        let b = try #require(lanes.coordinates(for: "B", screenScale: Self.screenScale))

        let apartOnScreen = Self.middle(a).distance(to: Self.middle(b)) / MKMetersPerMapPointAtLatitude(47.5615)
            * Self.screenScale
        #expect(abs(apartOnScreen - RouteLanes.laneWidth) < 0.5)
        #expect(lanes.sharedRouteIDs == ["A", "B"])
    }

    @Test func `A route on its own street draws its own shape`() throws {
        let lanes = RouteLanes(shapes: ["A": Self.street, "B": Self.otherStreet])

        let a = try #require(lanes.coordinates(for: "A", screenScale: Self.screenScale))
        #expect(a.count == Self.street.count)
        #expect(zip(a, Self.street).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude })
        #expect(lanes.sharedRouteIDs.isEmpty)
    }

    /// Before the map has a size there's no zoom to size a lane for.
    @Test func `With no zoom yet, shared routes draw down the middle`() throws {
        let lanes = RouteLanes(shapes: ["A": Self.street, "B": Self.street])

        let a = try #require(lanes.coordinates(for: "A", screenScale: nil))
        let b = try #require(lanes.coordinates(for: "B", screenScale: nil))
        #expect(Self.middle(a).distance(to: Self.middle(b)) < 0.01)
    }

    @Test func `A route with no shape draws nothing`() {
        let lanes = RouteLanes(shapes: ["A": Self.street])
        #expect(lanes.coordinates(for: "Z", screenScale: Self.screenScale) == nil)
    }

    /// Sides follow the route IDs, not the order the shapes arrived in, so a redraw
    /// doesn't swap them.
    @Test func `A route keeps its side however the shapes are ordered`() throws {
        let first = RouteLanes(shapes: ["A": Self.street, "B": Self.street])
        let second = RouteLanes(shapes: ["B": Self.street, "A": Self.street])

        let a1 = try #require(first.coordinates(for: "A", screenScale: Self.screenScale))
        let a2 = try #require(second.coordinates(for: "A", screenScale: Self.screenScale))
        #expect(Self.middle(a1).distance(to: Self.middle(a2)) < 0.01)
    }

    // MARK: - Zoom

    @Test func `Lanes drawn at no zoom yet need drawing`() {
        #expect(RouteLanes.needsRedraw(drawnAt: nil, now: 1))
    }

    @Test func `Within a quarter of a zoom level, lanes stay put`() {
        #expect(!RouteLanes.needsRedraw(drawnAt: 1, now: 1.1))
        #expect(!RouteLanes.needsRedraw(drawnAt: 1, now: 0.9))
    }

    @Test func `Past a quarter of a zoom level, lanes are drawn again`() {
        #expect(RouteLanes.needsRedraw(drawnAt: 1, now: 1.25))
        #expect(RouteLanes.needsRedraw(drawnAt: 1, now: 0.8))
    }
}
