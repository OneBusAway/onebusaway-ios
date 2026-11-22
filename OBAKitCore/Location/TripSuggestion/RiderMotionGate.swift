//
//  RiderMotionGate.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// Decides, from location fixes alone, whether the rider is moving at bus speed.
///
/// Trip suggestions stay hidden until this says yes, so a rider standing at a stop
/// next to a bus is never asked whether they're on it. It reads `CLLocation.speed`,
/// which needs no permission beyond the location access the app already has, rather
/// than CoreMotion's activity classifier: that one can't tell a bus from a car, needs
/// a Motion & Fitness prompt, and reports minutes late.
///
/// The gate opens after `sustainDuration` of fixes at or above `movingSpeed`, and
/// closes after `stoppedDuration` at or below `stoppedSpeed` (or a gap longer than `maximumGap`), so a bus waiting
/// at a red light or a stop doesn't flap the suggestion on and off.
public struct RiderMotionGate: Sendable {
    public struct Thresholds: Sendable, Equatable {
        /// Bus speed: 5 m/s is 18 km/h, faster than anyone walks or most people jog.
        public var movingSpeed: CLLocationSpeed = 5
        /// How long the rider must hold `movingSpeed` before the gate opens.
        public var sustainDuration: TimeInterval = 30
        /// Below this the rider counts as stopped (a bus at a light, or on foot).
        public var stoppedSpeed: CLLocationSpeed = 2
        /// How long the rider must stay stopped before the gate closes.
        public var stoppedDuration: TimeInterval = 120
        /// A longer silence between fixes breaks a run of fast fixes. Generous because
        /// `LocationService` drops a fix less accurate than the last for up to a minute.
        public var maximumGap: TimeInterval = 75

        public init() {}
    }

    public let thresholds: Thresholds

    /// Whether the rider is moving at bus speed.
    public private(set) var isMoving = false

    /// When the current run of fast fixes started.
    private var fastSince: Date?
    /// When the current run of slow fixes started.
    private var slowSince: Date?
    private var lastTimestamp: Date?

    public init(thresholds: Thresholds = Thresholds()) {
        self.thresholds = thresholds
    }

    /// Feeds one fix to the gate.
    ///
    /// A negative `speedAccuracy` or `speed` marks the speed invalid (Core Location's
    /// convention), as in a tunnel or indoors. Such a fix neither extends a fast run
    /// nor counts as stopped: it says nothing either way.
    ///
    /// - Returns: `isMoving` after the fix.
    @discardableResult
    public mutating func record(speed: CLLocationSpeed, speedAccuracy: CLLocationSpeedAccuracy, timestamp: Date) -> Bool {
        // An older fix arriving late (a cached one-shot reading, say) would start a
        // run in the past and make the next fix look like a long stop or a long run.
        if let lastTimestamp, timestamp < lastTimestamp {
            return isMoving
        }
        if let lastTimestamp, timestamp.timeIntervalSince(lastTimestamp) > thresholds.maximumGap {
            // Nothing is known about the silence (the app was in the background, say),
            // so the rider may have got off: start over closed.
            isMoving = false
            fastSince = nil
            slowSince = nil
        }
        lastTimestamp = timestamp

        guard speed >= 0, speedAccuracy >= 0 else {
            fastSince = nil
            return isMoving
        }

        if speed >= thresholds.movingSpeed {
            slowSince = nil
            let start = fastSince ?? timestamp
            fastSince = start
            if timestamp.timeIntervalSince(start) >= thresholds.sustainDuration {
                isMoving = true
            }
        } else if speed <= thresholds.stoppedSpeed {
            fastSince = nil
            let start = slowSince ?? timestamp
            slowSince = start
            if timestamp.timeIntervalSince(start) >= thresholds.stoppedDuration {
                isMoving = false
            }
        } else {
            // Between the two thresholds: slowing for a stop, or pulling away. Neither
            // run continues, and the gate holds where it was.
            fastSince = nil
            slowSince = nil
        }
        return isMoving
    }

    /// Convenience for a `CLLocation`.
    @discardableResult
    public mutating func record(_ location: CLLocation) -> Bool {
        record(speed: location.speed, speedAccuracy: location.speedAccuracy, timestamp: location.timestamp)
    }

    /// Forgets every fix, closing the gate.
    public mutating func reset() {
        isMoving = false
        fastSince = nil
        slowSince = nil
        lastTimestamp = nil
    }
}
