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

open class OBAMockHeading : CLHeading {

    var _magneticHeading: CLLocationDirection = 0.0
    open override var magneticHeading: CLLocationDirection {
        return _magneticHeading
    }

    var _trueHeading: CLLocationDirection = 0.0
    open override var trueHeading: CLLocationDirection {
        return _trueHeading
    }

    var _headingAccuracy: CLLocationDirection = 0.0
    open override var headingAccuracy: CLLocationDirection {
        return _headingAccuracy
    }

    var _timestamp: Date
    open override var timestamp: Date {
        return _timestamp
    }

    public init(heading: CLLocationDirection, timestamp: Date = Date()) {
        self._magneticHeading = heading
        self._trueHeading = heading
        self._timestamp = timestamp

        super.init()
    }

    public required init?(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    open override var debugDescription: String {
        return "wtf is wrong with this class?"
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

// MARK: - AuthorizedLocationServiceMock

class AuthorizedLocationManagerMock: LocationManagerMock {

    var updateLocation: CLLocation?
    var updateHeading: OBAMockHeading

    public init(updateLocation: CLLocation, updateHeading: OBAMockHeading) {
        self.updateLocation = updateLocation
        self.updateHeading = updateHeading
    }

    override func requestWhenInUseAuthorization() {
        delegate?.locationManager?(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)
    }

    class override func authorizationStatus() -> CLAuthorizationStatus {
        return .authorizedWhenInUse
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
