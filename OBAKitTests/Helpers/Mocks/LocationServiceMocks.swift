//
//  LocationServiceMocks.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import OBAKit
import OBAKitCore

public class LocationManagerMock: NSObject, LocationManager {

    public weak var delegate: CLLocationManagerDelegate?

    public var locationUpdatesStarted = false
    public var headingUpdatesStarted = false

    // MARK: - Region Monitoring

    public private(set) var monitoredRegions = Set<CLRegion>()

    public func startMonitoring(for region: CLRegion) {
        monitoredRegions.insert(region)
    }

    public func stopMonitoring(for region: CLRegion) {
        monitoredRegions.remove(region)
    }

    public func requestWhenInUseAuthorization() { }

    @available(iOS 14, *)
    public func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) {
        // nop.
    }

    public var authorizationStatus: CLAuthorizationStatus {
        return .notDetermined
    }

    public func locationServicesEnabled() async -> Bool {
        return true
    }

    @available(iOS 14, *)
    public var accuracyAuthorization: CLAccuracyAuthorization {
        return .fullAccuracy
    }

    public func startUpdatingLocation() {
        locationUpdatesStarted = true
    }

    public func stopUpdatingLocation() {
        locationUpdatesStarted = false
    }

    public var location: CLLocation? {
        didSet {
            let locations = [location].compactMap {$0}
            delegate?.locationManager?(CLLocationManager(), didUpdateLocations: locations)
        }
    }

    public var heading: CLHeading? {
        didSet {
            if let heading = heading {
                delegate?.locationManager?(CLLocationManager(), didUpdateHeading: heading)
            }
        }
    }

    /// Whether the device has a magnetometer, matching what the real
    /// `isHeadingAvailable` reports (`CLLocationManager.headingAvailable()`).
    ///
    /// Stored and default-`true`, like `MockAuthorizedLocationManager`'s. It used
    /// to derive from `authorizationStatus`, which conflated capability with
    /// permission: revoking authorization made it flip to `false`, and since
    /// `LocationService.stopUpdatingHeading()` guards on it, the stop was skipped
    /// and the mock reported heading as still running. Real hardware capability
    /// does not change with authorization, so neither does this.
    public var isHeadingAvailable = true

    public func startUpdatingHeading() {
        headingUpdatesStarted = true
    }

    public func stopUpdatingHeading() {
        headingUpdatesStarted = false
    }
}

public class AuthorizableLocationManagerMock: LocationManagerMock {

    var updateLocation: CLLocation?
    var updateHeading: OBAMockHeading
    public var _authorizationStatus: CLAuthorizationStatus = .notDetermined {
        didSet {
            // The modern callback, not the iOS 14-deprecated
            // `didChangeAuthorization:`. With an iOS 18 deployment target that
            // deprecated overload is never invoked on device, so a mock that
            // called it would exercise a path that doesn't ship. The service
            // reads the status off this mock, so the argument is unused.
            delegate?.locationManagerDidChangeAuthorization?(CLLocationManager())
        }
    }

    public init(updateLocation: CLLocation, updateHeading: OBAMockHeading) {
        self.updateLocation = updateLocation
        self.updateHeading = updateHeading
    }

    public override func requestWhenInUseAuthorization() {
        _authorizationStatus = .authorizedWhenInUse
    }

    public override var authorizationStatus: CLAuthorizationStatus {
        return _authorizationStatus
    }

    /// Simulates Location Services being switched off system-wide: the app's own
    /// authorization is untouched, but every attempt to start updates comes back
    /// as `CLError.denied` instead of a fix, and `locationServicesEnabled()`
    /// reports `false`.
    public var simulatesLocationServicesOff = false

    /// When true, `locationServicesEnabled()` parks each call instead of
    /// answering from `simulatesLocationServicesOff`. The test then resumes the
    /// parked calls in whatever order it likes, which is the only deterministic
    /// way to reproduce two probes completing out of order.
    public var parksProbes = false

    /// Parked `locationServicesEnabled()` calls, oldest first.
    public private(set) var pendingProbes: [CheckedContinuation<Bool, Never>] = []

    public override func locationServicesEnabled() async -> Bool {
        guard parksProbes else { return !simulatesLocationServicesOff }
        return await withCheckedContinuation { pendingProbes.append($0) }
    }

    /// Answers the parked probe at `index` (0 is the oldest).
    public func answerProbe(at index: Int, enabled: Bool) {
        pendingProbes[index].resume(returning: enabled)
    }

    public override func startUpdatingLocation() {
        super.startUpdatingLocation()
        // Guard on either authorized status, not just `.authorizedWhenInUse`, so
        // the `.authorizedAlways` path actually delivers fixes/errors instead of
        // returning here and letting Always-authorized tests pass vacuously.
        guard authorizationStatus.isAuthorized else { return }

        if simulatesLocationServicesOff {
            delegate?.locationManager?(CLLocationManager(), didFailWithError: CLError(.denied))
        } else {
            location = updateLocation
        }
    }

    /// Mirrors `startUpdatingLocation()`: with Location Services off system-wide,
    /// no heading is delivered.
    ///
    /// `super` is still called — deliberately. Real Core Location *accepts*
    /// `startUpdatingHeading()` with services off (there is no error return, and
    /// the magnetometer is powered); it simply never delivers data. So
    /// `headingUpdatesStarted` must stay a faithful record of "the call reached
    /// the manager." Skipping `super` here would model the leak out of existence
    /// and let a service that wrongly starts heading after latching denial pass.
    public override func startUpdatingHeading() {
        super.startUpdatingHeading()
        guard authorizationStatus.isAuthorized, !simulatesLocationServicesOff else { return }

        heading = updateHeading
    }
}

class LocDelegate: NSObject, LocationServiceDelegate {
    var location: CLLocation?
    var heading: CLHeading?
    var status: CLAuthorizationStatus?
    var error: Error?
    var enteredRegionIdentifier: String?
    var monitoringFailedIdentifier: String?
    var monitoringFailedError: Error?

    func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        self.location = location
    }

    func locationService(_ service: LocationService, headingChanged heading: CLHeading?) {
        self.heading = heading
    }

    func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        self.status = status
    }

    func locationService(_ service: LocationService, errorReceived error: Error) {
        self.error = error
    }

    func locationService(_ service: LocationService, didEnterMonitoredRegion identifier: String) {
        self.enteredRegionIdentifier = identifier
    }

    func locationService(_ service: LocationService, monitoringDidFailFor identifier: String?, error: Error) {
        self.monitoringFailedIdentifier = identifier
        self.monitoringFailedError = error
    }
}
