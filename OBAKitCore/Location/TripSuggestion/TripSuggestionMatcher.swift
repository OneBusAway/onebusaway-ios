//
//  TripSuggestionMatcher.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Where the rider is and how they're moving, from one location fix.
public struct RiderSample: Sendable {
    public let coordinate: CLLocationCoordinate2D
    /// Meters per second; negative when invalid.
    public let speed: CLLocationSpeed
    /// Compass degrees, 0 = north, clockwise; negative when invalid.
    public let course: CLLocationDirection
    public let timestamp: Date

    public init(coordinate: CLLocationCoordinate2D, speed: CLLocationSpeed, course: CLLocationDirection, timestamp: Date) {
        self.coordinate = coordinate
        self.speed = speed
        self.course = course
        self.timestamp = timestamp
    }

    /// This sample, with `earlier`'s speed and course standing in for its own when
    /// they're invalid (a tunnel, or briefly indoors). Without them the vehicle's fix
    /// isn't carried forward at all, and the rider's own bus looks a minute behind.
    public func fillingMotion(from earlier: RiderSample) -> RiderSample {
        RiderSample(
            coordinate: coordinate,
            speed: speed >= 0 ? speed : earlier.speed,
            course: course >= 0 ? course : earlier.course,
            timestamp: timestamp
        )
    }

    public init(location: CLLocation) {
        let course = location.courseAccuracy >= 0 ? location.course : -1
        // The same validity rule `RiderMotionGate` applies to speed.
        let speed = location.speedAccuracy >= 0 ? location.speed : -1
        self.init(coordinate: location.coordinate, speed: speed, course: course, timestamp: location.timestamp)
    }
}

/// A vehicle's last reported position, as a real-time feed gives it.
public struct VehicleSighting: Sendable {
    public let coordinate: CLLocationCoordinate2D
    /// When the vehicle reported `coordinate`, not when the response arrived.
    public let fixTime: Date
    /// Compass degrees, 0 = north, clockwise; `nil` when the feed doesn't say.
    public let heading: CLLocationDirection?

    public init(coordinate: CLLocationCoordinate2D, fixTime: Date, heading: CLLocationDirection?) {
        self.coordinate = coordinate
        self.fixTime = fixTime
        self.heading = heading
    }

    /// The sighting in a trip status, if it carries a live position for `tripID`.
    ///
    /// The position and time come from `VehicleFix`, which applies the rules for which
    /// of a status's several positions and times describe the vehicle itself.
    public init?(tripStatus: TripStatus, tripID: String) {
        guard let fix = VehicleFix(tripStatus: tripStatus, tripID: tripID) else { return nil }
        self.init(coordinate: fix.coordinate, fixTime: fix.fixTime, heading: Self.heading(fromLastKnownOrientation: tripStatus.lastKnownOrientation))
    }

    /// The compass heading in a status's `lastKnownOrientation`, if it has one.
    ///
    /// OBA servers send 0 when the feed has no bearing, and 0 converts to due east;
    /// read as a heading it would rule out every vehicle not heading east. It counts
    /// as unknown: the confirming reading compares the vehicle's own direction of
    /// travel anyway.
    static func heading(fromLastKnownOrientation orientation: Double?) -> CLLocationDirection? {
        guard let orientation, orientation.isFinite, orientation != 0 else { return nil }
        return TripSuggestionMatcher.compassHeading(fromOBAOrientation: orientation)
    }
}

/// Decides whether the rider is on a vehicle by checking that the two move together.
///
/// Every check works on an *estimate* of where the vehicle is now. Real-time fixes
/// arrive tens of seconds old (Puget Sound's average about 70 s), and a bus doing
/// 10 m/s covers 700 m in that time, so a raw fix of the rider's own bus can sit
/// well outside any sensible radius. The estimate carries the fix forward along
/// the rider's course at the rider's speed, which is exactly where the vehicle
/// would be if the rider were aboard it.
///
/// It's a dead reckoning, not the shape-following estimate the trip page uses
/// (`VehicleTrack`): that one needs the trip's shape and schedule, a fetch per
/// candidate, to rank buses that a heading and a second reading rule out anyway.
public enum TripSuggestionMatcher {
    public struct Thresholds: Sendable, Equatable {
        /// How close an estimated vehicle must be to count as a candidate.
        public var candidateDistance: CLLocationDistance = 300
        /// How close it must still be on the second reading.
        public var confirmDistance: CLLocationDistance = 150
        /// How far apart the rider's course and the vehicle's heading may point.
        public var maximumHeadingDifference: CLLocationDirection = 45
        /// A fix is carried forward at most this long; past it, it's held where it is.
        public var maximumProjection: TimeInterval = 120
        /// A fix older than this is too stale to say anything.
        public var maximumFixAge: TimeInterval = 180
        /// The vehicle must move at least this far between readings for its own
        /// direction of travel to be compared with the rider's.
        public var minimumTravelForBearing: CLLocationDistance = 25

        public init() {}
    }

    // MARK: - Candidates

    /// The distance from the rider to the vehicle's estimated position, if the vehicle
    /// is close enough and heading the same way to be the one the rider is on.
    public static func candidateDistance(
        of sighting: VehicleSighting,
        rider: RiderSample,
        thresholds: Thresholds = Thresholds()
    ) -> CLLocationDistance? {
        guard let estimate = estimatedCoordinate(of: sighting, rider: rider, thresholds: thresholds) else { return nil }
        if let heading = sighting.heading, rider.course >= 0,
           headingDifference(heading, rider.course) > thresholds.maximumHeadingDifference {
            return nil
        }
        let distance = estimate.distance(from: rider.coordinate)
        return distance <= thresholds.candidateDistance ? distance : nil
    }

    // MARK: - Confirmation

    /// The distance from the rider to the vehicle's estimated position on a second
    /// reading, taken some seconds after the first, if the vehicle is still moving
    /// with the rider.
    ///
    /// When the vehicle has reported a new position since `earlier`, its own direction
    /// of travel between the two has to agree with the rider's course too: that rules
    /// out a bus on a cross street that happened to be near at both readings.
    public static func confirmedDistance(
        of sighting: VehicleSighting,
        earlier: VehicleSighting?,
        rider: RiderSample,
        thresholds: Thresholds = Thresholds()
    ) -> CLLocationDistance? {
        guard let estimate = estimatedCoordinate(of: sighting, rider: rider, thresholds: thresholds) else { return nil }
        let distance = estimate.distance(from: rider.coordinate)
        guard distance <= thresholds.confirmDistance else { return nil }
        if let earlier, rider.course >= 0, sighting.fixTime > earlier.fixTime,
           earlier.coordinate.distance(from: sighting.coordinate) >= thresholds.minimumTravelForBearing {
            let travel = bearing(from: earlier.coordinate, to: sighting.coordinate)
            if headingDifference(travel, rider.course) > thresholds.maximumHeadingDifference {
                return nil
            }
        }
        return distance
    }

    // MARK: - Estimation

    /// Where the vehicle in `sighting` is likely to be at the rider's timestamp, if the
    /// fix is fresh enough to say.
    public static func estimatedCoordinate(
        of sighting: VehicleSighting,
        rider: RiderSample,
        thresholds: Thresholds = Thresholds()
    ) -> CLLocationCoordinate2D? {
        let age = rider.timestamp.timeIntervalSince(sighting.fixTime)
        guard age <= thresholds.maximumFixAge else { return nil }
        // Carried to the rider's timestamp, either way: a fix newer than the rider's
        // (LocationService can hold an older reading for up to a minute) moves back.
        let projection = min(max(age, -thresholds.maximumProjection), thresholds.maximumProjection)
        let direction = rider.course >= 0 ? rider.course : sighting.heading
        guard let direction, rider.speed > 0, projection != 0 else { return sighting.coordinate }
        return coordinate(from: sighting.coordinate, distance: rider.speed * projection, bearing: direction)
    }

    // MARK: - Geometry

    /// Converts an OBA orientation (0° east, counterclockwise) to a compass heading
    /// (0° north, clockwise).
    public static func compassHeading(fromOBAOrientation orientation: Double) -> CLLocationDirection {
        normalized(90 - orientation)
    }

    /// The smaller angle between two compass headings, 0–180°.
    public static func headingDifference(_ lhs: CLLocationDirection, _ rhs: CLLocationDirection) -> CLLocationDirection {
        let difference = abs(normalized(lhs) - normalized(rhs))
        return difference > 180 ? 360 - difference : difference
    }

    static func normalized(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    /// The same sphere `OnDemandGeometry` and `ShapeLine` measure on.
    private static let earthRadius = OnDemandGeometry.earthRadiusMeters

    /// The initial great-circle bearing from one coordinate to another, in compass degrees.
    static func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> CLLocationDirection {
        let lat1 = start.latitude * .pi / 180
        let lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return normalized(atan2(y, x) * 180 / .pi)
    }

    /// The coordinate `distance` meters from `start` along `bearing` (compass degrees).
    static func coordinate(from start: CLLocationCoordinate2D, distance: CLLocationDistance, bearing: CLLocationDirection) -> CLLocationCoordinate2D {
        let angular = distance / earthRadius
        let heading = bearing * .pi / 180
        let lat1 = start.latitude * .pi / 180
        let lon1 = start.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(heading))
        let lon2 = lon1 + atan2(sin(heading) * sin(angular) * cos(lat1), cos(angular) - sin(lat1) * sin(lat2))
        return CLLocationCoordinate2D(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }
}
