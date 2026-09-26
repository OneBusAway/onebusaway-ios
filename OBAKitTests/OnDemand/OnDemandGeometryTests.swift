//
//  OnDemandGeometryTests.swift
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
@testable import OBAKitCore

/// Spec 2.3 (label point) and 2.7 (nearest edge). Rings are near the equator
/// and prime meridian so 0.001° ≈ 111 m in both axes.
@MainActor
@Suite(.serialized)
final class OnDemandGeometryTests {

    private func point(_ latitude: Double, _ longitude: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// A closed ring from (lat, lon) pairs.
    private func ring(_ pairs: [(Double, Double)]) -> [CLLocationCoordinate2D] {
        pairs.map { point($0.0, $0.1) } + [point(pairs[0].0, pairs[0].1)]
    }

    private var square: [CLLocationCoordinate2D] { ring([(0, 0), (0, 0.01), (0.01, 0.01), (0.01, 0)]) }

    private func area(id: String = "a", polygons: [[[CLLocationCoordinate2D]]]) throws -> ServiceArea {
        let coordinates = polygons.map { polygon in polygon.map { ring in ring.map { [$0.longitude, $0.latitude] } } }
        let allPoints = polygons.flatMap { $0.flatMap { $0 } }
        let bbox = [allPoints.map(\.longitude).min()!, allPoints.map(\.latitude).min()!, allPoints.map(\.longitude).max()!, allPoints.map(\.latitude).max()!]
        let geometry: [String: Any] = polygons.count == 1
            ? ["type": "Polygon", "coordinates": coordinates[0]]
            : ["type": "MultiPolygon", "coordinates": coordinates]
        let json: [String: Any] = ["id": id, "name": NSNull(), "description": NSNull(), "bbox": bbox, "geometry": geometry]
        return try JSONDecoder().decode(ServiceArea.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // MARK: - Label point

    @Test func `Label point of a convex ring is its middle`() {
        let label = OnDemandGeometry.labelPoint(polygon: [square], bbox: OnDemandGeometry.boundingBox(of: square))
        expectClose(label.latitude, 0.005, within: 1e-9)
        expectClose(label.longitude, 0.005, within: 1e-9)
        #expect(OnDemandGeometry.pointInRing(label, ring: square))
    }

    /// A U opening north: the mid-latitude line crosses both arms; the label
    /// lands in the wider (left) arm, never in the gap.
    @Test func `Label point of a U-shaped ring lies inside an arm`() {
        let u = ring([(0, 0), (0, 0.01), (0.01, 0.01), (0.01, 0.008), (0.002, 0.008), (0.002, 0.004), (0.01, 0.004), (0.01, 0)])
        let label = OnDemandGeometry.labelPoint(polygon: [u], bbox: OnDemandGeometry.boundingBox(of: u))
        #expect(OnDemandGeometry.pointInRing(label, ring: u))
        #expect(label.longitude < 0.004 || label.longitude > 0.008, "not in the gap: \(label.longitude)")
        expectClose(label.longitude, 0.002, within: 1e-9, "the widest run is the left arm")
    }

    @Test func `Label point of a holed ring avoids the hole`() {
        let hole = ring([(0.004, 0.004), (0.004, 0.006), (0.006, 0.006), (0.006, 0.004)])
        let label = OnDemandGeometry.labelPoint(polygon: [square, hole], bbox: OnDemandGeometry.boundingBox(of: square))
        #expect(OnDemandGeometry.pointInRing(label, ring: square))
        #expect(!OnDemandGeometry.pointInRing(label, ring: hole))
        expectClose(label.latitude, 0.005, within: 1e-9)
    }

    @Test func `A two-polygon area labels its largest polygon`() throws {
        let small = ring([(0.02, 0.02), (0.02, 0.021), (0.021, 0.021), (0.021, 0.02)])
        let label = try #require(OnDemandGeometry.labelPoint(areas: [area(polygons: [[small], [square]])]))
        #expect(OnDemandGeometry.pointInRing(label, ring: square))
    }

    @Test func `Degenerate rings fall back to the bbox centre`() {
        let line = [point(0, 0), point(0.01, 0.01)]
        let bbox = BoundingBox(minLongitude: 0, minLatitude: 0, maxLongitude: 0.01, maxLatitude: 0.01)
        let label = OnDemandGeometry.labelPoint(polygon: [line], bbox: bbox)
        expectClose(label.latitude, 0.005, within: 1e-9)
        expectClose(label.longitude, 0.005, within: 1e-9)

        let collinear = ring([(0, 0), (0.005, 0.005), (0.01, 0.01)])
        let collinearLabel = OnDemandGeometry.labelPoint(polygon: [collinear], bbox: bbox)
        expectClose(collinearLabel.latitude, 0.005, within: 1e-9)
    }

    /// Review Focus 4: the largest polygon by area, not by point count.
    @Test func `Largest polygon selection skips degenerate rings`() throws {
        let degenerate = [point(0.5, 0.5), point(0.5, 0.5), point(0.5, 0.5), point(0.5, 0.5)]
        let label = try #require(OnDemandGeometry.labelPoint(areas: [area(polygons: [[degenerate], [square]])]))
        #expect(OnDemandGeometry.pointInRing(label, ring: square))
        #expect(OnDemandGeometry.labelPoint(areas: [try area(polygons: [[degenerate]])]) == nil)
    }

    @Test func `Areas without geometry have no label point`() throws {
        let json = "{\"id\":\"x\",\"bbox\":[0,0,1,1]}"
        let bare = try JSONDecoder().decode(ServiceArea.self, from: Data(json.utf8))
        #expect(OnDemandGeometry.labelPoint(areas: [bare]) == nil)
    }

    // MARK: - Nearest edge

    @Test func `Inside a square the nearest edge is the closest side`() throws {
        let edge = try #require(OnDemandGeometry.nearestBoundaryPoint(from: point(0.005, 0.002), areas: [area(polygons: [[square]])]))
        expectClose(edge.distanceMeters, 0.002 * .pi / 180 * OnDemandGeometry.earthRadiusMeters, within: 1)
        expectClose(edge.point.longitude, 0, within: 1e-9)
        expectClose(edge.point.latitude, 0.005, within: 1e-9)
        #expect(edge.edgeDirection == .west)
        #expect(edge.riderDirection == .east)
    }

    @Test func `Outside a square the rider direction is reversed`() throws {
        let edge = try #require(OnDemandGeometry.nearestBoundaryPoint(from: point(-0.001, 0.005), areas: [area(polygons: [[square]])]))
        expectClose(edge.distanceMeters, 0.001 * .pi / 180 * OnDemandGeometry.earthRadiusMeters, within: 1)
        #expect(edge.edgeDirection == .north)
        #expect(edge.riderDirection == .south)
    }

    @Test func `A hole edge counts as boundary`() throws {
        let hole = ring([(0.004, 0.004), (0.004, 0.006), (0.006, 0.006), (0.006, 0.004)])
        let edge = try #require(OnDemandGeometry.nearestBoundaryPoint(from: point(0.0035, 0.005), areas: [area(polygons: [[square, hole]])]))
        expectClose(edge.distanceMeters, 0.0005 * .pi / 180 * OnDemandGeometry.earthRadiusMeters, within: 1)
        #expect(edge.edgeDirection == .north)
    }

    /// Review Focus 2: standing on a vertex.
    @Test func `A probe point on a vertex yields a zero-distance edge with a finite bearing`() throws {
        let edge = try #require(OnDemandGeometry.nearestBoundaryPoint(from: point(0, 0), areas: [area(polygons: [[square]])]))
        #expect(edge.distanceMeters == 0)
        #expect(edge.bearingDegrees.isFinite)
        #expect(CompassDirection.allCases.contains(edge.edgeDirection))
    }

    @Test func `Areas without geometry yield no edge`() throws {
        let bare = try JSONDecoder().decode(ServiceArea.self, from: Data("{\"id\":\"x\",\"bbox\":[0,0,1,1]}".utf8))
        #expect(OnDemandGeometry.nearestBoundaryPoint(from: point(0, 0), areas: [bare]) == nil)
    }

    @Test func `A server boundary point builds an edge with the server distance`() {
        let edge = OnDemandGeometry.edge(from: point(-0.001, 0.005), toServerPoint: point(0, 0.005), distanceMeters: 850)
        #expect(edge.distanceMeters == 850)
        #expect(edge.riderDirection == .south)
        expectClose(edge.point.latitude, 0, within: 1e-9)
    }

    // MARK: - Compass

    @Test func `Compass buckets split at 22.5 degree boundaries`() {
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 0) == .north)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 22.4) == .north)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 22.5) == .northeast)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 67.5) == .east)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 112.5) == .southeast)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 157.5) == .south)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 202.5) == .southwest)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 247.5) == .west)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 292.5) == .northwest)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 337.5) == .north)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 359.9) == .north)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: -90) == .west)
        #expect(OnDemandGeometry.compassDirection(bearingDegrees: 450) == .east)
    }

    @Test func `Bearing is measured clockwise from north`() {
        expectClose(OnDemandGeometry.bearingDegrees(from: point(0, 0), to: point(0.01, 0)), 0, within: 1e-6)
        expectClose(OnDemandGeometry.bearingDegrees(from: point(0, 0), to: point(0, 0.01)), 90, within: 1e-6)
        expectClose(OnDemandGeometry.bearingDegrees(from: point(0, 0), to: point(-0.01, 0)), 180, within: 1e-6)
        expectClose(OnDemandGeometry.bearingDegrees(from: point(0, 0), to: point(0, -0.01)), 270, within: 1e-6)
    }
}
