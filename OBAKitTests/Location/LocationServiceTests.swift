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
    /// Suite names handed out by `freshDefaults()`, torn down in `deinit` so the
    /// test host doesn't accumulate a plist per run.
    private var createdDefaultsSuites: [String] = []

    /// An isolated defaults suite. The denied latch is persisted, so these tests
    /// must not read or write each other's (or the standard suite's) state.
    private func freshDefaults() -> UserDefaults {
        let suiteName = "LocationServiceTests.\(UUID().uuidString)"
        createdDefaultsSuites.append(suiteName)
        return UserDefaults(suiteName: suiteName)!
    }

    deinit {
        for suiteName in createdDefaultsSuites {
            UserDefaults().removePersistentDomain(forName: suiteName)
        }
    }

    /// Builds an authorizable mock and a service wired to it, with a fresh,
    /// isolated defaults suite by default. Collapses the mock + service pair that
    /// every test below would otherwise spell out.
    ///
    /// - Parameters:
    ///   - defaults: An explicit suite, for tests that simulate two launches
    ///     sharing persisted state.
    ///   - servicesOff: Simulates Location Services being off system-wide.
    ///   - initialStatus: The mock's authorization *before* the service is
    ///     constructed, so the service seeds its raw status from it (as it would
    ///     on a real relaunch).
    private func makeService(
        defaults: UserDefaults? = nil,
        servicesOff: Bool = false,
        initialStatus: CLAuthorizationStatus = .notDetermined
    ) -> (AuthorizableLocationManagerMock, LocationService) {
        let mock = AuthorizableLocationManagerMock(updateLocation: TestData.mockSeattleLocation, updateHeading: TestData.mockHeading)
        mock.simulatesLocationServicesOff = servicesOff
        mock._authorizationStatus = initialStatus
        let service = LocationService(userDefaults: defaults ?? freshDefaults(), locationManager: mock)
        return (mock, service)
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
        let (mock, service) = makeService(initialStatus: .authorizedWhenInUse)
        #expect(!mock.locationUpdatesStarted)

        service.locationManagerDidChangeAuthorization(CLLocationManager())

        #expect(mock.locationUpdatesStarted)
        #expect(mock.headingUpdatesStarted)
        #expect(service.currentLocation == TestData.mockSeattleLocation)
    }

    /// The same callback must *not* start updates when the app isn't authorized.
    @Test func `Authorization callback does not start updates when unauthorized`() {
        let (mock, service) = makeService(initialStatus: .denied)

        service.locationManagerDidChangeAuthorization(CLLocationManager())

        #expect(!service.isLocationUseAuthorized)
        #expect(!mock.locationUpdatesStarted)
    }

    /// A latch seeded from the previous launch is probed at app init rather than
    /// waiting for a foreground event, so a stale one resolves as early as
    /// possible. Recovery goes through the off-main `locationServicesEnabled`
    /// probe, so it is asynchronous.
    @Test func `Seeded latch is probed on authorization callback`() async {
        let userDefaults = freshDefaults()

        // First launch: Location Services off system-wide, so the app latches.
        let (_, firstLaunch) = makeService(defaults: userDefaults, servicesOff: true)
        firstLaunch.requestInUseAuthorization()
        #expect(!firstLaunch.isLocationUseAuthorized)

        // Relaunch, with Location Services back on system-wide. The per-app
        // authorization still reads as authorized, so the seeded latch masks it.
        let (_, secondLaunch) = makeService(defaults: userDefaults, initialStatus: .authorizedWhenInUse)
        #expect(secondLaunch.authorizationStatus == .denied)

        // The init-time authorization callback probes the seeded latch and, with
        // services back on, clears it.
        secondLaunch.locationManagerDidChangeAuthorization(CLLocationManager())
        await poll(until: { secondLaunch.isLocationUseAuthorized },
                   "seeded latch was never cleared by the probe")

        #expect(secondLaunch.authorizationStatus == .authorizedWhenInUse)
        #expect(secondLaunch.currentLocation == TestData.mockSeattleLocation)
    }

    /// A transition that crosses *into* authorization is a fresh grant, so it
    /// clears a stale latch synchronously — without waiting for the off-main probe.
    @Test func `Latch cleared when authorization crosses into authorized`() {
        let userDefaults = freshDefaults()

        // Prior session latched (services off) while authorized; the latch persists.
        let (_, firstLaunch) = makeService(defaults: userDefaults, servicesOff: true)
        firstLaunch.requestInUseAuthorization()
        #expect(!firstLaunch.isLocationUseAuthorized)

        // Relaunch not-yet-authorized: the persisted latch is masked by the raw
        // `.notDetermined` status.
        let (mock, secondLaunch) = makeService(defaults: userDefaults, initialStatus: .notDetermined)
        #expect(secondLaunch.authorizationStatus == .notDetermined)

        // The user grants access. Crossing into authorization clears the stale
        // latch right away.
        mock._authorizationStatus = .authorizedWhenInUse
        #expect(secondLaunch.authorizationStatus == .authorizedWhenInUse)
        #expect(secondLaunch.isLocationUseAuthorized)
    }

    // MARK: - Denied error handling

    /// `startUpdates()` starts location then heading, and starting location can
    /// synchronously deliver the `denied` error that latches and tears both down.
    /// Heading must not then start anyway on the way back out: `isHeadingAvailable`
    /// is a device-capability check (`CLLocationManager.headingAvailable()`), not
    /// an authorization one, so nothing else stops it — and a magnetometer left
    /// powered outlives the denial for the rest of the process.
    @Test func `Synchronous denial during startUpdates leaves heading stopped`() {
        let (mock, service) = makeService(servicesOff: true)
        let del = LocDelegate()
        service.addDelegate(del)

        // Synchronous throughout: no probe has run yet, so this observes the
        // state `startUpdates()` itself leaves behind.
        service.requestInUseAuthorization()

        #expect(service.authorizationStatus == .denied)
        #expect(!mock.locationUpdatesStarted)
        #expect(!mock.headingUpdatesStarted)
        #expect(service.currentHeading == nil)
        #expect(del.heading == nil)
    }

    /// A `denied` error means location is unusable even though the app's own
    /// authorization is untouched (e.g. Location Services switched off system-wide).
    /// The service should latch that, report `.denied` so the UI can explain the
    /// situation, stop updates, and re-notify delegates.
    @Test func `Denied error marks location unavailable`() {
        let (mock, service) = makeService()
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        #expect(service.isLocationUseAuthorized)
        #expect(mock.locationUpdatesStarted)
        #expect(mock.headingUpdatesStarted)

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
        #expect(!mock.locationUpdatesStarted)
        #expect(!mock.headingUpdatesStarted)
    }

    /// A `denied` error is not latched while the app isn't itself authorized:
    /// the effective status would mask it anyway, and persisting it there means a
    /// grant made while the app was not running launches wrongly showing
    /// "Location Services Off."
    @Test func `Denied error while unauthorized is not latched`() {
        let userDefaults = freshDefaults()

        // A denied error arrives while the app is only `.notDetermined`.
        let (_, firstLaunch) = makeService(defaults: userDefaults, initialStatus: .notDetermined)
        firstLaunch.locationManager(CLLocationManager(), didFailWithError: CLError(.denied))

        // Nothing was persisted, so a later launch that is authorized (the user
        // granted access while the app was dead) is not masked as denied.
        let (_, secondLaunch) = makeService(defaults: userDefaults, initialStatus: .authorizedWhenInUse)
        #expect(secondLaunch.authorizationStatus == .authorizedWhenInUse)
        #expect(secondLaunch.isLocationUseAuthorized)
    }

    /// An authorization callback triggers the off-main probe, which clears the
    /// latch once Location Services are back on — even a callback that only
    /// changes between two authorized values (WhenInUse → Always).
    @Test func `Denied latch cleared by probe on authorization callback`() async {
        let (mock, service) = makeService(servicesOff: true)

        service.requestInUseAuthorization()
        #expect(service.authorizationStatus == .denied)
        #expect(!mock.locationUpdatesStarted)

        // The user re-enabled Location Services and promoted the app to Always.
        mock.simulatesLocationServicesOff = false
        mock._authorizationStatus = .authorizedAlways

        await poll(until: { service.isLocationUseAuthorized },
                   "probe never cleared the latch after services came back on")
        #expect(service.authorizationStatus == .authorizedAlways)
        #expect(mock.locationUpdatesStarted)
    }

    /// Core Location fires an authorization callback whenever a delegate is
    /// assigned. One that leaves the status untouched carries no new evidence, so
    /// it must not clear the latch — doing so would re-arm location against a
    /// still-disabled subsystem and flicker the locate button and user dot.
    @Test func `Denied error survives redundant authorization callback`() async {
        let (mock, service) = makeService(servicesOff: true)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        #expect(service.authorizationStatus == .denied)

        del.status = nil
        service.locationManagerDidChangeAuthorization(CLLocationManager())

        // The callback probes instead of assuming. Location Services are still
        // off, so the probe confirms the denial and nothing the user can see
        // changes. Let the async probe run before asserting it changed nothing.
        await spin(0.05)
        #expect(service.authorizationStatus == .denied)
        #expect(!service.isLocationUseAuthorized)
        #expect(del.status == nil)
        #expect(!mock.locationUpdatesStarted)
        #expect(!mock.headingUpdatesStarted)
    }

    /// Toggling Location Services back on system-wide does not change the app's
    /// per-app authorization, so no authorization callback need arrive. The
    /// foreground retry probes the system-wide switch, and finding it back on
    /// clears the latch.
    @Test func `Denied error cleared by foreground retry`() async {
        let (mock, service) = makeService(servicesOff: true)
        let del = LocDelegate()
        service.addDelegate(del)

        service.requestInUseAuthorization()
        #expect(service.authorizationStatus == .denied)
        #expect(!mock.locationUpdatesStarted)

        // Still off: the probe re-confirms the denial, and the UI is not disturbed.
        del.status = nil
        service.retryIfLocationServicesDenied()
        await spin(0.05)
        #expect(service.authorizationStatus == .denied)
        #expect(del.status == nil)
        #expect(!mock.locationUpdatesStarted)

        // The user turned Location Services back on; now the probe clears the latch.
        mock.simulatesLocationServicesOff = false
        service.retryIfLocationServicesDenied()

        await poll(until: { service.isLocationUseAuthorized },
                   "foreground retry never cleared the latch")
        #expect(service.authorizationStatus == .authorizedWhenInUse)
        #expect(del.status == .authorizedWhenInUse)
        #expect(service.currentLocation == TestData.mockSeattleLocation)
        #expect(mock.locationUpdatesStarted)
        #expect(mock.headingUpdatesStarted)
    }

    /// Probes are unstructured tasks with no ordering guarantee at the `await`,
    /// and three call sites can start one. A probe that started earlier — and so
    /// read an older system state — must not clobber the latch when it resumes
    /// after a newer one. Cancel-and-replace is what makes the newest read win.
    @Test func `Stale probe does not clobber a newer one`() async {
        let (mock, service) = makeService(servicesOff: true)

        // Let the authorization callback's own probe run to completion first, so
        // the only parked probes below are the two this test starts.
        service.requestInUseAuthorization()
        await spin(0.05)
        #expect(service.authorizationStatus == .denied)

        mock.parksProbes = true

        // Two probes in flight, started one at a time so their parked order is
        // known: the first read the switch while it was still off, the second
        // after the user turned it back on.
        service.retryIfLocationServicesDenied()
        await poll(until: { mock.pendingProbes.count == 1 },
                   "the first probe should have parked")

        service.retryIfLocationServicesDenied()
        await poll(until: { mock.pendingProbes.count == 2 },
                   "the second probe should have parked")

        // The user turned Location Services back on between the two probes, so
        // the newer one sees `true` and the restarted manager delivers a fix.
        mock.simulatesLocationServicesOff = false

        // Resume newest-first, so the stale answer lands last.
        mock.answerProbe(at: 1, enabled: true)
        await poll(until: { service.isLocationUseAuthorized },
                   "the newer probe never cleared the latch")

        mock.answerProbe(at: 0, enabled: false)
        await spin(0.05)

        #expect(service.authorizationStatus == .authorizedWhenInUse)
        #expect(service.isLocationUseAuthorized)
    }

    /// Location Services being off system-wide outlives the app process, but the
    /// per-app authorization that masks it reads as authorized on the next launch.
    /// The latch is persisted so a cold start doesn't advertise location as
    /// available and then retract it.
    @Test func `Denied latch persists across launches`() {
        let userDefaults = freshDefaults()

        let (_, firstLaunch) = makeService(defaults: userDefaults, servicesOff: true)
        firstLaunch.requestInUseAuthorization()
        #expect(!firstLaunch.isLocationUseAuthorized)

        // Relaunch: the app is still authorized as far as Core Location is concerned.
        let (_, secondLaunch) = makeService(defaults: userDefaults, initialStatus: .authorizedWhenInUse)

        #expect(secondLaunch.authorizationStatus == .denied)
        #expect(!secondLaunch.isLocationUseAuthorized)
    }

    /// Revoking authorization must tear the manager down. Nothing else will, and a
    /// running `CLLocationManager` keeps the location-usage indicator lit.
    @Test func `Authorization revoked stops updates`() {
        let (mock, service) = makeService()

        service.requestInUseAuthorization()
        #expect(mock.locationUpdatesStarted)

        mock._authorizationStatus = .denied

        #expect(!service.isLocationUseAuthorized)
        #expect(!mock.locationUpdatesStarted)
        // Heading too, not just location: revocation must power the magnetometer
        // down as well, and `stopUpdatingHeading()`'s availability guard is a
        // device-capability check that does not relax when authorization goes away.
        #expect(!mock.headingUpdatesStarted)
    }

    /// A repeated `denied` error must not re-notify delegates — the latch only
    /// fires on a real state transition.
    @Test func `Repeated denied error does not re-notify`() {
        let (_, service) = makeService()
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
        let (_, service) = makeService()

        service.requestInUseAuthorization()
        #expect(service.isLocationUseAuthorized)

        service.locationManager(CLLocationManager(), didFailWithError: CLError(.locationUnknown))

        #expect(service.isLocationUseAuthorized)
    }
}
