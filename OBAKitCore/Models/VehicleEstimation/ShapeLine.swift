//
//  ShapeLine.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// A trip's shape measured in meters: the polyline, and how far along it each
/// vertex is. Positions on it are a distance along it, `s`, in `[0, length]`.
///
/// Lengths are great-circle (haversine) on a sphere. Projection works in a local
/// flat approximation per segment: segments are tens of meters long, where the
/// error against the sphere is far below GPS noise.
public struct ShapeLine: Sendable {
    /// The same sphere `OnDemandGeometry` measures on.
    public static let earthRadiusMeters = OnDemandGeometry.earthRadiusMeters

    public let coordinates: [CLLocationCoordinate2D]
    /// `cumulative[i]` is the distance along the shape of `coordinates[i]`.
    public let cumulative: [Double]

    public var length: Double { cumulative[cumulative.count - 1] }

    /// `nil` for fewer than two points or a shape with no length: there is no line
    /// to put a vehicle on.
    public init?(coordinates: [CLLocationCoordinate2D]) {
        guard coordinates.count >= 2 else { return nil }
        var cumulative = [0.0]
        cumulative.reserveCapacity(coordinates.count)
        for (from, to) in zip(coordinates, coordinates.dropFirst()) {
            cumulative.append(cumulative[cumulative.count - 1] + Self.distance(from, to))
        }
        guard cumulative[cumulative.count - 1] > 0 else { return nil }
        self.coordinates = coordinates
        self.cumulative = cumulative
    }

    // MARK: - Distance → point

    public struct Location: Sendable {
        public let coordinate: CLLocationCoordinate2D
        /// The direction the shape runs here, degrees clockwise from north, `[0, 360)`.
        public let bearingDegrees: Double
    }

    /// The point `s` meters along the shape, clamped to its ends. O(log n).
    public func point(at s: Double) -> Location {
        let s = min(max(s, 0), length)
        let index = segmentIndex(containing: s)
        let from = coordinates[index], to = coordinates[index + 1]
        let segmentLength = cumulative[index + 1] - cumulative[index]
        let ratio = segmentLength > 0 ? (s - cumulative[index]) / segmentLength : 0
        return Location(
            coordinate: CLLocationCoordinate2D(
                latitude: from.latitude + (to.latitude - from.latitude) * ratio,
                longitude: from.longitude + (to.longitude - from.longitude) * ratio
            ),
            bearingDegrees: OnDemandGeometry.bearingDegrees(from: from, to: to)
        )
    }

    /// The segment `[i, i + 1]` that `s` falls in, skipping zero-length segments
    /// at a vertex so the bearing comes from a segment that goes somewhere.
    private func segmentIndex(containing s: Double) -> Int {
        var low = 0, high = cumulative.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if cumulative[mid] <= s { low = mid } else { high = mid }
        }
        var index = low
        while index < coordinates.count - 2, cumulative[index + 1] - cumulative[index] == 0 { index += 1 }
        return index
    }

    // MARK: - Point → distance

    public struct Projection: Sendable, Equatable {
        public let distanceAlongShape: Double
        /// How far the point is from the shape, in meters.
        public let offsetMeters: Double
    }

    /// Where on the shape a point is.
    ///
    /// A shape that loops or doubles back passes near the same point more than
    /// once. Each segment within `maxOffset` is a candidate; with a `hint` (where
    /// the vehicle was last known to be) the candidate nearest the hint wins, but
    /// never one more than `maxBackwardJump` behind it while another candidate
    /// is ahead: a vehicle does not drive its route backward. Without a hint, the
    /// nearest candidate wins.
    ///
    /// - Returns: `nil` when no segment is within `maxOffset`.
    public func project(
        _ point: CLLocationCoordinate2D,
        maxOffset: Double,
        hint: Double?,
        maxBackwardJump: Double
    ) -> Projection? {
        var candidates: [Projection] = []
        for index in 0..<(coordinates.count - 1) {
            guard let candidate = project(point, ontoSegment: index), candidate.offsetMeters <= maxOffset else { continue }
            // Neighbouring segments meeting at a vertex both report it; one will do.
            if let last = candidates.last, abs(last.distanceAlongShape - candidate.distanceAlongShape) < 1 {
                if candidate.offsetMeters < last.offsetMeters { candidates[candidates.count - 1] = candidate }
                continue
            }
            candidates.append(candidate)
        }
        guard !candidates.isEmpty else { return nil }

        guard let hint else {
            return candidates.min { $0.offsetMeters < $1.offsetMeters }
        }
        let plausible = candidates.filter { $0.distanceAlongShape >= hint - maxBackwardJump }
        return (plausible.isEmpty ? candidates : plausible).min {
            abs($0.distanceAlongShape - hint) < abs($1.distanceAlongShape - hint)
        }
    }

    private func project(_ point: CLLocationCoordinate2D, ontoSegment index: Int) -> Projection? {
        let from = coordinates[index], to = coordinates[index + 1]
        // Meters east and north of `from`.
        let metersPerDegree = Self.earthRadiusMeters * .pi / 180
        let east = cos(from.latitude * .pi / 180) * metersPerDegree
        let bx = (to.longitude - from.longitude) * east, by = (to.latitude - from.latitude) * metersPerDegree
        let px = (point.longitude - from.longitude) * east, py = (point.latitude - from.latitude) * metersPerDegree
        let lengthSquared = bx * bx + by * by
        let t = lengthSquared > 0 ? min(max((px * bx + py * by) / lengthSquared, 0), 1) : 0
        let dx = px - t * bx, dy = py - t * by
        let segmentLength = cumulative[index + 1] - cumulative[index]
        return Projection(distanceAlongShape: cumulative[index] + t * segmentLength, offsetMeters: (dx * dx + dy * dy).squareRoot())
    }

    // MARK: - Spherical helpers

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180, lat2 = b.latitude * .pi / 180
        let dLat = lat2 - lat1, dLon = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMeters * asin(min(1, h.squareRoot()))
    }
}
