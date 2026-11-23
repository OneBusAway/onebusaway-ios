//
//  ProximityMonitoring.swift
//  OBAKitCore
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

/// The outcome of a request to begin monitoring a proximity alert's geofence.
///
/// Region monitoring has no self-healing re-arm: unlike location updates, which
/// `LocationService` restarts when authorization changes, a geofence that never
/// started stays dead for the life of the alert. So "did not start" cannot be a
/// silent no-op — every case below `started` is a condition the caller is
/// expected to surface rather than swallow.
public enum ProximityMonitoringResult: Equatable, Sendable {
    /// Monitoring began with the radius the alert asked for.
    case started

    /// Monitoring began, but at a smaller radius than requested, because the
    /// device will not monitor one that large. Core Location would answer the
    /// oversize region with `CLError.regionMonitoringFailure` — asynchronous, and
    /// carrying no radius — so this case exists to state up front what that error
    /// never would: the alert fires at a different distance than the user chose.
    case startedWithClampedRadius(requested: CLLocationDistance, monitored: CLLocationDistance)

    /// Monitoring did not begin: delivering geofence events in the background
    /// requires `.authorizedAlways`, and the app holds the status carried here.
    case insufficientAuthorization(CLAuthorizationStatus)

    /// Monitoring did not begin: the app already monitors `limit` regions, which
    /// is all iOS allows. A slot must be freed before this alert can arm.
    case regionLimitReached(limit: Int)

    /// Whether a geofence is now armed, at whatever radius.
    public var isMonitoring: Bool {
        switch self {
        case .started, .startedWithClampedRadius:
            return true
        case .insufficientAuthorization, .regionLimitReached:
            return false
        }
    }
}

/// A region-monitoring failure classified by what the caller can do about it.
///
/// Core Location funnels every monitoring failure through one delegate callback
/// carrying a bare `Error`. Some are permanent and need the user to act in
/// Settings; others are the OS deferring work that resolves on its own. The
/// distinction matters in both directions: retrying a permanent failure burns
/// battery forever, and giving up on a transient one drops an alert that would
/// have armed a moment later.
@objc(OBARegionMonitoringFailureKind)
public enum RegionMonitoringFailureKind: Int, Sendable {
    /// Permanent until the user changes location authorization in Settings.
    case authorizationDenied

    /// The region itself was rejected — the app exceeded the OS limit on
    /// simultaneously monitored regions, or asked for a radius this device will
    /// not monitor. Permanent until the app changes what it asks for.
    case regionRejected

    /// The OS delayed the request rather than refusing it immediately. LocationService
    /// applies bounded exponential backoff retries; if retries are exhausted, the failure
    /// surfaces to delegates to disarm the unmonitored geofence slot.
    case transient

    /// An error Core Location does not document for this path. Treated as
    /// permanent, because retrying an unrecognized failure forever is the worse
    /// of the two ways to be wrong.
    case unknown

    public init(error: Error) {
        guard let clError = error as? CLError else {
            self = .unknown
            return
        }

        switch clError.code {
        case .denied, .regionMonitoringDenied:
            self = .authorizationDenied
        case .regionMonitoringFailure:
            self = .regionRejected
        case .regionMonitoringSetupDelayed, .regionMonitoringResponseDelayed, .network:
            self = .transient
        default:
            self = .unknown
        }
    }

    /// Whether leaving the alert armed and waiting is the right response.
    ///
    /// Consumed by `LocationService` to schedule bounded retries with backoff
    /// for transient errors rather than dropping geofences or burning battery.
    public var isTransient: Bool {
        self == .transient
    }
}

/// Policy controlling bounded retry with backoff for transient region-monitoring failures.
public struct RegionMonitoringRetryPolicy: Sendable, Equatable {
    /// Maximum number of retry attempts after the initial failure.
    public let maxAttempts: Int

    /// Base delay for the first retry attempt in seconds.
    public let initialDelay: TimeInterval

    /// Maximum delay cap for backoff in seconds.
    public let maxDelay: TimeInterval

    /// Multiplier applied to the delay for each subsequent retry attempt.
    public let backoffMultiplier: Double

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        maxDelay: TimeInterval = 10.0,
        backoffMultiplier: Double = 2.0
    ) {
        precondition(maxAttempts > 0, "maxAttempts must be greater than 0")
        precondition(initialDelay >= 0, "initialDelay must be non-negative")
        precondition(maxDelay >= initialDelay, "maxDelay must be at least initialDelay")
        precondition(backoffMultiplier >= 1.0, "backoffMultiplier must be at least 1.0")
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.backoffMultiplier = backoffMultiplier
    }

    /// Standard retry schedule: 3 attempts with exponential backoff (1.0s, 2.0s, 4.0s).
    public static let standard = RegionMonitoringRetryPolicy(
        maxAttempts: 3,
        initialDelay: 1.0,
        maxDelay: 10.0,
        backoffMultiplier: 2.0
    )

    /// Immediate retry schedule: 3 attempts with zero delay, useful for testing.
    public static let immediate = RegionMonitoringRetryPolicy(
        maxAttempts: 3,
        initialDelay: 0,
        maxDelay: 0,
        backoffMultiplier: 1.0
    )

    /// Calculates the backoff delay for a 1-based attempt count.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 0 else { return 0 }
        let calculated = initialDelay * pow(backoffMultiplier, Double(attempt - 1))
        return min(calculated, maxDelay)
    }

    /// Whether this failure kind is transient and another retry attempt is available.
    public func shouldRetry(kind: RegionMonitoringFailureKind, currentAttempt: Int) -> Bool {
        kind.isTransient && currentAttempt < maxAttempts
    }
}

/// `@objc` enums interpolate as `RegionMonitoringFailureKind(rawValue: 1)`,
/// which tells whoever is reading a device log nothing at all. Matches how
/// `CLAuthorizationStatus` is given a description in `CoreLocationExtensions`.
extension RegionMonitoringFailureKind: CustomStringConvertible {
    public var description: String {
        switch self {
        case .authorizationDenied: return "authorizationDenied"
        case .regionRejected: return "regionRejected"
        case .transient: return "transient"
        case .unknown: return "unknown"
        }
    }
}
