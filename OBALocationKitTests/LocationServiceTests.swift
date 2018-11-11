//
//  LocationServiceTests.swift
//  OBALocationKitTests
//
//  Created by Aaron Brethorst on 11/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
@testable import OBALocationKit
import CoreLocation
import Nimble

class LocationServiceTests: XCTestCase {

    let notificationCenter = NotificationCenter.default

    // MARK: - Authorization

    func test_authorization_defaultValueIsNotDetermined() {
        let service = LocationService(locationManager: LocationServiceMock(), notificationCenter: notificationCenter)

        expect(service.authorizationStatus) == .notDetermined
        expect(service.currentLocation).to(beNil())
    }
}

class LocationServiceMock: LocationManager {
    var delegate: CLLocationManagerDelegate?

    func requestWhenInUseAuthorization() {
        //
    }

    static func authorizationStatus() -> CLAuthorizationStatus {
        return .notDetermined
    }

    static func locationServicesEnabled() -> Bool {
        return true
    }

    func startUpdatingLocation() {
        //
    }

    func stopUpdatingLocation() {
        //
    }

    var location: CLLocation?

    static func headingAvailable() -> Bool {
        return true
    }

    func startUpdatingHeading() {
        //
    }

    func stopUpdatingHeading() {
        //
    }
}
