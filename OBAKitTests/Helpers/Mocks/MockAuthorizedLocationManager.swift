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

    init(updateLocation: CLLocation, updateHeading: CLHeading) {
        self.updateLocation = updateLocation
        self.updateHeading = updateHeading
    }

    func requestWhenInUseAuthorization() {
        // nop, already authorized.
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
}
