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
    private let region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 47.6000, longitude: -122.3000),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    private let mapSize = CGSize(width: 390, height: 844)

    private func items(_ rentals: [VehicleRental]) -> [RentalMapItem] {
        let mapRect = MKMapRect(region)
        return RentalClustering.items(for: rentals, mapRect: mapRect, mapSize: mapSize, cellSize: 60)
    }

    /// Computes cell indices for coordinates in map-point space (for verification).
    private func cellIndices(for coordinates: [CLLocationCoordinate2D], cellSize: CGFloat = 60) -> [(CLLocationCoordinate2D, Int, Int)] {
        let mapRect = MKMapRect(region)
        let rawCellPoints = Double(cellSize) * (mapRect.width / Double(mapSize.width))
        let cellPoints = pow(2.0, (log2(rawCellPoints) * 4).rounded() / 4)

        return coordinates.map { coord in
            let p = MKMapPoint(coord)
            let row = Int(floor(p.y / cellPoints))
            let column = Int(floor(p.x / cellPoints))
            return (coord, row, column)
        }
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
        // Coordinates chosen to be mid-cell in map-point space. For cellSize 60 and
        // this region, cellPoints = 2048 map points. The three vehicles below
        // land in the same cell (row: 76991, column: 35331).
        let coordinates = [
            CLLocationCoordinate2D(latitude: 47.60010, longitude: -122.29930),
            CLLocationCoordinate2D(latitude: 47.60012, longitude: -122.29928),
            CLLocationCoordinate2D(latitude: 47.60014, longitude: -122.29926)
        ]
        let _ = cellIndices(for: coordinates)  // Verified: same cell

        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: coordinates[0].latitude, lon: coordinates[0].longitude),
            try RentalFixtures.vehicle(id: "b", lat: coordinates[1].latitude, lon: coordinates[1].longitude),
            try RentalFixtures.vehicle(id: "c", lat: coordinates[2].latitude, lon: coordinates[2].longitude)
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
        // of the cell center at cellSize 60, ensuring the map-point centroid is tested
        // independently of clamping. Both land in the same cell (row: 76991, column: 35331).
        let coordinates = [
            CLLocationCoordinate2D(latitude: 47.60005, longitude: -122.29935),
            CLLocationCoordinate2D(latitude: 47.60015, longitude: -122.29925)
        ]
        let _ = cellIndices(for: coordinates)  // Verified: same cell

        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: coordinates[0].latitude, lon: coordinates[0].longitude),
            try RentalFixtures.vehicle(id: "b", lat: coordinates[1].latitude, lon: coordinates[1].longitude)
        ])

        guard case .cluster(_, let coordinate, _) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        // Centroid in map-point space converted back to coordinate. Expected lat: 47.60010, lon: -122.29930
        #expect(abs(coordinate.latitude - 47.600100) < 0.000001)
        #expect(abs(coordinate.longitude - (-122.299300)) < 0.000001)
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
        let mapRect = MKMapRect(region)
        let result = RentalClustering.items(
            for: [try RentalFixtures.vehicle(id: "a"), try RentalFixtures.vehicle(id: "b")],
            mapRect: mapRect,
            mapSize: .zero,
            cellSize: 60
        )

        #expect(result.count == 2)
    }

    /// Vehicles straddling a cell boundary are not merged. This is an accepted
    /// divergence from MapKit's collision-based clustering (which tests frame
    /// overlap). Two vehicles ~4 m apart either side of the boundary at lon -122.299974179
    /// (cellSize 60, cellPoints = 2048 map points, boundary ≈ 1217.75 map points per cell)
    /// land in different cells (columns 35330 and 35331) and correctly stay separate, even
    /// though MapKit's collision-based approach would have merged them.
    @Test func `Vehicles straddling a cell boundary are not merged`() throws {
        let coordinates = [
            CLLocationCoordinate2D(latitude: 47.6000, longitude: -122.300001001),
            CLLocationCoordinate2D(latitude: 47.6000, longitude: -122.299947357)
        ]
        let _ = cellIndices(for: coordinates)  // Verified: columns 35330 and 35331 (different)

        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: coordinates[0].latitude, lon: coordinates[0].longitude),
            try RentalFixtures.vehicle(id: "b", lat: coordinates[1].latitude, lon: coordinates[1].longitude)
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
        // In map-point space (cellSize: 100), cellPoints = 2048.0 map points.
        // Boundary at longitude -122.294311523 (x = 43028480.0 in map points).
        // All four vehicles share latitude 47.60000 (row 45779).
        // Cluster 1 at column 21009, Cluster 2 at column 21010 (adjacent, differ by 1).
        // Unclamped centroid separation: 80 map points (0.039 of a cell).
        // Clamped separation: 1024 map points (0.500 of a cell, exactly the guarantee).

        // Cluster 1: vehicles hugging the right edge of the shared boundary
        let cluster1Coords = [
            CLLocationCoordinate2D(latitude: 47.60000, longitude: -122.294338346),
            CLLocationCoordinate2D(latitude: 47.60000, longitude: -122.294391990)
        ]

        // Cluster 2: vehicles hugging the left edge of the shared boundary
        let cluster2Coords = [
            CLLocationCoordinate2D(latitude: 47.60000, longitude: -122.294284701),
            CLLocationCoordinate2D(latitude: 47.60000, longitude: -122.294231057)
        ]

        let cluster1Indices = cellIndices(for: cluster1Coords, cellSize: 100)
        let cluster2Indices = cellIndices(for: cluster2Coords, cellSize: 100)
        // Verified: columns 21009 and 21010 (adjacent, differ by exactly 1)
        #expect(cluster1Indices.allSatisfy { $0.2 == 21009 })
        #expect(cluster2Indices.allSatisfy { $0.2 == 21010 })

        let cluster1 = try cluster1Coords.enumerated().map { i, coord in
            try RentalFixtures.vehicle(id: "c1v\(i+1)", lat: coord.latitude, lon: coord.longitude)
        }
        let cluster2 = try cluster2Coords.enumerated().map { i, coord in
            try RentalFixtures.vehicle(id: "c2v\(i+1)", lat: coord.latitude, lon: coord.longitude)
        }

        let mapRect = MKMapRect(region)
        let result = RentalClustering.items(for: cluster1 + cluster2, mapRect: mapRect, mapSize: mapSize, cellSize: 100)

        // Should produce exactly two clusters (one for each input group). Without clamping,
        // unclamped centroids 80 map points apart (0.039 cells) would overlap and merge.
        // With clamping to quarter-cell, they separate to 1024 map points (0.5 cells),
        // preventing merge and demonstrating the clamp guarantee.
        #expect(result.count == 2)

        var clusters: [CLLocationCoordinate2D] = []
        for item in result {
            if case .cluster(_, let coordinate, _) = item {
                clusters.append(coordinate)
            }
        }
        #expect(clusters.count == 2)
    }

    /// Single items must render at their vehicle's exact coordinate and never be
    /// clamped to a cell centre. Displacement would harm usability: a rider
    /// looking at the map must trust that a single marks the actual bike/scooter
    /// location, not an abstraction. This test ensures a future refactor cannot
    /// accidentally start clamping singles.
    @Test func `Single items are not clamped and show exact vehicle location`() throws {
        let vehicle = try RentalFixtures.vehicle(id: "a", lat: 47.60111, lon: -122.29876)
        let mapRect = MKMapRect(region)
        let result = RentalClustering.items(for: [vehicle], mapRect: mapRect, mapSize: mapSize)

        #expect(result.count == 1)
        guard case .single(let emission) = result.first else {
            Issue.record("expected a single item")
            return
        }

        #expect(emission.coordinate.latitude == vehicle.coordinate.latitude)
        #expect(emission.coordinate.longitude == vehicle.coordinate.longitude)
    }

    /// Pan invariance: clustering the same vehicles with two MKMapRects that differ
    /// only in origin (identical size) must produce identical output. This catches
    /// the regression where degree-space bucketing caused pan-induced re-bucketing.
    @Test func `Pan invariance - same vehicles cluster identically when rect translates`() throws {
        let vehicles = try [
            RentalFixtures.vehicle(id: "a", lat: 47.59990, lon: -122.30010),
            RentalFixtures.vehicle(id: "b", lat: 47.60000, lon: -122.30000),
            RentalFixtures.vehicle(id: "c", lat: 47.60010, lon: -122.29990)
        ]

        let baseMapRect = MKMapRect(region)

        // Create a translated mapRect (panning north by ~111 m in map points)
        let translatedMapRect = MKMapRect(
            x: baseMapRect.origin.x,
            y: baseMapRect.origin.y + 2500,  // Translate in projected space
            width: baseMapRect.width,
            height: baseMapRect.height
        )

        let result1 = RentalClustering.items(for: vehicles, mapRect: baseMapRect, mapSize: mapSize, cellSize: 60)
        let result2 = RentalClustering.items(for: vehicles, mapRect: translatedMapRect, mapSize: mapSize, cellSize: 60)

        #expect(result1.count == result2.count)

        // Extract item IDs from both results for comparison
        let ids1 = Set(result1.flatMap { item -> [String] in
            switch item {
            case .single(let rental): return [rental.id]
            case .cluster(_, _, let members): return members.map(\.id)
            }
        })

        let ids2 = Set(result2.flatMap { item -> [String] in
            switch item {
            case .single(let rental): return [rental.id]
            case .cluster(_, _, let members): return members.map(\.id)
            }
        })

        #expect(ids1 == ids2)
    }

    /// Regression test for the reported symptom: panning north caused clusters to
    /// re-bucket (e.g. 10+10 → 12+8). In degree-space, the span's latitudeDelta
    /// changes with Mercator projection as you pan, shifting cell boundaries. In
    /// map-point space, panning is a pure translation with constant cell boundaries.
    @Test func `Panning north does not re-bucket vehicles`() throws {
        let vehicles = try [
            RentalFixtures.vehicle(id: "v01", lat: 47.59990, lon: -122.30010),
            RentalFixtures.vehicle(id: "v02", lat: 47.59991, lon: -122.30009),
            RentalFixtures.vehicle(id: "v03", lat: 47.59992, lon: -122.30008),
            RentalFixtures.vehicle(id: "v04", lat: 47.59993, lon: -122.30007),
            RentalFixtures.vehicle(id: "v05", lat: 47.59994, lon: -122.30006),
            RentalFixtures.vehicle(id: "v06", lat: 47.59995, lon: -122.30005),
            RentalFixtures.vehicle(id: "v07", lat: 47.59996, lon: -122.30004),
            RentalFixtures.vehicle(id: "v08", lat: 47.59997, lon: -122.30003),
            RentalFixtures.vehicle(id: "v09", lat: 47.59998, lon: -122.30002),
            RentalFixtures.vehicle(id: "v10", lat: 47.59999, lon: -122.30001),
            RentalFixtures.vehicle(id: "v11", lat: 47.60010, lon: -122.29990),
            RentalFixtures.vehicle(id: "v12", lat: 47.60011, lon: -122.29989),
            RentalFixtures.vehicle(id: "v13", lat: 47.60012, lon: -122.29988),
            RentalFixtures.vehicle(id: "v14", lat: 47.60013, lon: -122.29987),
            RentalFixtures.vehicle(id: "v15", lat: 47.60014, lon: -122.29986),
            RentalFixtures.vehicle(id: "v16", lat: 47.60015, lon: -122.29985),
            RentalFixtures.vehicle(id: "v17", lat: 47.60016, lon: -122.29984),
            RentalFixtures.vehicle(id: "v18", lat: 47.60017, lon: -122.29983),
            RentalFixtures.vehicle(id: "v19", lat: 47.60018, lon: -122.29982),
            RentalFixtures.vehicle(id: "v20", lat: 47.60019, lon: -122.29981)
        ]

        let baseMapRect = MKMapRect(region)

        // Pan north by ~500 m (translate in projected space)
        let pannedMapRect = MKMapRect(
            x: baseMapRect.origin.x,
            y: baseMapRect.origin.y + 12_000,
            width: baseMapRect.width,
            height: baseMapRect.height
        )

        let resultBefore = RentalClustering.items(for: vehicles, mapRect: baseMapRect, mapSize: mapSize, cellSize: 60)
        let resultAfter = RentalClustering.items(for: vehicles, mapRect: pannedMapRect, mapSize: mapSize, cellSize: 60)

        // Extract membership maps: cluster id → set of member ids
        func membershipMap(_ items: [RentalMapItem]) -> [String: Set<String>] {
            var map: [String: Set<String>] = [:]
            for item in items {
                switch item {
                case .single(let rental):
                    map[rental.id] = Set([rental.id])
                case .cluster(let id, _, let members):
                    map[id] = Set(members.map(\.id))
                }
            }
            return map
        }

        let membersBefore = membershipMap(resultBefore)
        let membersAfter = membershipMap(resultAfter)

        // For each vehicle, it should be grouped with the same set of companions
        for vehicle in vehicles {
            let companionsBefore = membersBefore.values.first { $0.contains(vehicle.id) } ?? Set([vehicle.id])
            let companionsAfter = membersAfter.values.first { $0.contains(vehicle.id) } ?? Set([vehicle.id])
            #expect(companionsBefore == companionsAfter, "Vehicle \(vehicle.id) changed clusters when panning north")
        }
    }
}
