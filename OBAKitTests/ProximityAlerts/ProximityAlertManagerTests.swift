//
//  ProximityAlertManagerTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
import UserNotifications
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class ProximityAlertManagerTests: OBATestCase {

    var locationManagerMock: CountingLocationManagerMock!
    var locationService: LocationService!
    var store: UserDefaultsStore!
    var stops: [Stop]!

    /// Every request the manager handed to the notification system, in order.
    /// Boxed rather than held as a plain property because the scheduler closure
    /// stands in for one the real `UNUserNotificationCenter` may call anywhere.
    var delivered: SendableBox<[UNNotificationRequest]>!

    var stop: Stop { stops[0] }

    override init() async throws {
        try await super.init()

        let location = CLLocation(latitude: 47.0, longitude: -122.0)
        locationManagerMock = CountingLocationManagerMock(
            updateLocation: location,
            updateHeading: OBAMockHeading(heading: 0.0)
        )
        // Always, not When In Use: a geofence armed under When In Use never
        // delivers in the background, and `startMonitoringProximity` refuses it.
        locationManagerMock._authorizationStatus = .authorizedAlways
        locationService = LocationService(userDefaults: userDefaults, locationManager: locationManagerMock)
        store = UserDefaultsStore(userDefaults: userDefaults)
        stops = try! Fixtures.loadSomeStops()
        delivered = SendableBox([])
    }

    // MARK: - Helpers

    /// - Parameters:
    ///   - notificationStatus: what the manager sees when it checks whether a
    ///     notification it posted could actually reach the rider.
    ///   - regionID: the region the rider is in as the manager sees it, recorded
    ///     onto every alert it creates.
    private func makeManager(
        notificationStatus: UNAuthorizationStatus = .authorized,
        regionID: Int? = nil
    ) -> ProximityAlertManager {
        let delivered = self.delivered!
        return ProximityAlertManager(
            locationService: locationService,
            userDataStore: store,
            regionIDProvider: { regionID },
            authorizationStatusProvider: { notificationStatus },
            scheduleNotification: { request, completion in
                delivered.value.append(request)
                completion(nil)
            }
        )
    }

    /// Stands in for Core Location reporting a crossing into `alert`'s geofence.
    private func enterRegion(for alert: ProximityAlert) {
        enterRegion(identifier: LocationService.proximityRegionIdentifier(for: alert))
    }

    private func enterRegion(identifier: String) {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            radius: 200,
            identifier: identifier
        )
        locationService.locationManager(CLLocationManager(), didEnterRegion: region)
    }

    private func failMonitoring(for alert: ProximityAlert, error: CLError.Code) {
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: LocationService.proximityRegionIdentifier(for: alert)
        )
        locationService.locationManager(CLLocationManager(), monitoringDidFailFor: region, withError: CLError(error))
    }

    /// Fills the manager with regions this feature did not create. The OS cap on
    /// monitored regions is per-app, not per-feature.
    private func fillMonitoredRegions(count: Int) {
        for index in 0..<count {
            locationManagerMock.startMonitoring(for: CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
                radius: 100,
                identifier: "filler-region-\(index)"
            ))
        }
    }

    // MARK: - Creating Alerts

    @Test func `Create stores the alert and arms its geofence`() async {
        let manager = makeManager()

        let result = await manager.createProximityAlert(for: stop)

        guard case .activated(let alert) = result else {
            Issue.record("Expected .activated, got \(result)")
            return
        }
        #expect(alert.stopID == self.stop.id)
        #expect(alert.radiusMeters == ProximityAlert.defaultRadiusMeters)
        #expect(self.store.proximityAlerts.map(\.id) == [alert.id])
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
    }

    @Test func `Create honors a custom radius`() async {
        let manager = makeManager()

        let result = await manager.createProximityAlert(for: stop, radiusMeters: 500)

        guard case .activated(let alert) = result else {
            Issue.record("Expected .activated, got \(result)")
            return
        }
        #expect(alert.radiusMeters == 500)
    }

    @Test func `Create reports a radius the device shrank`() async {
        locationManagerMock.maximumRegionMonitoringDistance = 150
        let manager = makeManager()

        let result = await manager.createProximityAlert(for: stop, radiusMeters: 400)

        // Core Location would have clamped this silently, firing the alert 250m
        // closer than the rider asked for. The alert is still worth keeping — it
        // works, just not where they expected — so it is stored and armed.
        guard case .activatedWithClampedRadius(let alert, let requested, let monitored) = result else {
            Issue.record("Expected .activatedWithClampedRadius, got \(result)")
            return
        }
        #expect(requested == 400)
        #expect(monitored == 150)
        #expect(self.store.proximityAlerts.map(\.id) == [alert.id])
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
    }

    @Test func `Create without Always authorization stores nothing`() async {
        locationManagerMock._authorizationStatus = .authorizedWhenInUse
        let manager = makeManager()

        let result = await manager.createProximityAlert(for: stop)

        #expect(result == .needsLocationAuthorization(.authorizedWhenInUse))
        // Nothing persisted: an alert the rider believes in with no geofence
        // behind it is worse than a refusal they can act on.
        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Create with notifications denied stores nothing`() async {
        let manager = makeManager(notificationStatus: .denied)

        let result = await manager.createProximityAlert(for: stop)

        #expect(result == .needsNotificationAuthorization(.denied))
        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Create with notification authorization undetermined stores nothing`() async {
        let manager = makeManager(notificationStatus: .notDetermined)

        let result = await manager.createProximityAlert(for: stop)

        // Departure alarms let `.notDetermined` through, because `pushID()`
        // further down that path triggers the first-time system prompt. Nothing
        // here does: `UNUserNotificationCenter.add` on an undetermined app neither
        // asks nor delivers, so this is as dead an end as `.denied`.
        #expect(result == .needsNotificationAuthorization(.notDetermined))
        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Create with provisional notifications is allowed`() async {
        let manager = makeManager(notificationStatus: .provisional)

        let result = await manager.createProximityAlert(for: stop)

        // Quiet delivery is a poor fit for an alert meant to interrupt someone
        // watching the road, but it is still delivery.
        guard case .activated = result else {
            Issue.record("Expected .activated, got \(result)")
            return
        }
        #expect(self.store.proximityAlerts.count == 1)
        #expect(self.locationService.monitoredProximityAlertIDs.count == 1)
    }

    @Test func `Create at the region limit stores nothing`() async {
        fillMonitoredRegions(count: LocationService.maximumMonitoredRegions)
        let manager = makeManager()

        let result = await manager.createProximityAlert(for: stop)

        #expect(result == .regionLimitReached(limit: LocationService.maximumMonitoredRegions))
        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Create refuses a second alert on the same stop`() async {
        let manager = makeManager()
        guard case .activated(let first) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        let result = await manager.createProximityAlert(for: stop)

        guard case .alreadyActive(let existing) = result else {
            Issue.record("Expected .alreadyActive, got \(result)")
            return
        }
        #expect(existing.id == first.id)
        // The point of the guard. Asserting only the returned case would pass
        // even if a second geofence had armed at the same coordinate, holding a
        // second one of the twenty slots and firing alongside the first.
        #expect(self.store.proximityAlerts.map(\.id) == [first.id])
        #expect(self.locationService.monitoredProximityAlertIDs == [first.id])
    }

    @Test func `Create allows an alert on a stop whose old one expired`() async {
        let manager = makeManager()
        // Assigned rather than `add`ed. `add` posts `.proximityAlertsDidChange`,
        // which this manager observes with the selector form — `NotificationCenter`
        // invokes that inline, so reconciliation would reap the alert before the
        // guard ever saw it and the test would pass without exercising the expiry
        // filter it exists for.
        store.proximityAlerts = [ProximityAlert(
            stop: stop,
            createdAt: Date(timeIntervalSinceNow: -ProximityAlert.expirationInterval - 60)
        )]

        let result = await manager.createProximityAlert(for: stop)

        // The filter is easy to lose in a refactor, and losing it is invisible
        // until a rider cannot set today's alert on yesterday's stop.
        guard case .activated(let alert) = result else {
            Issue.record("Expected .activated, got \(result)")
            return
        }
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
    }

    @Test func `Create allows an alert on a different stop`() async {
        let manager = makeManager()
        _ = await manager.createProximityAlert(for: stops[0])

        let result = await manager.createProximityAlert(for: stops[1])

        // The guard keys on the stop. One that dropped that predicate would pass
        // every other test here while refusing every second alert the rider sets.
        guard case .activated(let second) = result else {
            Issue.record("Expected .activated, got \(result)")
            return
        }
        #expect(second.stopID == self.stops[1].id)
        #expect(self.store.proximityAlerts.count == 2)
        #expect(self.locationService.monitoredProximityAlertIDs.count == 2)
    }

    @Test func `Create on a stop that already has an alert still reports lost authorization`() async {
        let manager = makeManager()
        guard case .activated = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }
        // A downgrade from Always neither disarms nor deletes, so the stored alert
        // still looks healthy to the duplicate guard while no longer able to
        // deliver in the background.
        locationManagerMock._authorizationStatus = .authorizedWhenInUse

        let result = await manager.createProximityAlert(for: stop)

        // Ordering, asserted: "you already have one" would be true and useless
        // here, because the one they have went quiet when Always did. This is the
        // actionable answer, and the explanation.
        #expect(result == .needsLocationAuthorization(.authorizedWhenInUse))
    }

    @Test func `Create records the region the alert was set in`() async {
        let manager = makeManager(regionID: 12)

        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }
        #expect(alert.regionID == 12)
        // Persisted, not merely returned: the tap that needs the region reads the
        // stored alert, often from a process that did not create it.
        #expect(self.store.proximityAlerts.first?.regionID == 12)
    }

    // MARK: - Cancelling Alerts

    @Test func `Cancel disarms the geofence and forgets the alert`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        manager.cancelProximityAlert(alert)

        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Cancel all clears every alert`() async {
        let manager = makeManager()
        _ = await manager.createProximityAlert(for: stops[0])
        _ = await manager.createProximityAlert(for: stops[1])
        #expect(self.store.proximityAlerts.count == 2)

        manager.cancelAllProximityAlerts()

        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Cancel all leaves regions the app monitors elsewhere alone`() async {
        let manager = makeManager()
        _ = await manager.createProximityAlert(for: stop)
        fillMonitoredRegions(count: 3)

        manager.cancelAllProximityAlerts()

        #expect(self.locationManagerMock.monitoredRegions.count == 3)
    }

    // MARK: - Reading Alerts

    @Test func `Active alert finds the alert set on a stop`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        #expect(manager.activeAlert(for: self.stop.id)?.id == alert.id)
        #expect(manager.activeAlert(for: self.stops[1].id) == nil)
    }

    @Test func `Active alert ignores an expired alert`() {
        let expired = ProximityAlert(
            stop: stop,
            createdAt: Date(timeIntervalSinceNow: -ProximityAlert.expirationInterval - 60)
        )
        store.add(proximityAlert: expired)
        let manager = makeManager()

        #expect(manager.activeAlert(for: self.stop.id) == nil)
    }

    // MARK: - Reconciliation

    @Test func `Construction re arms alerts stored before launch`() {
        // The launch that matters: Core Location relaunches a terminated app for
        // a geofence crossing, and only the stored alerts survive to say which
        // regions belong to this feature.
        let alert = ProximityAlert(stop: stop)
        store.add(proximityAlert: alert)

        _ = makeManager()

        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
    }

    @Test func `Reconcile disarms a region whose alert is gone`() {
        let alert = ProximityAlert(stop: stop)
        #expect(locationService.startMonitoringProximity(for: alert) == .started)
        // Never stored — stands in for an alert deleted by a process that has
        // since been replaced, leaving its region armed with nothing to explain it.

        _ = makeManager()

        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Reconcile reaps expired alerts and disarms them`() {
        let expired = ProximityAlert(
            stop: stop,
            createdAt: Date(timeIntervalSinceNow: -ProximityAlert.expirationInterval - 60)
        )
        store.add(proximityAlert: expired)
        #expect(locationService.startMonitoringProximity(for: expired) == .started)

        _ = makeManager()

        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Reconcile keeps unexpired alerts armed`() {
        let fresh = ProximityAlert(stop: stops[0])
        let expired = ProximityAlert(
            stop: stops[1],
            createdAt: Date(timeIntervalSinceNow: -ProximityAlert.expirationInterval - 60)
        )
        store.add(proximityAlert: fresh)
        store.add(proximityAlert: expired)

        _ = makeManager()

        #expect(self.store.proximityAlerts.map(\.id) == [fresh.id])
        #expect(self.locationService.monitoredProximityAlertIDs == [fresh.id])
    }

    @Test func `Reconcile is idempotent`() async {
        let manager = makeManager()
        _ = await manager.createProximityAlert(for: stop)

        manager.reconcileMonitoredRegions()
        manager.reconcileMonitoredRegions()
        manager.reconcileMonitoredRegions()

        // Re-arming replaces a region rather than adding one, so repeated passes
        // must not accumulate regions or duplicate the stored alert.
        #expect(self.locationManagerMock.monitoredRegions.count == 1)
        #expect(self.store.proximityAlerts.count == 1)
    }

    @Test func `Reconcile does not re enter itself while reaping`() {
        // Reaping an expired alert makes the store post `.proximityAlertsDidChange`,
        // which this manager observes synchronously — landing back inside the pass
        // that provoked it. Without the `isReconciling` guard the surviving alert
        // is armed twice: once by the re-entrant pass, then again when the outer
        // pass resumes. Counted rather than read off `monitoredRegions`, which is
        // a Set and collapses the second call into the first.
        let fresh = ProximityAlert(stop: stops[0])
        let expired = ProximityAlert(
            stop: stops[1],
            createdAt: Date(timeIntervalSinceNow: -ProximityAlert.expirationInterval - 60)
        )
        store.add(proximityAlert: fresh)
        store.add(proximityAlert: expired)
        locationManagerMock.resetStartMonitoringCallCount()

        _ = makeManager()

        #expect(self.locationManagerMock.startMonitoringCallCount == 1)
        #expect(self.locationService.monitoredProximityAlertIDs == [fresh.id])
    }

    @Test func `Reconcile leaves regions the app monitors elsewhere alone`() {
        fillMonitoredRegions(count: 3)

        _ = makeManager()

        #expect(self.locationManagerMock.monitoredRegions.count == 3)
    }

    // MARK: - Store Observation

    @Test func `An alert added straight to the store gets armed`() {
        let manager = makeManager()
        let alert = ProximityAlert(stop: stop)

        store.add(proximityAlert: alert)

        // Asserted directly rather than polled. The store posts
        // `.proximityAlertsDidChange` on the calling thread and the manager
        // observes it with the selector form, which `NotificationCenter` invokes
        // inline — so this is already true here, and a regression to an
        // asynchronous delivery form is exactly what this would catch.
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
        #expect(manager.proximityAlerts.count == 1)
    }

    @Test func `An alert deleted straight from the store gets disarmed`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        store.delete(proximityAlert: alert)

        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
        #expect(manager.proximityAlerts.isEmpty)
    }

    // MARK: - Firing

    @Test func `Entering the geofence delivers a notification naming the stop`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        enterRegion(for: alert)

        #expect(self.delivered.value.count == 1)
        let request = delivered.value.first
        #expect(request?.content.title.isEmpty == false)
        #expect(request?.content.body.contains(self.stop.name) == true)
        #expect(request?.content.sound == .default)
        // Namespaced so a proximity notification can never replace another
        // feature's request that happens to share an identifier.
        #expect(request?.identifier == ProximityAlertManager.notificationIdentifierPrefix + alert.id.uuidString)
        // The payload `PushService` routes a tap on, back to the stop page.
        #expect(request?.content.userInfo[ProximityAlertManager.notificationUserInfoKey] as? String == self.stop.id)
    }

    @Test func `The notification carries the region the alert was set in`() async {
        let manager = makeManager(regionID: 12)
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        enterRegion(for: alert)

        let userInfo = self.delivered.value.first?.content.userInfo
        #expect(userInfo?[ProximityAlertManager.notificationRegionUserInfoKey] as? Int == 12)
        // Beside a stop ID that is still bare, not repackaged into a dictionary
        // with it: a notification delivered by an earlier build and tapped after
        // the update routes on this key's shape alone, and reshaping it would drop
        // that tap into the fallback that re-presents the notification's own text.
        #expect(userInfo?[ProximityAlertManager.notificationUserInfoKey] as? String == self.stop.id)
    }

    @Test func `The notification omits the region key when the alert has none`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        enterRegion(for: alert)

        // Absent rather than present and empty: `PushService` reads the key
        // optionally, so an alert that named no region delivers the payload every
        // alert delivered before the field existed did.
        let userInfo = self.delivered.value.first?.content.userInfo
        #expect(userInfo?.keys.contains(ProximityAlertManager.notificationRegionUserInfoKey) == false)
        #expect(userInfo?[ProximityAlertManager.notificationUserInfoKey] as? String == self.stop.id)
    }

    @Test func `Entering the geofence clears the alert`() async {
        let manager = makeManager()
        guard case .activated = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        enterRegion(for: store.proximityAlerts[0])

        // One-shot. A geofence left armed would fire again on tomorrow's commute
        // past the same stop.
        #expect(self.store.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    @Test func `Entering a region with no alert ID delivers nothing`() {
        _ = makeManager()

        enterRegion(identifier: LocationService.proximityRegionPrefix + "not-a-uuid")

        #expect(self.delivered.value.isEmpty)
    }

    @Test func `Entering a region whose alert is gone disarms it silently`() {
        let manager = makeManager()
        let alert = ProximityAlert(stop: stop)
        #expect(locationService.startMonitoringProximity(for: alert) == .started)

        enterRegion(for: alert)

        #expect(self.delivered.value.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
        #expect(manager.proximityAlerts.isEmpty)
    }

    @Test func `Entering the geofence of an expired alert delivers nothing`() {
        let expired = ProximityAlert(
            stop: stop,
            createdAt: Date(timeIntervalSinceNow: -ProximityAlert.expirationInterval - 60)
        )
        let manager = makeManager()
        // Assigned, not `add`ed. `add` posts `.proximityAlertsDidChange`, which
        // this manager observes with the selector form — `NotificationCenter`
        // invokes that inline, so reconciliation reaps the alert before the
        // crossing arrives and the test passes through the no-longer-stored
        // branch instead of the expiry guard it names.
        store.proximityAlerts = [expired]
        #expect(locationService.startMonitoringProximity(for: expired) == .started)

        enterRegion(for: expired)

        // Waking a rider for a trip that ended a day ago is worse than not firing.
        #expect(self.delivered.value.isEmpty)
        #expect(manager.proximityAlerts.isEmpty)
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    // MARK: - Authorization Changes

    @Test func `Granting Always arms alerts that could not arm before`() {
        locationManagerMock._authorizationStatus = .authorizedWhenInUse
        let alert = ProximityAlert(stop: stop)
        store.add(proximityAlert: alert)
        let manager = makeManager()
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)

        locationManagerMock.requestAlwaysAuthorization()

        // Region monitoring has no self-healing re-arm of its own: without this,
        // an alert stored under When In Use stays dead after the rider grants
        // Always in Settings.
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
        #expect(manager.proximityAlerts.count == 1)
    }

    @Test func `A change to less than Always arms nothing`() {
        locationManagerMock._authorizationStatus = .notDetermined
        let alert = ProximityAlert(stop: stop)
        store.add(proximityAlert: alert)
        _ = makeManager()

        locationManagerMock.requestWhenInUseAuthorization()

        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
    }

    // MARK: - Monitoring Failures

    @Test func `A delayed region stays armed`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        failMonitoring(for: alert, error: .regionMonitoringSetupDelayed)

        // The OS deferred the request rather than refusing it, and will retry on
        // its own. Disarming now would throw away an alert about to start working.
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
        #expect(self.store.proximityAlerts.count == 1)
    }

    @Test func `A permanently rejected region is disarmed but its alert kept`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        failMonitoring(for: alert, error: .regionMonitoringFailure)

        // The slot goes back to the twenty-region budget, but the alert is the
        // rider's — not ours to delete on an OS error, and the next reconciliation
        // gets to try once more.
        #expect(self.locationService.monitoredProximityAlertIDs.isEmpty)
        #expect(self.store.proximityAlerts.map(\.id) == [alert.id])
    }

    @Test func `A failure naming no region disarms nothing`() async {
        let manager = makeManager()
        guard case .activated(let alert) = await manager.createProximityAlert(for: stop) else {
            Issue.record("Setup failed: alert did not activate")
            return
        }

        locationService.locationManager(
            CLLocationManager(),
            monitoringDidFailFor: nil,
            withError: CLError(.regionMonitoringFailure)
        )

        // Core Location reports the region cap, and some setup failures, with no
        // region attached. There is no alert to act on, and guessing at one would
        // disarm whichever alert happened to be looked at first.
        #expect(self.locationService.monitoredProximityAlertIDs == [alert.id])
        #expect(self.store.proximityAlerts.count == 1)
    }
}

/// Counts arm calls, which `LocationManagerMock` otherwise collapses into a
/// `Set` of regions — re-arming the same alert is indistinguishable from arming
/// it once unless the calls themselves are counted.
final class CountingLocationManagerMock: AuthorizableLocationManagerMock {
    private(set) var startMonitoringCallCount = 0

    override func startMonitoring(for region: CLRegion) {
        startMonitoringCallCount += 1
        super.startMonitoring(for: region)
    }

    /// Discards calls made while a test was arranging its fixtures, so the count
    /// covers only the pass under test.
    func resetStartMonitoringCallCount() {
        startMonitoringCallCount = 0
    }
}
