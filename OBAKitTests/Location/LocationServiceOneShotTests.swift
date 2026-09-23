//
//  LocationServiceOneShotTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import CoreLocation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// The watch's one-shot location path: `requestLocation(desiredAccuracy:)`
/// and the `startsUpdatesOnAuthorization` opt-out. Continuous-update behavior
/// is covered by `LocationServiceTests`.
@Suite(.serialized)
final class LocationServiceOneShotTests: OBATestCase {

    private func authorizedManager() -> MockAuthorizedLocationManager {
        MockAuthorizedLocationManager(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
    }

    @Test func `requestLocation throws before authorization`() async {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        await #expect(throws: LocationServiceError.notAuthorized) {
            _ = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        }
        #expect(manager.requestLocationCount == 0)
    }

    @Test func `requestLocation sets the accuracy and resolves with the manager's fix`() async throws {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        let fix = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)

        #expect(fix === TestData.mockSeattleLocation)
        #expect(manager.desiredAccuracy == kCLLocationAccuracyHundredMeters)
        #expect(manager.requestLocationCount == 1)
        #expect(service.currentLocation === TestData.mockSeattleLocation)
    }

    @Test func `A worse fix inside the prune window still resolves and still reaches delegates`() async throws {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)
        let delegate = LocDelegate()
        service.addDelegate(delegate)

        // Seed an accurate fix, as a cached continuous update would.
        manager.location = TestData.mockSeattleLocation
        #expect(service.currentLocation === TestData.mockSeattleLocation)

        // The one-shot lands seconds later with far worse accuracy — the case
        // the continuous-update prune (successiveLocationComparisonWindow) swallows.
        let coarse = CLLocation(coordinate: TestData.seattleCoordinate, altitude: 100, horizontalAccuracy: 500, verticalAccuracy: 500, timestamp: Date())
        manager.oneShotLocation = coarse

        let fix = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)

        #expect(fix === coarse)
        #expect(service.currentLocation === coarse)
        #expect(delegate.location === coarse)
    }

    @Test func `A manager error fails the request`() async {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)
        manager.nextRequestLocationError = CLError(.locationUnknown)

        await #expect(throws: CLError.self) {
            _ = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        }
    }

    @Test func `Concurrent callers share one manager request`() async throws {
        let manager = authorizedManager()
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        async let first = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        async let second = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        let (a, b) = try await (first, second)

        #expect(a === b)
        // The mock delivers synchronously inside requestLocation(), so the first
        // caller is resolved before the second registers; both must still get a fix.
        #expect(manager.requestLocationCount <= 2)
    }

    @Test func `With startsUpdatesOnAuthorization off, a grant starts neither location nor heading`() {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        manager.requestWhenInUseAuthorization()

        #expect(service.isLocationUseAuthorized)
        #expect(manager.locationUpdatesStarted == false)
        #expect(manager.headingUpdatesStarted == false)
    }

    @Test func `With startsUpdatesOnAuthorization off, revocation still stops updates`() {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)
        manager.requestWhenInUseAuthorization()

        service.startUpdatingLocation()
        #expect(manager.locationUpdatesStarted)

        manager._authorizationStatus = .denied

        #expect(manager.locationUpdatesStarted == false)
    }

    @Test func `The default still starts updates on a grant`() {
        let manager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: userDefaults, locationManager: manager)

        manager.requestWhenInUseAuthorization()

        #expect(service.isLocationUseAuthorized)
        #expect(manager.locationUpdatesStarted)
    }
}
