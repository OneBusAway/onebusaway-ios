//
//  EstimationFixtures.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
@testable import OBAKitCore

/// Synthetic geometry in meters, so a test can say "300 m along, 10 m east" and
/// mean it. Uses the same spherical earth as `ShapeLine`.
nonisolated enum EstimationFixtures {
    static let origin = CLLocationCoordinate2D(latitude: 47.6, longitude: -122.3)
    static let metersPerDegree = ShapeLine.earthRadiusMeters * .pi / 180

    /// A point `north` meters north and `east` meters east of `origin`.
    static func point(north: Double, east: Double = 0) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: origin.latitude + north / metersPerDegree,
            longitude: origin.longitude + east / (metersPerDegree * cos(origin.latitude * .pi / 180))
        )
    }

    /// Straight north, `length` meters, with a vertex every 100 m.
    static func straightLine(length: Double = 1000) -> ShapeLine {
        ShapeLine(coordinates: stride(from: 0, through: length, by: 100).map { point(north: $0) })!
    }

    static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    /// A stop `s` meters along a trip's shape, arriving and departing `at` seconds after `t0`.
    static func stop(_ s: Double, at seconds: TimeInterval, dwell: TimeInterval = 0) -> TripGeometry.StopTime {
        TripGeometry.StopTime(distanceAlongTrip: s, arrival: t0 + seconds, departure: t0 + seconds + dwell)
    }

    /// A 1000 m line at a scheduled 10 m/s, with stops at either end and `extraStops` between.
    static func tenMetersPerSecond(extraStops: [Double] = []) -> TripGeometry {
        let stops = ([0] + extraStops + [1000]).map { stop($0, at: $0 / 10) }
        return TripGeometry(shape: straightLine(), stopTimes: stops, serverTripLength: 1000)
    }

    static func fix(
        north: Double,
        east: Double = 0,
        at seconds: TimeInterval,
        vehicleID: String? = "v1",
        tripID: String = "trip",
        scheduleDeviation: TimeInterval = 0
    ) -> VehicleFix {
        VehicleFix(
            tripID: tripID,
            vehicleID: vehicleID,
            fixTime: t0 + seconds,
            coordinate: point(north: north, east: east),
            scheduleDeviation: scheduleDeviation
        )
    }
}
