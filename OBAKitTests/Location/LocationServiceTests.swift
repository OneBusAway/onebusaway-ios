//
//  LocationServiceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import XCTest
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation
import Nimble

@MainActor
class LocationServiceTests: XCTestCase {
    // MARK: - Authorization

    func test_authorization_defaultValueIsNotDetermined() {
        let service = LocationService(userDefaults: UserDefaults(), locationManager: LocationManagerMock())

        expect(service.authorizationStatus) == .notDetermined
        expect(service.currentLocation).to(beNil())
        expect(service.canRequestAuthorization).to(beTrue())
    }

    func test_authorization_granted() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
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
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        expect(service.currentLocation).to(beNil())

        service.startUpdatingLocation()

        expect(service.currentLocation) == TestData.mockSeattleLocation

        service.locationManager(CLLocationManager(), didUpdateLocations: [TestData.mockTampaLocation])

        expect(service.currentLocation) == TestData.mockTampaLocation
    }

    func test_updateLocation_withNoLocation_doesNotTriggerUpdates() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        let del = LocDelegate()
        del.location = TestData.mockSeattleLocation

        service.addDelegate(del)

        service.locationManager(CLLocationManager(), didUpdateLocations: [])
        expect(del.location) == TestData.mockSeattleLocation
    }

    func test_updateLocation_withLowAccuracy_doesNotTriggerUpdates() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        service.successiveLocationComparisonWindow = 60.0
        let locManager = CLLocationManager()

        expect(service.currentLocation).to(beNil())

        let seattle = CLLocation(coordinate: TestData.seattleCoordinate, altitude: 100.0, horizontalAccuracy: 10.0, verticalAccuracy: 10.0, timestamp: Date())
        service.locationManager(locManager, didUpdateLocations: [seattle])
        expect(service.currentLocation) == seattle

        let badLocation = CLLocation(coordinate: TestData.tampaCoordinate, altitude: 10.0, horizontalAccuracy: 1000, verticalAccuracy: 1000, timestamp: Date())
        service.locationManager(locManager, didUpdateLocations: [badLocation])

        expect(service.currentLocation) == seattle
    }

    func test_stopUpdates_disablesUpdates() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        service.stopUpdates()
        expect(locationManagerMock.locationUpdatesStarted).to(beFalse())
        expect(locationManagerMock.headingUpdatesStarted).to(beFalse())
    }

    func test_startUpdates_withoutAuthorization_doesNothing() {
        let locationManagerMock = LocationManagerMock()
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

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
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        expect(del.error).to(beNil())

        let err = NSError(domain: "error", code: 100, userInfo: nil)

        service.locationManager(CLLocationManager(), didFailWithError: err)

        let delError = del.error! as NSError

        expect(delError) == err
    }

    // MARK: - Denied error handling

    /// A `denied` error means location is unusable even though `authorizationStatus`
    /// still reads as authorized (e.g. Location Services switched off system-wide).
    /// The service should latch that, report location unavailable, stop updates, and
    /// re-notify delegates so the UI can hide its location affordances.
    func test_deniedError_marksLocationUnavailable() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        expect(service.isLocationUseAuthorized).to(beTrue())
        expect(locationManagerMock.locationUpdatesStarted).to(beTrue())
        expect(locationManagerMock.headingUpdatesStarted).to(beTrue())

        del.status = nil

        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        // Per-app authorization is unchanged, but location is now reported unavailable.
        expect(service.authorizationStatus) == .authorizedWhenInUse
        expect(service.isLocationUseAuthorized).to(beFalse())
        // Delegates were re-notified so UI (locate button, user dot) can update.
        expect(del.status).toNot(beNil())
        // The raw error is still forwarded to delegates.
        expect((del.error as? CLError)?.code) == .denied
        // Both location and heading updates were stopped, as Apple recommends.
        expect(locationManagerMock.locationUpdatesStarted).to(beFalse())
        expect(locationManagerMock.headingUpdatesStarted).to(beFalse())
    }

    /// A subsequent authorization callback (the user re-enabling access) clears the
    /// latch so location becomes usable again *and* updates resume, even though the
    /// coarse authorization status is unchanged.
    func test_deniedError_clearedByAuthorizationChange() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        service.requestInUseAuthorization()
        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        expect(service.isLocationUseAuthorized).to(beFalse())
        expect(locationManagerMock.locationUpdatesStarted).to(beFalse())

        // Status stays `.authorizedWhenInUse`, so recovery must come from the latch
        // clearing rather than an `authorizationStatus` value change.
        service.locationManager(CLLocationManager(), didChangeAuthorization: .authorizedWhenInUse)

        expect(service.isLocationUseAuthorized).to(beTrue())
        expect(locationManagerMock.locationUpdatesStarted).to(beTrue())
    }

    /// A repeated `denied` error must not re-notify delegates — the latch only
    /// fires on a real state transition.
    func test_deniedError_repeated_doesNotReNotify() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        expect(service.isLocationUseAuthorized).to(beFalse())

        del.status = nil
        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        // Still latched, but no authorization notification for the no-op transition.
        expect(service.isLocationUseAuthorized).to(beFalse())
        expect(del.status).to(beNil())
    }

    /// Only a `denied` error latches unavailability; transient errors such as
    /// `locationUnknown` must not disable location.
    func test_nonDeniedError_doesNotMarkUnavailable() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        service.requestInUseAuthorization()
        expect(service.isLocationUseAuthorized).to(beTrue())

        service.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

        expect(service.isLocationUseAuthorized).to(beTrue())
    }
}
