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

        do {
            _ = try await service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
            Issue.record("Expected requestLocation to throw")
        } catch {
            #expect((error as? CLError)?.code == .locationUnknown)
        }
    }

    @Test func `Concurrent callers share one manager request`() async throws {
        let manager = authorizedManager()
        manager.deliversOneShotSynchronously = false
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        async let first = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        async let second = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)

        // Wait for both callers to suspend, not just the first: delivering
        // between them would resolve only one and let the other issue its own request.
        await poll(until: { service.pendingOneShotRequests.count == 2 }, "both callers never suspended")
        #expect(manager.requestLocationCount == 1)

        manager.deliverPendingOneShot()
        let (a, b) = try await (first, second)

        #expect(a === TestData.mockSeattleLocation)
        #expect(a === b)
        #expect(manager.requestLocationCount == 1)
    }

    @Test func `Stopping updates while a one-shot is pending fails the waiter with notAuthorized`() async throws {
        let manager = authorizedManager()
        manager.deliversOneShotSynchronously = false
        let service = LocationService(userDefaults: userDefaults, locationManager: manager, startsUpdatesOnAuthorization: false)

        async let fix = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        await poll(until: { manager.requestLocationCount == 1 }, "the one-shot never reached the manager")

        // Revoke through the real delegate path. This mock's `authorizationStatus`
        // has no change hook, so fire the callback Core Location would send.
        manager.authorizationStatus = .denied
        manager.delegate?.locationManagerDidChangeAuthorization?(CLLocationManager())

        do {
            _ = try await fix
            Issue.record("Expected the pending one-shot to fail")
        } catch {
            #expect(error as? LocationServiceError == .notAuthorized)
        }

        // Re-authorize. The next request must reach the manager, proving the
        // single-flight guard did not get stuck behind the failed waiter.
        manager.authorizationStatus = .authorizedWhenInUse
        manager.delegate?.locationManagerDidChangeAuthorization?(CLLocationManager())

        async let second = service.requestLocation(desiredAccuracy: kCLLocationAccuracyHundredMeters)
        await poll(until: { manager.requestLocationCount == 2 }, "a later request never reached the manager")
        manager.deliverPendingOneShot()
        let secondFix = try await second
        #expect(secondFix === TestData.mockSeattleLocation)
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
