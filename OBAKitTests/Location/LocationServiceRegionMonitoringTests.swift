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
        locationManagerMock._authorizationStatus = .authorizedWhenInUse
        service = LocationService(userDefaults: userDefaults, locationManager: locationManagerMock)
        delegate = LocDelegate()
        service.addDelegate(delegate)
        stop = try! Fixtures.loadSomeStops().first!
    }

    // MARK: - Start Monitoring

    @Test func `Start monitoring proximity creates region with correct properties`() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 300.0)

        service.startMonitoringProximity(for: alert)

        #expect(self.locationManagerMock.monitoredRegions.count == 1)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region != nil)
        #expect(region?.identifier == "oba.proximity.\(alert.id.uuidString)")
        #expect(region?.center.latitude == stop.location.coordinate.latitude)
        #expect(region?.center.longitude == stop.location.coordinate.longitude)
        #expect(region?.radius == 300.0)
        #expect(region?.notifyOnEntry == true)
        #expect(region?.notifyOnExit == false)
    }

    @Test func `Start monitoring proximity unauthorized does not monitor`() {
        let unauthorizedMock = LocationManagerMock()
        let unauthorizedService = LocationService(userDefaults: userDefaults, locationManager: unauthorizedMock)
        let alert = ProximityAlert(stop: stop)

        unauthorizedService.startMonitoringProximity(for: alert)

        #expect(unauthorizedMock.monitoredRegions.isEmpty)
    }

    @Test func `Start monitoring proximity default radius`() {
        let alert = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        #expect(region?.radius == 200.0)
    }

    @Test func `Start monitoring proximity duplicate alert replaces region`() {
        let alert = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert)
        service.startMonitoringProximity(for: alert)

        // CLRegion uses identifier for equality in Set, so duplicate insert replaces
        #expect(self.locationManagerMock.monitoredRegions.count == 1)
        #expect(self.locationManagerMock.monitoredRegions.first?.identifier == "oba.proximity.\(alert.id.uuidString)")
    }

    @Test func `Start monitoring proximity multiple alerts`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        service.startMonitoringProximity(for: alert1)
        service.startMonitoringProximity(for: alert2)

        #expect(self.locationManagerMock.monitoredRegions.count == 2)
    }

    // MARK: - Stop Monitoring

    @Test func `Stop monitoring proximity removes correct region`() {
        let alert = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert)
        #expect(self.locationManagerMock.monitoredRegions.count == 1)

        service.stopMonitoringProximity(for: alert)
        #expect(self.locationManagerMock.monitoredRegions.isEmpty)
    }

    @Test func `Stop monitoring proximity nonexistent alert is no op`() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert1)

        service.stopMonitoringProximity(for: alert2)

        #expect(self.locationManagerMock.monitoredRegions.count == 1)
    }

    @Test func `Stop monitoring proximity only removes target region`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        service.startMonitoringProximity(for: alert1)
        service.startMonitoringProximity(for: alert2)

        service.stopMonitoringProximity(for: alert1)

        #expect(self.locationManagerMock.monitoredRegions.count == 1)
        let remaining = self.locationManagerMock.monitoredRegions.first
        #expect(remaining?.identifier == "oba.proximity.\(alert2.id.uuidString)")
    }

    // MARK: - Stop All Monitoring

    @Test func `Stop monitoring all proximity alerts removes all prefixed regions`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        service.startMonitoringProximity(for: alert1)
        service.startMonitoringProximity(for: alert2)

        service.stopMonitoringAllProximityAlerts()

        #expect(self.locationManagerMock.monitoredRegions.isEmpty)
    }

    @Test func `Stop monitoring all proximity alerts preserves non prefixed regions`() {
        let alert = ProximityAlert(stop: stop)
        service.startMonitoringProximity(for: alert)

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

    // MARK: - Delegate: didEnterRegion

    @Test func `Did enter region notifies delegate`() {
        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: "oba.proximity.\(alert.id.uuidString)"
        )

        service.locationManager(CLLocationManager(), didEnterRegion: region)

        #expect(self.delegate.enteredRegionIdentifier == "oba.proximity.\(alert.id.uuidString)")
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
        let beaconRegion = CLBeaconRegion(
            uuid: UUID(),
            identifier: "oba.proximity.beacon-test"
        )

        service.locationManager(CLLocationManager(), didEnterRegion: beaconRegion)

        #expect(self.delegate.enteredRegionIdentifier == nil)
    }

    // MARK: - Delegate: monitoringDidFail

    @Test func `Monitoring did fail notifies delegate`() {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            radius: 200,
            identifier: UUID().uuidString
        )
        let error = NSError(domain: "CLError", code: 5, userInfo: nil)

        service.locationManager(CLLocationManager(), monitoringDidFailFor: region, withError: error)

        #expect(self.delegate.monitoringFailedIdentifier == region.identifier)
        #expect((self.delegate.monitoringFailedError as? NSError)?.code == 5)
    }

    @Test func `Monitoring did fail nil region notifies delegate`() {
        let error = NSError(domain: "CLError", code: 5, userInfo: nil)

        service.locationManager(CLLocationManager(), monitoringDidFailFor: nil, withError: error)

        #expect(self.delegate.monitoringFailedIdentifier == nil)
        #expect(self.delegate.monitoringFailedError != nil)
    }

    // MARK: - Multiple Delegates

    @Test func `Did enter region notifies multiple delegates`() {
        let delegate2 = LocDelegate()
        service.addDelegate(delegate2)

        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: "oba.proximity.\(alert.id.uuidString)"
        )

        service.locationManager(CLLocationManager(), didEnterRegion: region)

        #expect(self.delegate.enteredRegionIdentifier == "oba.proximity.\(alert.id.uuidString)")
        #expect(delegate2.enteredRegionIdentifier == "oba.proximity.\(alert.id.uuidString)")
    }
}

