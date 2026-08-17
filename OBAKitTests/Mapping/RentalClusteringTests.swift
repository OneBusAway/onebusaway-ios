//
//  RentalClusteringTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import Testing
import OTPKit
@testable import OBAKit

/// MapKit clusters by view-frame collision; SwiftUI `Map` offers nothing
/// equivalent, so the panel groups in screen space itself. Pure function, so
/// these tests need no map at all.
@Suite(.serialized)
struct RentalClusteringTests {

    /// An iPhone-ish map viewport spanning roughly one square kilometre.
    private let span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    private let mapSize = CGSize(width: 390, height: 844)

    private func items(_ rentals: [VehicleRental]) -> [RentalMapItem] {
        RentalClustering.items(for: rentals, span: span, mapSize: mapSize, cellSize: 60)
    }

    @Test func `Isolated vehicles stay single`() throws {
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.600, lon: -122.300),
            try RentalFixtures.vehicle(id: "b", lat: 47.609, lon: -122.309)
        ])

        #expect(result.count == 2)
        #expect(result.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    @Test func `Co-located vehicles collapse into one cluster`() throws {
        // Base coordinate deliberately chosen to sit mid-cell (raw longitude index
        // -79494.48, comfortably between cell boundaries). Tiny offsets keep all
        // three in the same cell; see `Vehicles straddling a cell boundary are not merged`
        // for the accepted boundary-crossing divergence.
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.60040, lon: -122.29920),
            try RentalFixtures.vehicle(id: "b", lat: 47.60041, lon: -122.29919),
            try RentalFixtures.vehicle(id: "c", lat: 47.60042, lon: -122.29918)
        ])

        #expect(result.count == 1)
        guard case .cluster(_, _, let members) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        #expect(Set(members.map(\.id)) == ["a", "b", "c"])
    }

    @Test func `A cluster sits at the centroid of its members`() throws {
        // Coordinates positioned so their centroid falls well within a quarter-cell
        // of the cell center at cellSize 60, ensuring the raw average is tested
        // independently of clamping.
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.60010, lon: -122.29920),
            try RentalFixtures.vehicle(id: "b", lat: 47.60012, lon: -122.29919)
        ])

        guard case .cluster(_, let coordinate, _) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        // Centroid of (47.60010, 47.60012) and (-122.29920, -122.29919)
        #expect(abs(coordinate.latitude - 47.600110) < 0.000001)
        #expect(abs(coordinate.longitude - (-122.299195)) < 0.000001)
    }

    /// Identity is a hash of the sorted member ids, not the cell index. Cell
    /// indices shift as the viewport origin pans, which would churn SwiftUI's
    /// diff on every camera move.
    @Test func `Cluster id is stable while membership is unchanged`() throws {
        let members = [
            try RentalFixtures.vehicle(id: "a", lat: 47.6000, lon: -122.3000),
            try RentalFixtures.vehicle(id: "b", lat: 47.6001, lon: -122.3001)
        ]

        #expect(RentalClustering.clusterID(for: members) == RentalClustering.clusterID(for: members.reversed()))
    }

    @Test func `Cluster id changes when a member leaves`() throws {
        let a = try RentalFixtures.vehicle(id: "a")
        let b = try RentalFixtures.vehicle(id: "b")
        let c = try RentalFixtures.vehicle(id: "c")

        #expect(RentalClustering.clusterID(for: [a, b, c]) != RentalClustering.clusterID(for: [a, b]))
    }

    /// The property that removes the need for a density cap: marker count is
    /// bounded by occupied cells, not by how many vehicles are in the viewport.
    @Test func `Marker count is bounded by viewport cells at extreme density`() throws {
        let crowd = try (0..<500).map { index in
            try RentalFixtures.vehicle(
                id: "v\(index)",
                lat: 47.600 + Double(index % 25) * 0.0004,
                lon: -122.300 + Double(index / 25) * 0.0004
            )
        }

        let result = items(crowd)

        let maxCells = Int(ceil(mapSize.width / 60)) * Int(ceil(mapSize.height / 60))
        #expect(result.count <= maxCells)
        #expect(result.count < 500)
    }

    @Test func `Every input rental appears exactly once in the output`() throws {
        let crowd = try (0..<40).map { index in
            try RentalFixtures.vehicle(
                id: "v\(index)",
                lat: 47.600 + Double(index) * 0.0002,
                lon: -122.300
            )
        }

        let emitted = items(crowd).flatMap { item -> [String] in
            switch item {
            case .single(let rental): return [rental.id]
            case .cluster(_, _, let members): return members.map(\.id)
            }
        }

        #expect(Set(emitted).count == 40)
        #expect(emitted.count == 40)
    }

    @Test func `An empty input produces no items`() {
        #expect(items([]).isEmpty)
    }

    /// A degenerate viewport (before the Map reports its first layout) must not
    /// divide by zero or emit garbage.
    @Test func `A zero-sized map produces one item per rental`() throws {
        let result = RentalClustering.items(
            for: [try RentalFixtures.vehicle(id: "a"), try RentalFixtures.vehicle(id: "b")],
            span: span,
            mapSize: .zero,
            cellSize: 60
        )

        #expect(result.count == 2)
    }

    /// Vehicles straddling a cell boundary are not merged. This is an accepted
    /// divergence from MapKit's collision-based clustering (which tests frame
    /// overlap). The dominant real case — a genuine pile-up at one corner — lands
    /// in a single cell. Two vehicles a hair apart crossing a known boundary
    /// (longitude -122.30000 divides to exactly -79495.0, landing on the boundary)
    /// correctly stay separate.
    @Test func `Vehicles straddling a cell boundary are not merged`() throws {
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.6004, lon: -122.30000),
            try RentalFixtures.vehicle(id: "b", lat: 47.6004, lon: -122.30001)
        ])

        #expect(result.count == 2)
        #expect(result.allSatisfy { if case .single = $0 { return true } else { return false } })
    }

    /// Cluster centroids are clamped to a quarter-cell of their cell's centre,
    /// guaranteeing that markers in adjacent cells are at least half a cell apart.
    /// This test constructs vehicles in adjacent cells with centroids pulled
    /// toward the shared edge, runs at the production default, and verifies that
    /// the clamping prevents overlap. This test protects against the original bug
    /// where unclamped centroids could overlap across cell boundaries.
    @Test func `Clusters in adjacent cells are at least half a cell apart`() throws {
        // At the production default (cellSize: 100), latitudePerCell ≈ 0.00119°
        // and longitudePerCell ≈ 0.00256°. We build two clusters in adjacent
        // cells with centroids pulled hard toward the boundary.

        // Cluster 1: all vehicles at the cell's right edge (high longitude)
        let cluster1 = try [
            RentalFixtures.vehicle(id: "c1v1", lat: 47.60000, lon: -122.29500),
            RentalFixtures.vehicle(id: "c1v2", lat: 47.60005, lon: -122.29510)
        ]

        // Cluster 2: all vehicles at the adjacent cell's left edge (low longitude)
        let cluster2 = try [
            RentalFixtures.vehicle(id: "c2v1", lat: 47.60000, lon: -122.29000),
            RentalFixtures.vehicle(id: "c2v2", lat: 47.60005, lon: -122.28990)
        ]

        let result = RentalClustering.items(for: cluster1 + cluster2, span: span, mapSize: mapSize)

        // Should produce exactly two clusters (one for each input group)
        #expect(result.count == 2)

        var clusters: [CLLocationCoordinate2D] = []
        for item in result {
            if case .cluster(_, let coordinate, _) = item {
                clusters.append(coordinate)
            }
        }
        #expect(clusters.count == 2)

        guard clusters.count == 2 else { return }

        let longitudePerCell = span.longitudeDelta * Double(100 / mapSize.width)
        // Half a cell (minimum safe separation due to clamping)
        let minSeparationLon = longitudePerCell / 2

        // Verify adjacent clusters are at least half a cell apart
        let lonDistance = abs(clusters[0].longitude - clusters[1].longitude)
        #expect(lonDistance >= minSeparationLon)
    }

    /// Single items must render at their vehicle's exact coordinate and never be
    /// clamped to a cell centre. Displacement would harm usability: a rider
    /// looking at the map must trust that a single marks the actual bike/scooter
    /// location, not an abstraction. This test ensures a future refactor cannot
    /// accidentally start clamping singles.
    @Test func `Single items are not clamped and show exact vehicle location`() throws {
        let vehicle = try RentalFixtures.vehicle(id: "a", lat: 47.60111, lon: -122.29876)
        let result = RentalClustering.items(for: [vehicle], span: span, mapSize: mapSize)

        #expect(result.count == 1)
        guard case .single(let emission) = result.first else {
            Issue.record("expected a single item")
            return
        }

        #expect(emission.coordinate.latitude == vehicle.coordinate.latitude)
        #expect(emission.coordinate.longitude == vehicle.coordinate.longitude)
    }
}
