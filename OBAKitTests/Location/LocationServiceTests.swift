//
//  LocationServiceTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
@testable import OBAKit
@testable import OBAKitCore
import CoreLocation
import Testing

@MainActor
@Suite(.serialized)
final class LocationServiceTests {
    // MARK: - Authorization

    @Test func `Authorization default value is not determined`() {
        let service = LocationService(userDefaults: UserDefaults(), locationManager: LocationManagerMock())

        #expect(service.authorizationStatus == .notDetermined)
        #expect(service.currentLocation == nil)
        #expect(service.canRequestAuthorization)
    }

    @Test func `Authorization granted`() async {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        let delegate = LocDelegate()

        service.addDelegate(delegate)

        service.requestInUseAuthorization()

        await poll(until: { locationManagerMock.locationUpdatesStarted },
                   "location updates never started")
        #expect(locationManagerMock.locationUpdatesStarted)
        #expect(locationManagerMock.headingUpdatesStarted)
        #expect(delegate.location == TestData.mockSeattleLocation)
        #expect(delegate.heading == TestData.mockHeading)
        #expect(delegate.error == nil)
    }

    @Test func `Update location successive updates succeed`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        locationManagerMock.requestWhenInUseAuthorization()
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        #expect(service.currentLocation == nil)

        service.startUpdatingLocation()

        #expect(service.currentLocation == TestData.mockSeattleLocation)

        service.locationManager(CLLocationManager(), didUpdateLocations: [TestData.mockTampaLocation])

        #expect(service.currentLocation == TestData.mockTampaLocation)
    }

    @Test func `Update location with no location does not trigger updates`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        let del = LocDelegate()
        del.location = TestData.mockSeattleLocation

        service.addDelegate(del)

        service.locationManager(CLLocationManager(), didUpdateLocations: [])
        #expect(del.location == TestData.mockSeattleLocation)
    }

    @Test func `Update location with low accuracy does not trigger updates`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        service.successiveLocationComparisonWindow = 60.0
        let locManager = CLLocationManager()

        #expect(service.currentLocation == nil)

        let seattle = CLLocation(coordinate: TestData.seattleCoordinate, altitude: 100.0, horizontalAccuracy: 10.0, verticalAccuracy: 10.0, timestamp: Date())
        service.locationManager(locManager, didUpdateLocations: [seattle])
        #expect(service.currentLocation == seattle)

        let badLocation = CLLocation(coordinate: TestData.tampaCoordinate, altitude: 10.0, horizontalAccuracy: 1000, verticalAccuracy: 1000, timestamp: Date())
        service.locationManager(locManager, didUpdateLocations: [badLocation])

        #expect(service.currentLocation == seattle)
    }

    @Test func `Stop updates disables updates`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        service.stopUpdates()
        #expect(!locationManagerMock.locationUpdatesStarted)
        #expect(!locationManagerMock.headingUpdatesStarted)
    }

    @Test func `Start updates without authorization does nothing`() {
        let locationManagerMock = LocationManagerMock()
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)

        #expect(!service.isLocationUseAuthorized)
        #expect(!locationManagerMock.locationUpdatesStarted)
        #expect(!locationManagerMock.headingUpdatesStarted)

        service.startUpdates()

        #expect(!service.isLocationUseAuthorized)
        #expect(!locationManagerMock.locationUpdatesStarted)
        #expect(!locationManagerMock.headingUpdatesStarted)
    }

    @Test func `Receive errors`() {
        let locationManagerMock = LocationManagerMock()
        let service = LocationService(userDefaults: UserDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        #expect(del.error == nil)

        let err = NSError(domain: "error", code: 100, userInfo: nil)

        service.locationManager(CLLocationManager(), didFailWithError: err)

        let delError = del.error! as NSError

        #expect(delError == err)
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
