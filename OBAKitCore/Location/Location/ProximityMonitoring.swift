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
    /// device will not monitor one that large. Core Location clamps an oversize
    /// radius silently, so this is the only signal that the alert will fire at a
    /// different distance than the user chose.
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

    /// The OS delayed the request rather than refusing it. Expected to resolve
    /// without intervention, so the alert is safe to leave armed.
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
    /// Nothing in OBAKitCore consumes this yet — it exists for the retry decision
    /// `ProximityAlertManager` has to make, which is the whole reason failures are
    /// classified at all. Keep it when wiring that up rather than re-deriving
    /// `== .transient` at the call site.
    public var isTransient: Bool {
        self == .transient
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
