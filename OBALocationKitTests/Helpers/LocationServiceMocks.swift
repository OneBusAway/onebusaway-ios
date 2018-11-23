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

    public class func authorizationStatus() -> CLAuthorizationStatus {
        return .notDetermined
    }

    static func locationServicesEnabled() -> Bool {
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

    static func headingAvailable() -> Bool {
        return authorizationStatus() == .authorizedWhenInUse
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
    public static var _authorizationStatus: CLAuthorizationStatus = .notDetermined

    public init(updateLocation: CLLocation, updateHeading: OBAMockHeading) {
        self.updateLocation = updateLocation
        self.updateHeading = updateHeading
    }

    override func requestWhenInUseAuthorization() {
        AuthorizableLocationManagerMock._authorizationStatus = .authorizedWhenInUse
        delegate?.locationManager?(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)
    }

    class override func authorizationStatus() -> CLAuthorizationStatus {
        return _authorizationStatus
    }

    override func startUpdatingLocation() {
        super.startUpdatingLocation()
        if type(of: self).authorizationStatus() == .authorizedWhenInUse {
            location = updateLocation
        }
    }

    override func startUpdatingHeading() {
        super.startUpdatingHeading()
        if type(of: self).authorizationStatus() == .authorizedWhenInUse {
            heading = updateHeading
        }
    }
}
