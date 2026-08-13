//
//  TripCameraFraming.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import MapKit

/// Decides what the camera should hold when a rider opens a trip.
///
/// Two things matter to someone tracking a bus: where the bus is, and where
/// they are. Framing the whole trip shape — several miles of it — shrinks both
/// to specks; framing the vehicle alone hides the gap the rider is watching
/// close. So the required content is the pair, and the path between them is a
/// bonus taken when it fits.
///
/// Pure geometry, deliberately: this is the part worth testing, and it needs
/// neither a map view nor a live location to be exercised.
nonisolated enum TripCameraFraming {

    /// The smallest span the camera will frame, in metres. A bus pulling up to
    /// the rider's own stop puts the two required points metres apart, and
    /// fitting that bounding rect slams the camera to maximum zoom.
    static let minimumSpan: CLLocationDistance = 400

    /// How much larger the corridor may make the framed rect before it is
    /// dropped. A trip can loop miles away from both endpoints before coming
    /// back, and framing that detour shrinks the two points the rider actually
    /// came to compare.
    static let maximumCorridorExpansion: Double = 2.5

    // MARK: - Framing

    /// The rect to frame, or `nil` when there is no vehicle position to build
    /// one around — the caller falls back to the trip's own shape there, since
    /// framing the rider alone says nothing about where the bus is.
    static func rect(
        vehicle: CLLocationCoordinate2D?,
        userLocation: CLLocationCoordinate2D?,
        corridor: [CLLocationCoordinate2D] = []
    ) -> MKMapRect? {
        guard let vehicle else { return nil }

        guard let required = rect(of: [vehicle, userLocation].compactMap { $0 }) else { return nil }

        let expanded = required.union(boundingRect(of: corridor))
        let fits = expanded.width <= required.width * maximumCorridorExpansion
            && expanded.height <= required.height * maximumCorridorExpansion

        return fits ? expanded : required
    }

    /// A framing rect around a bare list of coordinates, never degenerate.
    /// `nil` when there is nothing to frame.
    static func rect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect? {
        let rect = boundingRect(of: coordinates)
        guard !rect.isNull else { return nil }
        return expanded(rect, toAtLeast: minimumSpan)
    }

    // MARK: - The corridor between the bus and the rider

    /// The part of the trip still ahead of the bus, truncated at the point
    /// nearest the rider.
    ///
    /// Truncated rather than run to the end of the line: the trip usually
    /// continues well past the rider's stop, and framing the rest of it spends
    /// the map on track the rider will never ride.
    static func corridor(
        ahead: [CLLocationCoordinate2D],
        userLocation: CLLocationCoordinate2D?
    ) -> [CLLocationCoordinate2D] {
        guard let userLocation, !ahead.isEmpty else { return [] }
        guard let nearest = nearestIndex(in: ahead, to: userLocation) else { return [] }
        return Array(ahead.prefix(through: nearest))
    }

    private static func nearestIndex(
        in coordinates: [CLLocationCoordinate2D],
        to target: CLLocationCoordinate2D
    ) -> Int? {
        let point = MKMapPoint(target)
        return coordinates.indices.min { lhs, rhs in
            MKMapPoint(coordinates[lhs]).distance(to: point) < MKMapPoint(coordinates[rhs]).distance(to: point)
        }
    }

    // MARK: - Rect helpers

    static func boundingRect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        coordinates.reduce(MKMapRect.null) {
            $0.union(MKMapRect(origin: MKMapPoint($1), size: MKMapSize()))
        }
    }

    private static func expanded(_ rect: MKMapRect, toAtLeast metres: CLLocationDistance) -> MKMapRect {
        // Map points per metre vary with latitude, so the conversion is taken at
        // the rect's own centre rather than from a constant.
        let latitude = MKMapPoint(x: rect.midX, y: rect.midY).coordinate.latitude
        let minimum = metres * MKMapPointsPerMeterAtLatitude(latitude)

        return rect.insetBy(
            dx: -max(0, (minimum - rect.width) / 2),
            dy: -max(0, (minimum - rect.height) / 2)
        )
    }
}
