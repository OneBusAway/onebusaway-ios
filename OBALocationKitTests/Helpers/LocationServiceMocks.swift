//
//  LocationServiceMocks.swift
//  OBALocationKitTests
//
//  Created by Aaron Brethorst on 11/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import CoreLocation
import OBALocationKit
import OBATestHelpers

class LocDelegate: NSObject, LocationServiceDelegate {
    var location: CLLocation?
    var heading: CLHeading?
    var status: CLAuthorizationStatus?
    var error: Error?

    func locationService(_ service: LocationService, locationChanged location: CLLocation) {
        self.location = location
    }

    func locationService(_ service: LocationService, headingChanged heading: CLHeading) {
        self.heading = heading
    }

    func locationService(_ service: LocationService, authorizationStatusChanged status: CLAuthorizationStatus) {
        self.status = status
    }

    func locationService(_ service: LocationService, errorReceived error: Error) {
        self.error = error
    }
}

// MARK: - Location Service Mock

class LocationManagerMock: LocationManager {

    var delegate: CLLocationManagerDelegate?

    var locationUpdatesStarted = false
    var headingUpdatesStarted = false

    func requestWhenInUseAuthorization() { }

    public var authorizationStatus: CLAuthorizationStatus {
        return .notDetermined
    }

    public var isLocationServicesEnabled: Bool {
        return true
    }

    func startUpdatingLocation() {
        locationUpdatesStarted = true
    }

    func stopUpdatingLocation() {
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

    public var isHeadingAvailable: Bool {
        return authorizationStatus == .authorizedWhenInUse
    }

    func startUpdatingHeading() {
        headingUpdatesStarted = true
    }

    func stopUpdatingHeading() {
        headingUpdatesStarted = false
    }
}

// MARK: - AuthorizableLocationManagerMock

class AuthorizableLocationManagerMock: LocationManagerMock {

    var updateLocation: CLLocation?
    var updateHeading: OBAMockHeading
    public var _authorizationStatus: CLAuthorizationStatus = .notDetermined {
        didSet {
            delegate?.locationManager?(CLLocationManager(), didChangeAuthorization: _authorizationStatus)
        }
    }

    public init(updateLocation: CLLocation, updateHeading: OBAMockHeading) {
        self.updateLocation = updateLocation
        self.updateHeading = updateHeading
    }

    override func requestWhenInUseAuthorization() {
        _authorizationStatus = .authorizedWhenInUse
    }

    override var authorizationStatus: CLAuthorizationStatus {
        return _authorizationStatus
    }

    override func startUpdatingLocation() {
        super.startUpdatingLocation()
        if authorizationStatus == .authorizedWhenInUse {
            location = updateLocation
        }
    }

    override func startUpdatingHeading() {
        super.startUpdatingHeading()
        if authorizationStatus == .authorizedWhenInUse {
            heading = updateHeading
        }
    }
}
