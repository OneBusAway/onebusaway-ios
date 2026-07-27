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
    /// An isolated defaults suite. The denied latch is persisted, so these tests
    /// must not read or write each other's (or the standard suite's) state.
    private func freshDefaults() -> UserDefaults {
        return UserDefaults(suiteName: "LocationServiceTests.\(UUID().uuidString)")!
    }

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

    /// Core Location delivers an authorization callback as soon as the delegate
    /// is assigned, carrying an unchanged status. An already-authorized app must
    /// start updates from it: that is what gets the first fix in before the map
    /// settles, and without it the map opens zoomed out and jumps once the fix
    /// finally arrives at the next foreground event.
    @Test func `Authorization callback starts updates when already authorized`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        locationManagerMock._authorizationStatus = .authorizedWhenInUse
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)
        #expect(!locationManagerMock.locationUpdatesStarted)

        service.locationManagerDidChangeAuthorization(CLLocationManager())

        #expect(locationManagerMock.locationUpdatesStarted)
        #expect(locationManagerMock.headingUpdatesStarted)
        #expect(service.currentLocation == TestData.mockSeattleLocation)
    }

    /// The same callback must *not* start updates when the app isn't authorized.
    @Test func `Authorization callback does not start updates when unauthorized`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        locationManagerMock._authorizationStatus = .denied
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)

        service.locationManagerDidChangeAuthorization(CLLocationManager())

        #expect(!service.isLocationUseAuthorized)
        #expect(!locationManagerMock.locationUpdatesStarted)
    }

    /// A latch seeded from the previous launch is probed at app init rather than
    /// waiting for a foreground event, so a stale one resolves as early as possible.
    @Test func `Seeded latch is probed on authorization callback`() {
        let userDefaults = freshDefaults()

        let firstLaunchManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let firstLaunch = LocationService(userDefaults: userDefaults, locationManager: firstLaunchManager)
        firstLaunch.requestInUseAuthorization()
        firstLaunch.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        #expect(!firstLaunch.isLocationUseAuthorized)

        // Relaunch, with Location Services back on system-wide.
        let secondLaunchManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        secondLaunchManager._authorizationStatus = .authorizedWhenInUse
        let secondLaunch = LocationService(userDefaults: userDefaults, locationManager: secondLaunchManager)
        #expect(secondLaunch.authorizationStatus == .denied)

        secondLaunch.locationManagerDidChangeAuthorization(CLLocationManager())

        #expect(secondLaunch.authorizationStatus == .authorizedWhenInUse)
        #expect(secondLaunch.currentLocation == TestData.mockSeattleLocation)
    }

    // MARK: - Denied error handling

    /// A `denied` error means location is unusable even though the app's own
    /// authorization is untouched (e.g. Location Services switched off system-wide).
    /// The service should latch that, report `.denied` so the UI can explain the
    /// situation, stop updates, and re-notify delegates.
    @Test func `Denied error marks location unavailable`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        #expect(service.isLocationUseAuthorized)
        #expect(locationManagerMock.locationUpdatesStarted)
        #expect(locationManagerMock.headingUpdatesStarted)

        del.status = nil

        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        // The per-app authorization is unchanged, but the *effective* status must
        // read `.denied`: consumers switch on this value to decide whether to show
        // the "Location Services Off / Turn On in Settings" pill.
        #expect(service.authorizationStatus == .denied)
        #expect(!service.isLocationUseAuthorized)
        // Delegates were re-notified, and with the denied-like status — not the
        // stale `.authorizedWhenInUse`, which would hide the pill.
        #expect(del.status == .denied)
        // The raw error is still forwarded to delegates.
        #expect((del.error as? CLError)?.code == .denied)
        // Both location and heading updates were stopped, as Apple recommends.
        #expect(!locationManagerMock.locationUpdatesStarted)
        #expect(!locationManagerMock.headingUpdatesStarted)
    }

    /// An authorization callback whose status actually *changed* means the user
    /// made a fresh decision, so the latch is stale evidence and access is
    /// re-armed optimistically.
    @Test func `Denied error cleared by authorization status change`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)

        service.requestInUseAuthorization()
        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        #expect(!service.isLocationUseAuthorized)
        #expect(!locationManagerMock.locationUpdatesStarted)

        // The user re-enabled Location Services and promoted the app to Always.
        locationManagerMock._authorizationStatus = .authorizedAlways

        #expect(service.authorizationStatus == .authorizedAlways)
        #expect(service.isLocationUseAuthorized)
        #expect(locationManagerMock.locationUpdatesStarted)
    }

    /// Core Location fires an authorization callback whenever a delegate is
    /// assigned. One that leaves the status untouched carries no new evidence, so
    /// it must not clear the latch — doing so would re-arm location against a
    /// still-disabled subsystem and flicker the locate button and user dot.
    @Test func `Denied error survives redundant authorization callback`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        locationManagerMock.simulatesLocationServicesOff = true
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        #expect(service.authorizationStatus == .denied)

        del.status = nil
        service.locationManagerDidChangeAuthorization(CLLocationManager())

        // The callback probes instead of assuming. Location Services are still
        // off, so the probe re-fails and nothing the user can see changes.
        #expect(service.authorizationStatus == .denied)
        #expect(!service.isLocationUseAuthorized)
        #expect(del.status == nil)
        #expect(!locationManagerMock.locationUpdatesStarted)
        #expect(!locationManagerMock.headingUpdatesStarted)
    }

    /// Toggling Location Services back on system-wide does not change the app's
    /// per-app authorization, so no authorization callback need arrive. The
    /// foreground retry probes for a fix, and a successful one clears the latch.
    @Test func `Denied error cleared by foreground retry`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        locationManagerMock.simulatesLocationServicesOff = true
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        #expect(service.authorizationStatus == .denied)
        #expect(!locationManagerMock.locationUpdatesStarted)

        // Still off: the probe re-fails, and the UI is not disturbed by it.
        del.status = nil
        service.retryIfLocationServicesDenied()
        #expect(service.authorizationStatus == .denied)
        #expect(del.status == nil)
        #expect(!locationManagerMock.locationUpdatesStarted)

        // The user turned Location Services back on; now the probe yields a fix.
        locationManagerMock.simulatesLocationServicesOff = false
        service.retryIfLocationServicesDenied()

        #expect(service.authorizationStatus == .authorizedWhenInUse)
        #expect(service.isLocationUseAuthorized)
        #expect(del.status == .authorizedWhenInUse)
        #expect(service.currentLocation == TestData.mockSeattleLocation)
        #expect(locationManagerMock.locationUpdatesStarted)
        #expect(locationManagerMock.headingUpdatesStarted)
    }

    /// Location Services being off system-wide outlives the app process, but the
    /// per-app authorization that masks it reads as authorized on the next launch.
    /// The latch is persisted so a cold start doesn't advertise location as
    /// available and then retract it.
    @Test func `Denied latch persists across launches`() {
        let userDefaults = freshDefaults()

        let firstLaunchManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let firstLaunch = LocationService(userDefaults: userDefaults, locationManager: firstLaunchManager)
        firstLaunch.requestInUseAuthorization()
        firstLaunch.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        #expect(!firstLaunch.isLocationUseAuthorized)

        // Relaunch: the app is still authorized as far as Core Location is concerned.
        let secondLaunchManager = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        secondLaunchManager._authorizationStatus = .authorizedWhenInUse
        let secondLaunch = LocationService(userDefaults: userDefaults, locationManager: secondLaunchManager)

        #expect(secondLaunch.authorizationStatus == .denied)
        #expect(!secondLaunch.isLocationUseAuthorized)
    }

    /// Revoking authorization must tear the manager down. Nothing else will, and a
    /// running `CLLocationManager` keeps the location-usage indicator lit.
    @Test func `Authorization revoked stops updates`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)

        service.requestInUseAuthorization()
        #expect(locationManagerMock.locationUpdatesStarted)

        locationManagerMock._authorizationStatus = .denied

        #expect(!service.isLocationUseAuthorized)
        #expect(!locationManagerMock.locationUpdatesStarted)
    }

    /// A repeated `denied` error must not re-notify delegates — the latch only
    /// fires on a real state transition.
    @Test func `Repeated denied error does not re-notify`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))
        #expect(!service.isLocationUseAuthorized)

        del.status = nil
        service.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        // Still latched, but no authorization notification for the no-op transition.
        #expect(!service.isLocationUseAuthorized)
        #expect(del.status == nil)
    }

    /// Only a `denied` error latches unavailability; transient errors such as
    /// `locationUnknown` must not disable location.
    @Test func `Non-denied error does not mark unavailable`() {
        let locationManagerMock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        let service = LocationService(userDefaults: freshDefaults(), locationManager: locationManagerMock)

        service.requestInUseAuthorization()
        #expect(service.isLocationUseAuthorized)

        service.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

        #expect(service.isLocationUseAuthorized)
    }
}
