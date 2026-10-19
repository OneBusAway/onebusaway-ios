//
//  VehicleEstimate.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation

/// Where to draw a vehicle right now.
public struct VehicleEstimate: Sendable {
    public enum Mode: Sendable, Equatable {
        /// Moving along the shape from the last fix.
        case estimated
        /// Waiting at a terminal: before the first departure, or at the end of the trip.
        case holding
        /// The last fix is older than the horizon, so the marker stopped where the
        /// horizon left it.
        case frozen
        /// Not estimated; see `RawReason`.
        case raw(RawReason)
    }

    public enum RawReason: Sendable, Equatable {
        /// The fix is too far from the shape to place on it (a detour, bad GPS).
        /// `coordinate` is the fix itself.
        case offShape
        /// Neither a schedule nor two fixes to take a speed from. `coordinate` is the
        /// fix snapped to the shape.
        case noSpeed
    }

    public let coordinate: CLLocationCoordinate2D
    /// Meters along the client shape. `nil` when off the shape.
    public let distanceAlongShape: Double?
    /// `distanceAlongShape` as a fraction of the shape, for splitting the line.
    public let progress: Double?
    /// The way the shape runs here, degrees clockwise from north.
    public let bearingDegrees: Double?
    public let fixTime: Date
    /// How old the newest fix is, in seconds. Never negative.
    public let fixAge: TimeInterval
    public let mode: Mode
    /// Jump straight here rather than animating: the first estimate, a new vehicle,
    /// a fix too far from the marker to glide to.
    public let shouldSnap: Bool

    /// `bearingDegrees` in OBA's convention, which `TripStatus.orientation` uses and
    /// `PulsingVehicleAnnotationView` expects: 0° is east, counter-clockwise.
    public var obaOrientation: Double? {
        bearingDegrees.map { ((90 - $0).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
    }
}

/// Every constant the estimator uses. Defaults are provisional: see
/// `docs/vehicle-position-estimation.md` §4.8 and the replay evaluation.
public struct VehicleEstimationTunables: Sendable, Equatable {
    /// Stop extrapolating this long after the fix.
    public var horizon: TimeInterval = 120
    /// Never extrapolate farther than this from the fix.
    public var maxExtrapolationMeters = 800.0
    /// A fix farther than this from the shape is off it.
    public var maxProjectionMeters = 40.0
    /// Loop disambiguation: a projection this far behind the vehicle's last known
    /// position loses to one ahead of it.
    public var maxBackwardJumpMeters = 100.0
    /// Weight on observed pace for a fresh fix, against the schedule's.
    public var observedWeight = 0.7
    /// The observed weight halves every this many seconds of fix age.
    public var observedHalfLife: TimeInterval = 60
    /// Observed pace is clamped to this range of the schedule's.
    public var minPace = 0.3
    public var maxPace = 1.6
    /// Meters per second.
    public var maxSpeed = 30.0
    /// Two fixes closer or farther apart than this don't measure a pace.
    public var minObservationInterval: TimeInterval = 10
    public var maxObservationInterval: TimeInterval = 180
    /// Expected pause at each stop reached.
    public var dwell: TimeInterval = 15
    /// A fix this close to a stop is already there: no dwell at that one.
    public var dwellMinApproachMeters = 20.0
    /// A fix this close to either end of the trip holds there.
    public var terminalZoneMeters = 75.0
    /// How long the marker takes to catch up with a fix that landed ahead of it.
    public var reconcileDuration: TimeInterval = 1.5
    /// A fix this little behind the marker is noise; the marker waits it out.
    public var backwardToleranceMeters = 15.0
    /// A fix farther behind than this snaps the marker back.
    public var snapBackMeters = 150.0
    /// Ahead by more than this, the marker snaps instead of gliding. Matches
    /// `VehicleCoordinateUpdate.snapBeyondMeters`.
    public var snapForwardMeters = 500.0
    /// The longest the marker waits for the estimate to catch up before snapping back.
    public var maxHold: TimeInterval = 20

    public static let `default` = VehicleEstimationTunables()

    public init() {}
}
