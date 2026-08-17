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
/// Bucketing occurs in the flat-projected `MKMapRect` space, not in degrees.
/// This is critical for pan stability: `MKMapRect` width and height are constant
/// at constant zoom, so panning only translates the origin without resizing.
/// Degree-space bucketing (latitude/longitude per cell derived from the span)
/// exhibits latitude dependence: the span's `latitudeDelta` changes with Mercator
/// projection as you pan north/south, causing cell boundaries to drift and
/// vehicles to be rebucketed wholesale. Projected space eliminates this amplification.
///
/// This is also what makes a density cap unnecessary. Marker count is bounded by
/// *occupied cells* (screen area ÷ cell area, roughly 90 on an iPhone-sized
/// map), not by how many vehicles the viewport holds, so `RentalMapLayer`'s
/// 500-vehicle `densityBudget` never translates into 500 SwiftUI views — and no
/// vehicle is ever silently dropped to stay under a limit.
///
/// Cluster centroids are clamped to within `cellSize/4` (a quarter-cell) of
/// their cell's centre. This guarantees that adjacent cells' markers are
/// separated by at least half a cell (50pt at the default 100pt cell size),
/// exceeding marker size and eliminating overlap by construction. Single items
/// are NOT clamped — a centroid is an abstraction whose tap opens a list, so
/// displacement is harmless, but a single must show the vehicle's exact location.
nonisolated enum RentalClustering {

    /// Buckets `rentals` into `cellSize`-point grid cells, emitting a single for
    /// a lone occupant and a cluster at the centroid otherwise.
    ///
    /// - Parameters:
    ///   - mapRect: the visible region's map rectangle in flat projected space.
    ///   - mapSize: the map view's size in points. `.zero` before the first
    ///     layout, which yields one item per rental rather than a division by zero.
    static func items(
        for rentals: [VehicleRental],
        mapRect: MKMapRect,
        mapSize: CGSize,
        cellSize: CGFloat = 100
    ) -> [RentalMapItem] {
        guard !rentals.isEmpty else { return [] }

        // Before the Map reports a layout there is no screen space to cluster
        // in; drawing each rental on its own is the honest fallback.
        guard mapSize.width > 0, mapSize.height > 0, cellSize > 0 else {
            return rentals.map { .single($0) }
        }

        guard mapRect.width > 0, mapRect.height > 0 else {
            return rentals.map { .single($0) }
        }

        // Cell size in map-point space (flat projection). Quantize to quarter-octave
        // steps to prevent residual float jitter in mapRect.width from moving boundaries.
        let rawCellPoints = Double(cellSize) * (mapRect.width / Double(mapSize.width))
        let cellPoints = quantizeToQuarterOctave(rawCellPoints)

        guard cellPoints > 0 else {
            return rentals.map { .single($0) }
        }

        // Preserves input order (which the coordinator sorts by id), so the
        // output is deterministic for a given input.
        var cellOrder: [CellIndex] = []
        var buckets: [CellIndex: [VehicleRental]] = [:]

        for rental in rentals {
            let p = MKMapPoint(rental.coordinate)
            let row = Int(floor(p.y / cellPoints))
            let column = Int(floor(p.x / cellPoints))
            let cellIndex = CellIndex(row: row, column: column)
            if buckets[cellIndex] == nil {
                buckets[cellIndex] = []
                cellOrder.append(cellIndex)
            }
            buckets[cellIndex]?.append(rental)
        }

        return cellOrder.compactMap { cellIndex -> RentalMapItem? in
            guard let members = buckets[cellIndex], !members.isEmpty else { return nil }
            if members.count == 1 {
                return .single(members[0])
            }

            let centroidMapPoint = centroidMapPoint(of: members)

            // Clamp centroid to within a quarter-cell of the cell center. Adjacent cell
            // centres are one cell apart; each clamped marker deviates at most a quarter-cell
            // toward the other, so minimum separation between clustered markers is half a cell
            // (50pt at default 100pt size). With 32pt markers, overlap becomes impossible by
            // construction rather than merely improbable.
            let cellCenterX = (Double(cellIndex.column) + 0.5) * cellPoints
            let cellCenterY = (Double(cellIndex.row) + 0.5) * cellPoints
            let clampRange = cellPoints / 4

            let clampedX = clamp(centroidMapPoint.x, min: cellCenterX - clampRange, max: cellCenterX + clampRange)
            let clampedY = clamp(centroidMapPoint.y, min: cellCenterY - clampRange, max: cellCenterY + clampRange)

            let clampedCoordinate = MKMapPoint(x: clampedX, y: clampedY).coordinate

            return .cluster(
                id: clusterID(for: members),
                coordinate: clampedCoordinate,
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

    private static func centroidMapPoint(of members: [VehicleRental]) -> MKMapPoint {
        let count = Double(members.count)
        let sumX = members.reduce(0.0) { $0 + MKMapPoint($1.coordinate).x }
        let sumY = members.reduce(0.0) { $0 + MKMapPoint($1.coordinate).y }
        return MKMapPoint(x: sumX / count, y: sumY / count)
    }

    private static func quantizeToQuarterOctave(_ value: Double) -> Double {
        guard value.isFinite, value > 0 else { return 100 }
        let log = log2(value)
        let quantized = pow(2.0, (log * 4).rounded() / 4)
        return quantized.isFinite && quantized > 0 ? quantized : 100
    }

    private static func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        if value < minValue { return minValue }
        if value > maxValue { return maxValue }
        return value
    }

    private struct CellIndex: Hashable {
        let row: Int
        let column: Int
    }
}
