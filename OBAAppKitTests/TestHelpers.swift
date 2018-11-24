//
//  AuthorizedMockLocationService.swift
//  OBAAppKitTests
//
//  Created by Aaron Brethorst on 11/23/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import OBALocationKit

class AuthorizedMockLocationManager: NSObject, LocationManager {
    var delegate: CLLocationManagerDelegate?

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
