//
//  LocationServiceRegionMonitoringTests.swift
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

// swiftlint:disable force_try

@Suite(.serialized)
final class LocationServiceRegionMonitoringTests: OBATestCase {

    var locationManagerMock: AuthorizableLocationManagerMock!
    var service: LocationService!
    var delegate: LocDelegate!
    var stop: Stop!

    override init() async throws {
        try await super.init()

        let location = CLLocation(latitude: 47.0, longitude: -122.0)
        locationManagerMock = AuthorizableLocationManagerMock(updateLocation: location, updateHeading: OBAMockHeading(heading: 0.0))
        // Always, not When In Use: geofences only deliver in the background under
        // Always, and `startMonitoringProximity` now refuses anything less.
        locationManagerMock._authorizationStatus = .authorizedAlways
        service = LocationService(userDefaults: userDefaults, locationManager: locationManagerMock)
        delegate = LocDelegate()
        service.addDelegate(delegate)
        stop = try! Fixtures.loadSomeStops().first!
    }

    /// Fills the manager with regions the service did not create, standing in for
    /// the rest of the app's monitoring. The OS cap is per-app, not per-feature.
    private func fillMonitoredRegions(count: Int) {
        for index in 0..<count {
            locationManagerMock.startMonitoring(for: CLCircularRegion(
                center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
                radius: 100,
                identifier: "filler-region-\(index)"
            ))
        }
    }

    // MARK: - Start Monitoring

    @Test func `Start monitoring proximity creates region with correct properties`() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 300.0)

        let result = service.startMonitoringProximity(for: alert)

        #expect(result == .started)
        #expect(result.isMonitoring)
        #expect(self.locationManagerMock.monitoredRegions.count == 1)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region != nil)
        #expect(region?.identifier == LocationService.proximityRegionIdentifier(for: alert))
        #expect(region?.center.latitude == stop.location.coordinate.latitude)
        #expect(region?.center.longitude == stop.location.coordinate.longitude)
        #expect(region?.radius == 300.0)
        #expect(region?.notifyOnEntry == true)
        #expect(region?.notifyOnExit == false)
    }

    @Test func `Start monitoring proximity default radius`() {
        let alert = ProximityAlert(stop: stop)

        #expect(service.startMonitoringProximity(for: alert) == .started)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region?.radius == ProximityAlert.defaultRadiusMeters)
    }

    @Test func `Start monitoring proximity duplicate alert replaces region`() {
        let alert = ProximityAlert(stop: stop)

        #expect(service.startMonitoringProximity(for: alert) == .started)
        #expect(service.startMonitoringProximity(for: alert) == .started)

        // CLRegion uses identifier for equality in Set, so duplicate insert replaces
        #expect(self.locationManagerMock.monitoredRegions.count == 1)
        #expect(self.locationManagerMock.monitoredRegions.first?.identifier == LocationService.proximityRegionIdentifier(for: alert))
    }

    @Test func `Start monitoring proximity multiple alerts`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        #expect(service.startMonitoringProximity(for: alert1) == .started)
        #expect(service.startMonitoringProximity(for: alert2) == .started)

        #expect(self.locationManagerMock.monitoredRegions.count == 2)
    }

    // MARK: - Start Monitoring: Authorization

    @Test func `Start monitoring proximity when in use is insufficient`() {
        locationManagerMock._authorizationStatus = .authorizedWhenInUse
        let alert = ProximityAlert(stop: stop)

        let result = service.startMonitoringProximity(for: alert)

        // When In Use passes `isLocationUseAuthorized`, which is exactly why this
        // path needs its own check: monitoring started under it never fires in the
        // background, which is the only time a proximity alert is useful.
        #expect(result == .insufficientAuthorization(.authorizedWhenInUse))
        #expect(!result.isMonitoring)
        #expect(self.locationManagerMock.monitoredRegions.isEmpty)
    }

    @Test func `Start monitoring proximity unauthorized does not monitor`() {
        let unauthorizedMock = LocationManagerMock()
        let unauthorizedService = LocationService(userDefaults: userDefaults, locationManager: unauthorizedMock)
        let alert = ProximityAlert(stop: stop)

        let result = unauthorizedService.startMonitoringProximity(for: alert)

        #expect(result == .insufficientAuthorization(.notDetermined))
        #expect(unauthorizedMock.monitoredRegions.isEmpty)
    }

    @Test func `Is proximity monitoring authorized requires always`() {
        locationManagerMock._authorizationStatus = .authorizedAlways
        #expect(self.service.isProximityMonitoringAuthorized)

        locationManagerMock._authorizationStatus = .authorizedWhenInUse
        #expect(!self.service.isProximityMonitoringAuthorized)
        // Still authorized for ordinary location use — the two questions differ.
        #expect(self.service.isLocationUseAuthorized)
    }

    @Test func `Request always authorization upgrades from when in use`() {
        locationManagerMock._authorizationStatus = .authorizedWhenInUse

        service.requestAlwaysAuthorization()

        #expect(self.service.isProximityMonitoringAuthorized)
    }

    @Test func `Request always authorization does nothing when denied`() {
        locationManagerMock._authorizationStatus = .denied

        service.requestAlwaysAuthorization()

        #expect(!self.service.isProximityMonitoringAuthorized)
    }

    // MARK: - Start Monitoring: Region Limit

    @Test func `Start monitoring proximity at region limit is refused`() {
        fillMonitoredRegions(count: LocationService.maximumMonitoredRegions)
        let alert = ProximityAlert(stop: stop)

        let result = service.startMonitoringProximity(for: alert)

        #expect(result == .regionLimitReached(limit: LocationService.maximumMonitoredRegions))
        #expect(!result.isMonitoring)
        #expect(self.locationManagerMock.monitoredRegions.count == LocationService.maximumMonitoredRegions)
        #expect(self.service.monitoredProximityRegions.isEmpty)
    }

    @Test func `Start monitoring proximity counts regions the app monitors elsewhere`() {
        // The cap is per-app, so non-proximity regions consume slots too.
        fillMonitoredRegions(count: LocationService.maximumMonitoredRegions - 1)
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)

        #expect(service.startMonitoringProximity(for: alert1) == .started)
        #expect(service.startMonitoringProximity(for: alert2) == .regionLimitReached(limit: LocationService.maximumMonitoredRegions))
    }

    @Test func `Start monitoring proximity re arms existing alert at region limit`() {
        let alert = ProximityAlert(stop: stop)
        #expect(service.startMonitoringProximity(for: alert) == .started)

        fillMonitoredRegions(count: LocationService.maximumMonitoredRegions - 1)
        #expect(self.locationManagerMock.monitoredRegions.count == LocationService.maximumMonitoredRegions)

        // Re-arming replaces a region rather than adding one, so being at the cap
        // must not block it — otherwise a full slate would freeze every alert.
        #expect(service.startMonitoringProximity(for: alert) == .started)
        #expect(self.locationManagerMock.monitoredRegions.count == LocationService.maximumMonitoredRegions)
    }

    // MARK: - Start Monitoring: Radius Clamping

    @Test func `Start monitoring proximity clamps radius to device maximum`() {
        locationManagerMock.maximumRegionMonitoringDistance = 150
        let alert = ProximityAlert(stop: stop, radiusMeters: 400)

        let result = service.startMonitoringProximity(for: alert)

        // Core Location would have clamped this silently and fired the alert 250m
        // closer than the user asked for, with nothing recording the difference.
        #expect(result == .startedWithClampedRadius(requested: 400, monitored: 150))
        #expect(result.isMonitoring)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region?.radius == 150)
    }

    @Test func `Start monitoring proximity keeps radius within device maximum`() {
        locationManagerMock.maximumRegionMonitoringDistance = 5_000
        let alert = ProximityAlert(stop: stop, radiusMeters: 300)

        #expect(service.startMonitoringProximity(for: alert) == .started)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region?.radius == 300)
    }

    @Test func `Start monitoring proximity ignores unavailable device maximum`() {
        // A non-positive maximum means "unknown", not "monitor nothing".
        locationManagerMock.maximumRegionMonitoringDistance = 0
        let alert = ProximityAlert(stop: stop, radiusMeters: 300)

        #expect(service.startMonitoringProximity(for: alert) == .started)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region?.radius == 300)
    }

    // MARK: - Stop Monitoring

    @Test func `Stop monitoring proximity removes correct region`() {
        let alert = ProximityAlert(stop: stop)

        #expect(service.startMonitoringProximity(for: alert) == .started)
        #expect(self.locationManagerMock.monitoredRegions.count == 1)

        service.stopMonitoringProximity(for: alert)
        #expect(self.locationManagerMock.monitoredRegions.isEmpty)
    }

    @Test func `Stop monitoring proximity nonexistent alert is no op`() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)

        #expect(service.startMonitoringProximity(for: alert1) == .started)

        service.stopMonitoringProximity(for: alert2)

        #expect(self.locationManagerMock.monitoredRegions.count == 1)
    }

    @Test func `Stop monitoring proximity only removes target region`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        #expect(service.startMonitoringProximity(for: alert1) == .started)
        #expect(service.startMonitoringProximity(for: alert2) == .started)

        service.stopMonitoringProximity(for: alert1)

        #expect(self.locationManagerMock.monitoredRegions.count == 1)
        let remaining = self.locationManagerMock.monitoredRegions.first
        #expect(remaining?.identifier == LocationService.proximityRegionIdentifier(for: alert2))
    }

    // MARK: - Stop All Monitoring

    @Test func `Stop monitoring all proximity alerts removes all prefixed regions`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        #expect(service.startMonitoringProximity(for: alert1) == .started)
        #expect(service.startMonitoringProximity(for: alert2) == .started)

        service.stopMonitoringAllProximityAlerts()

        #expect(self.locationManagerMock.monitoredRegions.isEmpty)
    }

    @Test func `Stop monitoring all proximity alerts preserves non prefixed regions`() {
        let alert = ProximityAlert(stop: stop)
        #expect(service.startMonitoringProximity(for: alert) == .started)

        let otherRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,
            identifier: "some-other-region"
        )
        locationManagerMock.startMonitoring(for: otherRegion)

        #expect(self.locationManagerMock.monitoredRegions.count == 2)

        service.stopMonitoringAllProximityAlerts()

        #expect(self.locationManagerMock.monitoredRegions.count == 1)
        #expect(self.locationManagerMock.monitoredRegions.first?.identifier == "some-other-region")
    }

    @Test func `Stop monitoring all proximity alerts empty regions is no op`() {
        #expect(self.locationManagerMock.monitoredRegions.isEmpty)

        service.stopMonitoringAllProximityAlerts()

        #expect(self.locationManagerMock.monitoredRegions.isEmpty)
    }

    // MARK: - Monitored Proximity Regions

    @Test func `Monitored proximity regions excludes regions the app monitors elsewhere`() {
        let alert = ProximityAlert(stop: stop)
        #expect(service.startMonitoringProximity(for: alert) == .started)
        fillMonitoredRegions(count: 3)

        #expect(self.locationManagerMock.monitoredRegions.count == 4)
        #expect(self.service.monitoredProximityRegions.count == 1)
        #expect(self.service.monitoredProximityRegions.first?.identifier == LocationService.proximityRegionIdentifier(for: alert))
    }

    // MARK: - Delegate: didEnterRegion

    @Test func `Did enter region notifies delegate`() {
        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: LocationService.proximityRegionIdentifier(for: alert)
        )

        service.locationManager(CLLocationManager(), didEnterRegion: region)

        #expect(self.delegate.enteredRegionIdentifier == LocationService.proximityRegionIdentifier(for: alert))
    }

    @Test func `Did enter region non prefixed circular region does not notify`() {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            radius: 200,
            identifier: "some-other-region"
        )

        service.locationManager(CLLocationManager(), didEnterRegion: region)

        #expect(self.delegate.enteredRegionIdentifier == nil)
    }

    @Test func `Did enter region non circular region does not notify`() {
        // A beacon region wearing our prefix is a "should never happen" state:
        // everything registered under it is created as a CLCircularRegion.
        let beaconRegion = CLBeaconRegion(
            uuid: UUID(),
            // No alert to derive this from, but the prefix still comes from the
            // one place that defines it — that's what puts the region in our
            // namespace, and so what the guard under test keys off.
            identifier: LocationService.proximityRegionPrefix + "beacon-test"
        )

        service.locationManager(CLLocationManager(), didEnterRegion: beaconRegion)

        #expect(self.delegate.enteredRegionIdentifier == nil)
    }

    // MARK: - Delegate: monitoringDidFail

    @Test func `Monitoring did fail notifies delegate for proximity region`() {
        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: LocationService.proximityRegionIdentifier(for: alert)
        )

        service.locationManager(CLLocationManager(), monitoringDidFailFor: region, withError: CLError(.regionMonitoringFailure))

        #expect(self.delegate.monitoringFailedCallCount == 1)
        #expect(self.delegate.monitoringFailedIdentifier == region.identifier)
        #expect(self.delegate.monitoringFailedKind == .regionRejected)
    }

    @Test func `Monitoring did fail ignores non proximity region`() {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            radius: 200,
            identifier: "some-other-region"
        )

        service.locationManager(CLLocationManager(), monitoringDidFailFor: region, withError: CLError(.regionMonitoringFailure))

        // Proximity delegates used to receive every monitoring failure in the app,
        // including ones they could neither attribute nor act on.
        #expect(self.delegate.monitoringFailedCallCount == 0)
        #expect(self.delegate.monitoringFailedIdentifier == nil)
        #expect(self.delegate.monitoringFailedError == nil)
    }

    @Test func `Monitoring did fail nil region notifies delegate`() {
        // Core Location reports the region cap with no region attached. It can't
        // be attributed, but it may well be ours, so it still gets forwarded.
        service.locationManager(CLLocationManager(), monitoringDidFailFor: nil, withError: CLError(.regionMonitoringFailure))

        #expect(self.delegate.monitoringFailedCallCount == 1)
        #expect(self.delegate.monitoringFailedIdentifier == nil)
        #expect(self.delegate.monitoringFailedError != nil)
        #expect(self.delegate.monitoringFailedKind == .regionRejected)
    }

    @Test func `Monitoring did fail forwards denial kind`() {
        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: LocationService.proximityRegionIdentifier(for: alert)
        )

        service.locationManager(CLLocationManager(), monitoringDidFailFor: region, withError: CLError(.regionMonitoringDenied))

        #expect(self.delegate.monitoringFailedKind == .authorizationDenied)
    }

    // MARK: - Failure Classification

    @Test func `Failure kind classifies denials as authorization denied`() {
        #expect(RegionMonitoringFailureKind(error: CLError(.denied)) == .authorizationDenied)
        #expect(RegionMonitoringFailureKind(error: CLError(.regionMonitoringDenied)) == .authorizationDenied)
    }

    @Test func `Failure kind classifies monitoring failure as region rejected`() {
        let kind = RegionMonitoringFailureKind(error: CLError(.regionMonitoringFailure))

        #expect(kind == .regionRejected)
        // Retrying this one forever would never succeed: the app has to change
        // what it asks for first.
        #expect(!kind.isTransient)
    }

    @Test func `Failure kind classifies delays as transient`() {
        #expect(RegionMonitoringFailureKind(error: CLError(.regionMonitoringSetupDelayed)) == .transient)
        #expect(RegionMonitoringFailureKind(error: CLError(.regionMonitoringResponseDelayed)) == .transient)
        #expect(RegionMonitoringFailureKind(error: CLError(.network)) == .transient)
        #expect(RegionMonitoringFailureKind(error: CLError(.network)).isTransient)
    }

    @Test func `Failure kind classifies non core location error as unknown`() {
        let error = NSError(domain: "SomeOtherDomain", code: 5, userInfo: nil)
        let kind = RegionMonitoringFailureKind(error: error)

        #expect(kind == .unknown)
        // Unknown is treated as permanent: retrying an unrecognized failure
        // forever is the worse of the two ways to be wrong.
        #expect(!kind.isTransient)
    }

    // MARK: - Multiple Delegates

    @Test func `Did enter region notifies multiple delegates`() {
        let delegate2 = LocDelegate()
        service.addDelegate(delegate2)

        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: LocationService.proximityRegionIdentifier(for: alert)
        )

        service.locationManager(CLLocationManager(), didEnterRegion: region)

        #expect(self.delegate.enteredRegionIdentifier == LocationService.proximityRegionIdentifier(for: alert))
        #expect(delegate2.enteredRegionIdentifier == LocationService.proximityRegionIdentifier(for: alert))
    }
}
