//
//  MockAuthorizedLocationManager.swift
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

class MockAuthorizedLocationManager: NSObject, LocationManager {
    weak var delegate: CLLocationManagerDelegate?

    private let updateLocation: CLLocation
    private let updateHeading: CLHeading

    var updatingLocation = false
    var updatingHeading = false
    private(set) var monitoredRegions = Set<CLRegion>()

    init(updateLocation: CLLocation, updateHeading: CLHeading) {
        self.updateLocation = updateLocation
        self.updateHeading = updateHeading
    }

    func requestWhenInUseAuthorization() {
        // nop, already authorized.
    }

    @available(iOS 14, *)
    func requestTemporaryFullAccuracyAuthorization(withPurposeKey purposeKey: String) {
        // nop.
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

    var authorizationStatus: CLAuthorizationStatus = .authorizedWhenInUse
    var isLocationServicesEnabled: Bool = true

    /// Stored so tests can toggle reduced accuracy without needing a separate
    /// mock class. Kept as `CLAccuracyAuthorization` even though it's only
    /// touched under iOS 14+ — the availability gate lives on the protocol
    /// requirement below, matching how `LocationManager` declares it.
    var overrideAccuracyAuthorization: CLAccuracyAuthorization = .fullAccuracy

    @available(iOS 14, *)
    var accuracyAuthorization: CLAccuracyAuthorization {
        return overrideAccuracyAuthorization
    }

    func startUpdatingLocation() {
        updatingLocation = true
        self.location = updateLocation
    }

    func stopUpdatingLocation() {
        updatingLocation = false
    }

    var isHeadingAvailable: Bool = true

    func startUpdatingHeading() {
        updatingHeading = true
        heading = updateHeading
    }

    func stopUpdatingHeading() {
        updatingHeading = false
    }

    func startMonitoring(for region: CLRegion) {
        monitoredRegions.insert(region)
    }

    func stopMonitoring(for region: CLRegion) {
        monitoredRegions.remove(region)
    }
}
