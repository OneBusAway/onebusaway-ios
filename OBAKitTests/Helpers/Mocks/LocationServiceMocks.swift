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

    public func requestWhenInUseAuthorization() { }

    public var authorizationStatus: CLAuthorizationStatus {
        return .notDetermined
    }

    public var isLocationServicesEnabled: Bool {
        return true
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

    public var isHeadingAvailable: Bool {
        return authorizationStatus == .authorizedWhenInUse
    }

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
            delegate?.locationManager?(CLLocationManager(), didChangeAuthorization: _authorizationStatus)
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

    public override func startUpdatingLocation() {
        super.startUpdatingLocation()
        if authorizationStatus == .authorizedWhenInUse {
            location = updateLocation
        }
    }

    public override func startUpdatingHeading() {
        super.startUpdatingHeading()
        if authorizationStatus == .authorizedWhenInUse {
            heading = updateHeading
        }
    }
}

class LocDelegate: NSObject, LocationServiceDelegate {
    var location: CLLocation?
    var heading: CLHeading?
    var status: CLAuthorizationStatus?
    var error: Error?

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
}
