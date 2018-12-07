//
//  LocationServiceTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 11/11/18.
//  Copyright © 2018 OneBusAway. All rights reserved.
//

import Foundation
import XCTest
import OBATestHelpers
@testable import OBAKit
import CoreLocation
import Nimble

class LocationServiceTests: XCTestCase {
    // MARK: - Authorization

    func test_authorization_defaultValueIsNotDetermined() {
        let service = LocationService(locationManager: LocationManagerMock())

        expect(service.authorizationStatus) == .notDetermined
        expect(service.currentLocation).to(beNil())
        expect(service.canRequestAuthorization).to(beTrue())
    }

    func test_authorization_granted() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(locationManager: locationManagerMock)
        let delegate = LocDelegate()

        service.addDelegate(delegate)

        service.requestInUseAuthorization()

        waitUntil { (done) in
            expect(locationManagerMock.locationUpdatesStarted).to(beTrue())
            expect(locationManagerMock.headingUpdatesStarted).to(beTrue())
            expect(delegate.location) == TestData.mockSeattleLocation
            expect(delegate.heading) == TestData.mockHeading
            expect(delegate.error).to(beNil())
            done()
        }
    }

    func test_updateLocation_successiveUpdates_succeed() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        locationManagerMock.requestWhenInUseAuthorization()
        let service = LocationService(locationManager: locationManagerMock)

        expect(service.currentLocation).to(beNil())

        service.startUpdatingLocation()

        expect(service.currentLocation) == TestData.mockSeattleLocation

        service.locationManager(CLLocationManager(), didUpdateLocations: [TestData.mockTampaLocation])

        expect(service.currentLocation) == TestData.mockTampaLocation
    }

    func test_updateLocation_withNoLocation_doesNotTriggerUpdates() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(locationManager: locationManagerMock)

        let del = LocDelegate()
        del.location = TestData.mockSeattleLocation

        service.addDelegate(del)

        service.locationManager(CLLocationManager(), didUpdateLocations: [])
        expect(del.location) == TestData.mockSeattleLocation
    }

    func test_updateLocation_withLowAccuracy_doesNotTriggerUpdates() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(locationManager: locationManagerMock)

        expect(service.currentLocation).to(beNil())

        service.locationManager(CLLocationManager(), didUpdateLocations: [TestData.mockSeattleLocation])
        expect(service.currentLocation) == TestData.mockSeattleLocation

        let badLocation = CLLocation(coordinate: TestData.tampaCoordinate, altitude: 10.0, horizontalAccuracy: 1000, verticalAccuracy: 1000, timestamp: Date())
        service.locationManager(CLLocationManager(), didUpdateLocations: [badLocation])

        expect(service.currentLocation) == TestData.mockSeattleLocation
    }

    func test_stopUpdates_disablesUpdates() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(locationManager: locationManagerMock)

        service.stopUpdates()
        expect(locationManagerMock.locationUpdatesStarted).to(beFalse())
        expect(locationManagerMock.headingUpdatesStarted).to(beFalse())
    }

    func test_startUpdates_withoutAuthorization_doesNothing() {
        let locationManagerMock = LocationManagerMock()
        let service = LocationService(locationManager: locationManagerMock)

        expect(service.isLocationUseAuthorized).to(beFalse())
        expect(locationManagerMock.locationUpdatesStarted).to(beFalse())
        expect(locationManagerMock.headingUpdatesStarted).to(beFalse())

        service.startUpdates()

        expect(service.isLocationUseAuthorized).to(beFalse())
        expect(locationManagerMock.locationUpdatesStarted).to(beFalse())
        expect(locationManagerMock.headingUpdatesStarted).to(beFalse())
    }

    func test_receiveErrors() {
        let locationManagerMock = LocationManagerMock()
        let service = LocationService(locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        expect(del.error).to(beNil())

        let err = NSError(domain: "error", code: 100, userInfo: nil)

        service.locationManager(CLLocationManager(), didFailWithError: err)

        let delError = del.error! as NSError

        expect(delError) == err
    }
}

