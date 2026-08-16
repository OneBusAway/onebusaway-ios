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
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.6000, lon: -122.3000),
            try RentalFixtures.vehicle(id: "b", lat: 47.60001, lon: -122.30001),
            try RentalFixtures.vehicle(id: "c", lat: 47.60002, lon: -122.30002)
        ])

        #expect(result.count == 1)
        guard case .cluster(_, _, let members) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        #expect(Set(members.map(\.id)) == ["a", "b", "c"])
    }

    @Test func `A cluster sits at the centroid of its members`() throws {
        let result = items([
            try RentalFixtures.vehicle(id: "a", lat: 47.6000, lon: -122.3000),
            try RentalFixtures.vehicle(id: "b", lat: 47.6001, lon: -122.3001)
        ])

        guard case .cluster(_, let coordinate, _) = try #require(result.first) else {
            Issue.record("expected a cluster")
            return
        }
        #expect(abs(coordinate.latitude - 47.60005) < 0.000001)
        #expect(abs(coordinate.longitude - (-122.30005)) < 0.000001)
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
}
