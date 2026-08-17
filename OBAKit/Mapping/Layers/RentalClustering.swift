//
//  RentalClustering.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import MapKit
import OTPKit

/// Groups rentals that would visually collide on the SwiftUI panel map.
///
/// MapKit gives the UIKit map this for free via `clusteringIdentifier`, testing
/// actual marker frames for collision and declustering progressively as the
/// rider zooms. SwiftUI `Map` exposes nothing equivalent, so the panel buckets
/// into a fixed screen-space grid instead. The tradeoff is accepted and known:
/// two vehicles either side of a cell boundary stay separate even when they
/// overlap. The dominant real case — a pile-up at one corner — lands in one
/// cell.
///
/// This is also what makes a density cap unnecessary. Marker count is bounded by
/// *occupied cells* (screen area ÷ cell area, roughly 90 on an iPhone-sized
/// map), not by how many vehicles the viewport holds, so `RentalMapLayer`'s
/// 500-vehicle `densityBudget` never translates into 500 SwiftUI views — and no
/// vehicle is ever silently dropped to stay under a limit.
nonisolated enum RentalClustering {

    /// Buckets `rentals` into `cellSize`-point grid cells, emitting a single for
    /// a lone occupant and a cluster at the centroid otherwise.
    ///
    /// - Parameters:
    ///   - span: the visible region's span, used to convert points to degrees.
    ///   - mapSize: the map view's size in points. `.zero` before the first
    ///     layout, which yields one item per rental rather than a division by zero.
    static func items(
        for rentals: [VehicleRental],
        span: MKCoordinateSpan,
        mapSize: CGSize,
        cellSize: CGFloat = 60
    ) -> [RentalMapItem] {
        guard !rentals.isEmpty else { return [] }

        // Before the Map reports a layout there is no screen space to cluster
        // in; drawing each rental on its own is the honest fallback.
        guard mapSize.width > 0, mapSize.height > 0, cellSize > 0 else {
            return rentals.map { .single($0) }
        }

        let latitudePerCell = span.latitudeDelta * Double(cellSize / mapSize.height)
        let longitudePerCell = span.longitudeDelta * Double(cellSize / mapSize.width)

        guard latitudePerCell > 0, longitudePerCell > 0 else {
            return rentals.map { .single($0) }
        }

        // Preserves input order (which the coordinator sorts by id), so the
        // output is deterministic for a given input.
        var cellOrder: [String] = []
        var buckets: [String: [VehicleRental]] = [:]

        for rental in rentals {
            let row = Int(floor(rental.coordinate.latitude / latitudePerCell))
            let column = Int(floor(rental.coordinate.longitude / longitudePerCell))
            let key = "\(row):\(column)"
            if buckets[key] == nil {
                buckets[key] = []
                cellOrder.append(key)
            }
            buckets[key]?.append(rental)
        }

        return cellOrder.compactMap { key -> RentalMapItem? in
            guard let members = buckets[key], !members.isEmpty else { return nil }
            if members.count == 1 {
                return .single(members[0])
            }
            return .cluster(
                id: clusterID(for: members),
                coordinate: centroid(of: members),
                members: members
            )
        }
    }

    /// A cluster's identity, derived from its sorted member ids.
    ///
    /// Deliberately *not* the cell index: indices shift as the viewport origin
    /// pans, so a cell-keyed id would churn SwiftUI's `ForEach` diff on every
    /// camera move and re-create the marker views. The same id is used for the
    /// `.rentalCluster` sheet route, so an open sheet and its marker agree.
    ///
    /// Warning: `Hasher` is seeded per-process on Apple platforms, so `clusterID`
    /// is stable *within* a launch but not across launches. That is exactly the
    /// guarantee needed here (SwiftUI diffing and a live sheet route), and the
    /// tests only compare ids within one run. Do NOT persist a cluster id or send
    /// it off-device.
    static func clusterID(for members: [VehicleRental]) -> String {
        var hasher = Hasher()
        for id in members.map(\.id).sorted() {
            hasher.combine(id)
        }
        return "rentalCluster-\(hasher.finalize())"
    }

    private static func centroid(of members: [VehicleRental]) -> CLLocationCoordinate2D {
        let count = Double(members.count)
        let latitude = members.reduce(0.0) { $0 + $1.coordinate.latitude } / count
        let longitude = members.reduce(0.0) { $0 + $1.coordinate.longitude } / count
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
