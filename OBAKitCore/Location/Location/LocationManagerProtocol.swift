//
//  LocationManagerProtocol.swift
//  OBAKit
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation

public protocol LocationManager {
    var delegate: CLLocationManagerDelegate? { get set }

    // MARK: - Authorization

    func requestWhenInUseAuthorization()

    @available(iOS 14, *)
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String)

    /// Replaces the CLLocationManager class func of the same name. This is used
    /// to facilitate easier testing on a per-instance basis instead of having
    /// to try to mock class functions.
    var authorizationStatus: CLAuthorizationStatus { get }

    /// Whether Location Services are enabled system-wide.
    ///
    /// Wraps `CLLocationManager.locationServicesEnabled()`, which Apple documents
    /// as a synchronous, potentially long-blocking call that must not run on the
    /// main thread. This is `async` so the real implementation can hop the read
    /// off-main; it is the authoritative signal for the system-wide switch, which
    /// per-app authorization and `didFailWithError` only approximate.
    ///
    /// `@MainActor` because the only caller is the main-actor `LocationService`
    /// and the mocks hold main-actor state — the off-main hop happens *inside*
    /// the real implementation, not at this boundary.
    @MainActor func locationServicesEnabled() async -> Bool

    @available(iOS 14, *)
    var accuracyAuthorization: CLAccuracyAuthorization { get }

    // MARK: - Location

    func startUpdatingLocation()
    func stopUpdatingLocation()
    var location: CLLocation? { get }

    // MARK: - Heading
    var isHeadingAvailable: Bool { get }
    func startUpdatingHeading()
    func stopUpdatingHeading()

    // MARK: - Region Monitoring
    func startMonitoring(for region: CLRegion)
    func stopMonitoring(for region: CLRegion)
    var monitoredRegions: Set<CLRegion> { get }
}

extension CLLocationManager: LocationManager {
    // nop. CLLocationManager already implements all of the protocol methods.

    /// Reads the class-level `locationServicesEnabled()` off the main thread.
    /// The call is a blocking XPC round-trip; hopping to a detached task keeps
    /// it from hanging the main thread (the whole point of this method). The
    /// method is `@MainActor` per the protocol, but its work runs on the
    /// detached task, so awaiting it never blocks the main thread.
    @MainActor public func locationServicesEnabled() async -> Bool {
        await Task.detached { CLLocationManager.locationServicesEnabled() }.value
    }

    public var isHeadingAvailable: Bool {
        return CLLocationManager.headingAvailable()
    }
}
