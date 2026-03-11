//
//  LocationServiceRegionMonitoringTests.swift
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

// swiftlint:disable force_try

class LocationServiceRegionMonitoringTests: OBATestCase {

    var locationManagerMock: LocationManagerMock!
    var service: LocationService!
    var delegate: LocDelegate!
    var stop: Stop!

    override func setUp() {
        super.setUp()
        locationManagerMock = LocationManagerMock()
        service = LocationService(userDefaults: userDefaults, locationManager: locationManagerMock)
        delegate = LocDelegate()
        service.addDelegate(delegate)
        stop = try! Fixtures.loadSomeStops().first!
    }

    // MARK: - Start Monitoring

    func test_startMonitoringProximity_createsRegionWithCorrectProperties() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 300.0)

        service.startMonitoringProximity(for: alert)

        expect(self.locationManagerMock.monitoredRegions.count) == 1

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        expect(region).toNot(beNil())
        expect(region?.identifier) == alert.id.uuidString
        expect(region?.center.latitude) == stop.location.coordinate.latitude
        expect(region?.center.longitude) == stop.location.coordinate.longitude
        expect(region?.radius) == 300.0
        expect(region?.notifyOnEntry).to(beTrue())
        expect(region?.notifyOnExit).to(beFalse())
    }

    func test_startMonitoringProximity_defaultRadius() {
        let alert = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert)

        let region = locationManagerMock.monitoredRegions.first as? CLCircularRegion
        expect(region?.radius) == 200.0
    }

    func test_startMonitoringProximity_multipleAlerts() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        service.startMonitoringProximity(for: alert1)
        service.startMonitoringProximity(for: alert2)

        expect(self.locationManagerMock.monitoredRegions.count) == 2
    }

    // MARK: - Stop Monitoring

    func test_stopMonitoringProximity_removesCorrectRegion() {
        let alert = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert)
        expect(self.locationManagerMock.monitoredRegions.count) == 1

        service.stopMonitoringProximity(for: alert)
        expect(self.locationManagerMock.monitoredRegions).to(beEmpty())
    }

    func test_stopMonitoringProximity_nonexistentAlert_isNoOp() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)

        service.startMonitoringProximity(for: alert1)

        service.stopMonitoringProximity(for: alert2)

        expect(self.locationManagerMock.monitoredRegions.count) == 1
    }

    func test_stopMonitoringProximity_onlyRemovesTargetRegion() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        service.startMonitoringProximity(for: alert1)
        service.startMonitoringProximity(for: alert2)

        service.stopMonitoringProximity(for: alert1)

        expect(self.locationManagerMock.monitoredRegions.count) == 1
        let remaining = self.locationManagerMock.monitoredRegions.first
        expect(remaining?.identifier) == alert2.id.uuidString
    }

    // MARK: - Stop All Monitoring

    func test_stopMonitoringAllProximityAlerts_removesAllUUIDRegions() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        service.startMonitoringProximity(for: alert1)
        service.startMonitoringProximity(for: alert2)

        service.stopMonitoringAllProximityAlerts()

        expect(self.locationManagerMock.monitoredRegions).to(beEmpty())
    }

    func test_stopMonitoringAllProximityAlerts_preservesNonUUIDRegions() {
        let alert = ProximityAlert(stop: stop)
        service.startMonitoringProximity(for: alert)

        let otherRegion = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            radius: 100,
            identifier: "not-a-uuid-region"
        )
        locationManagerMock.startMonitoring(for: otherRegion)

        expect(self.locationManagerMock.monitoredRegions.count) == 2

        service.stopMonitoringAllProximityAlerts()

        expect(self.locationManagerMock.monitoredRegions.count) == 1
        expect(self.locationManagerMock.monitoredRegions.first?.identifier) == "not-a-uuid-region"
    }

    // MARK: - Delegate: didEnterRegion

    func test_didEnterRegion_notifiesDelegate() {
        let alert = ProximityAlert(stop: stop)
        let region = CLCircularRegion(
            center: alert.coordinate,
            radius: alert.radiusMeters,
            identifier: alert.id.uuidString
        )

        service.locationManager(CLLocationManager(), didEnterRegion: region)

        expect(self.delegate.enteredRegionIdentifier) == alert.id.uuidString
    }

    func test_didEnterRegion_nonCircularRegion_doesNotNotify() {
        let beaconRegion = CLBeaconRegion(
            uuid: UUID(),
            identifier: "beacon-test"
        )

        service.locationManager(CLLocationManager(), didEnterRegion: beaconRegion)

        expect(self.delegate.enteredRegionIdentifier).to(beNil())
    }

    // MARK: - Delegate: monitoringDidFail

    func test_monitoringDidFail_notifiesDelegate() {
        let region = CLCircularRegion(
            center: CLLocationCoordinate2D(latitude: 47.0, longitude: -122.0),
            radius: 200,
            identifier: UUID().uuidString
        )
        let error = NSError(domain: "CLError", code: 5, userInfo: nil)

        service.locationManager(CLLocationManager(), monitoringDidFailFor: region, withError: error)

        expect(self.delegate.monitoringFailedIdentifier) == region.identifier
        expect((self.delegate.monitoringFailedError as? NSError)?.code) == 5
    }

    func test_monitoringDidFail_nilRegion_notifiesDelegate() {
        let error = NSError(domain: "CLError", code: 5, userInfo: nil)

        service.locationManager(CLLocationManager(), monitoringDidFailFor: nil, withError: error)

        expect(self.delegate.monitoringFailedIdentifier).to(beNil())
        expect(self.delegate.monitoringFailedError).toNot(beNil())
    }
}
