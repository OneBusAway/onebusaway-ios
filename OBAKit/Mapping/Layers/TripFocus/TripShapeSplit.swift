//
//  TripShapeSplit.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// Cuts a trip's shape into the part the vehicle has already covered and the
/// part still ahead of it, so the two can be drawn in different colors.
///
/// Progress arrives as a fraction rather than a distance on purpose. OBA reports
/// `distanceAlongTrip` against the agency's own measure of the trip, which is not
/// the length of the polyline we drew — different source data, different
/// generalization. Measuring the fraction against the shape's *own* length keeps
/// the split point on the line the rider is looking at, which is what matters
/// here; using the raw meters would drift the vehicle off the drawn shape
/// wherever the two measures disagree.
nonisolated enum TripShapeSplit {

    struct Result {
        /// Behind the vehicle. Empty when the trip hasn't started.
        var spent: [CLLocationCoordinate2D]
        /// Ahead of the vehicle. Empty when the trip is over.
        var ahead: [CLLocationCoordinate2D]

        static let empty = Result(spent: [], ahead: [])
    }

    /// How far along the trip the vehicle is, as a fraction of the whole.
    ///
    /// - Returns: `nil` when the trip reports no total distance — a schedule-only
    ///   trip, or a feed that omits the field. There is no progress to draw, which
    ///   is different from progress of zero.
    static func fraction(distanceAlongTrip: Double, totalDistanceAlongTrip: Double) -> Double? {
        guard totalDistanceAlongTrip > 0 else { return nil }
        return min(max(distanceAlongTrip / totalDistanceAlongTrip, 0), 1)
    }

    static func split(coordinates: [CLLocationCoordinate2D], atFraction fraction: Double) -> Result {
        // One point is not a line; there is nothing to draw on either side of a cut.
        guard coordinates.count >= 2 else { return .empty }

        let clamped = min(max(fraction, 0), 1)
        if clamped <= 0 { return Result(spent: [], ahead: coordinates) }
        if clamped >= 1 { return Result(spent: coordinates, ahead: []) }

        let segmentLengths = zip(coordinates, coordinates.dropFirst()).map(distance)
        let totalLength = segmentLengths.reduce(0, +)

        // A shape that never moves has no length to take a fraction of. Calling
        // any of it travelled would be arbitrary, so none of it is.
        guard totalLength > 0 else { return Result(spent: [], ahead: coordinates) }

        let target = totalLength * clamped

        var travelled = 0.0
        for (index, segmentLength) in segmentLengths.enumerated() {
            let segmentEnd = travelled + segmentLength

            guard segmentEnd >= target else {
                travelled = segmentEnd
                continue
            }

            // The cut lands inside this segment. Both halves get the split point,
            // so the two overlays meet at the vehicle instead of leaving a gap.
            let ratio = segmentLength > 0 ? (target - travelled) / segmentLength : 0

            // A cut that lands on one of the shape's own vertices needs that
            // vertex, not an interpolated copy of it sitting on top of it. The
            // tolerance matters as much as the dedup: segment lengths are
            // geodesic, so a cut the caller thinks is exactly on a vertex lands
            // a hair either side of it, and without this the two cases would
            // produce different point counts for the same picture.
            if ratio <= Self.vertexTolerance {
                return normalized(spent: Array(coordinates[...index]), ahead: Array(coordinates[index...]))
            }
            if ratio >= 1 - Self.vertexTolerance {
                return normalized(spent: Array(coordinates[...(index + 1)]), ahead: Array(coordinates[(index + 1)...]))
            }

            let join = interpolate(from: coordinates[index], to: coordinates[index + 1], ratio: ratio)
            return normalized(
                spent: Array(coordinates[...index]) + [join],
                ahead: [join] + Array(coordinates[(index + 1)...])
            )
        }

        // Floating-point residue can leave the loop without ever reaching the
        // target even though `clamped < 1`. The vehicle is at the end.
        return Result(spent: coordinates, ahead: [])
    }

    /// How close to a segment's end a cut has to fall before it counts as landing
    /// on the vertex itself. Expressed as a fraction of the segment.
    private static let vertexTolerance = 1e-9

    /// Drops a half that came out too short to draw. A single point is not a
    /// line, and handing `MKPolyline` one produces an overlay that renders as
    /// nothing while still occupying the map's overlay list.
    private static func normalized(spent: [CLLocationCoordinate2D], ahead: [CLLocationCoordinate2D]) -> Result {
        Result(spent: spent.count >= 2 ? spent : [], ahead: ahead.count >= 2 ? ahead : [])
    }

    private static func distance(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    /// Straight-line interpolation in degrees. Shape vertices sit tens of metres
    /// apart, a scale at which the error against a great-circle interpolation is
    /// far below one rendered pixel.
    private static func interpolate(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        ratio: Double
    ) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: from.latitude + (to.latitude - from.latitude) * ratio,
            longitude: from.longitude + (to.longitude - from.longitude) * ratio
        )
    }
}
