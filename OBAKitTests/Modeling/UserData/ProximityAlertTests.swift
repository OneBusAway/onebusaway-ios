//
//  ProximityAlertTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import XCTest
import Nimble
import CoreLocation
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

class ProximityAlertTests: OBATestCase {

    var stop: Stop!

    override func setUp() {
        super.setUp()
        stop = try! Fixtures.loadSomeStops().first!
    }

    // MARK: - Model Init

    func test_init_setsPropertiesFromStop() {
        let alert = ProximityAlert(stop: stop)

        expect(alert.stopID) == stop.id
        expect(alert.stopName) == stop.name
        expect(alert.latitude) == stop.location.coordinate.latitude
        expect(alert.longitude) == stop.location.coordinate.longitude
        expect(alert.radiusMeters) == 200.0
        expect(alert.id).toNot(beNil())
        expect(alert.createdAt).toNot(beNil())
    }

    func test_init_customRadius() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 500.0)

        expect(alert.radiusMeters) == 500.0
    }

    func test_coordinate_returnsCorrectValue() {
        let alert = ProximityAlert(stop: stop)

        expect(alert.coordinate.latitude) == stop.location.coordinate.latitude
        expect(alert.coordinate.longitude) == stop.location.coordinate.longitude
    }

    // MARK: - Codable Round-Trip

    func test_codable_roundTrip() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 350.0)
        let roundtripped = try! Fixtures.roundtripCodable(type: ProximityAlert.self, model: alert)

        expect(roundtripped.id) == alert.id
        expect(roundtripped.stopID) == alert.stopID
        expect(roundtripped.stopName) == alert.stopName
        expect(roundtripped.latitude) == alert.latitude
        expect(roundtripped.longitude) == alert.longitude
        expect(roundtripped.radiusMeters) == 350.0
        expect(roundtripped.createdAt.timeIntervalSince1970).to(beCloseTo(alert.createdAt.timeIntervalSince1970, within: 1.0))
    }

    func test_codable_roundTrip_preservesCoordinate() {
        let alert = ProximityAlert(stop: stop)
        let roundtripped = try! Fixtures.roundtripCodable(type: ProximityAlert.self, model: alert)

        expect(roundtripped.coordinate.latitude) == alert.latitude
        expect(roundtripped.coordinate.longitude) == alert.longitude
    }

    // MARK: - Expiration

    func test_isExpired_falseWhenFresh() {
        let alert = ProximityAlert(stop: stop)

        expect(alert.isExpired).to(beFalse())
    }

    func test_isExpired_trueWhenOlderThan24Hours() {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        let alert = ProximityAlert(stop: stop, createdAt: expiredDate)

        expect(alert.isExpired).to(beTrue())
    }

    // MARK: - Equality

    func test_equality_sameID() {
        let alert = ProximityAlert(stop: stop)

        expect(alert.isEqual(alert)).to(beTrue())
    }

    func test_equality_differentID() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)

        expect(alert1.isEqual(alert2)).to(beFalse())
    }

    func test_equality_nonProximityAlertObject() {
        let alert = ProximityAlert(stop: stop)

        expect(alert.isEqual("not an alert")).to(beFalse())
    }
}

// MARK: - UserDefaultsStore Integration

class ProximityAlertStoreTests: OBATestCase {

    var userDefaultsStore: UserDefaultsStore!
    var stop: Stop!

    override func setUp() {
        super.setUp()
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        stop = try! Fixtures.loadSomeStops().first!
    }

    // MARK: - Empty State

    func test_proximityAlerts_emptyByDefault() {
        expect(self.userDefaultsStore.proximityAlerts).to(beEmpty())
    }

    // MARK: - Add

    func test_add_storesAlert() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        expect(self.userDefaultsStore.proximityAlerts.count) == 1
        expect(self.userDefaultsStore.proximityAlerts.first?.id) == alert.id
        expect(self.userDefaultsStore.proximityAlerts.first?.stopID) == stop.id
    }

    func test_add_multipleAlerts() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        expect(self.userDefaultsStore.proximityAlerts.count) == 2
    }

    // MARK: - Delete

    func test_delete_removesAlert() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        userDefaultsStore.delete(proximityAlert: alert)

        expect(self.userDefaultsStore.proximityAlerts).to(beEmpty())
    }

    func test_delete_nonexistentAlert_isNoOp() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert1)

        userDefaultsStore.delete(proximityAlert: alert2)

        expect(self.userDefaultsStore.proximityAlerts.count) == 1
        expect(self.userDefaultsStore.proximityAlerts.first?.id) == alert1.id
    }

    func test_delete_onlyRemovesTargetAlert() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        userDefaultsStore.delete(proximityAlert: alert1)

        expect(self.userDefaultsStore.proximityAlerts.count) == 1
        expect(self.userDefaultsStore.proximityAlerts.first?.id) == alert2.id
    }

    // MARK: - Delete All

    func test_deleteAll_removesAllAlerts() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        userDefaultsStore.deleteAllProximityAlerts()

        expect(self.userDefaultsStore.proximityAlerts).to(beEmpty())
    }

    // MARK: - Expired Alerts

    func test_deleteExpired_keepsNonExpiredAlerts() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        userDefaultsStore.deleteExpiredProximityAlerts()

        expect(self.userDefaultsStore.proximityAlerts.count) == 1
    }

    func test_deleteExpired_removesExpiredAlerts() {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60) // 25 hours ago
        let expiredAlert = ProximityAlert(stop: stop, createdAt: expiredDate)
        let freshAlert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: expiredAlert)
        userDefaultsStore.add(proximityAlert: freshAlert)

        userDefaultsStore.deleteExpiredProximityAlerts()

        expect(self.userDefaultsStore.proximityAlerts.count) == 1
        expect(self.userDefaultsStore.proximityAlerts.first?.id) == freshAlert.id
    }

    func test_deleteExpired_removesAllWhenAllExpired() {
        let stops = try! Fixtures.loadSomeStops()
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        let alert1 = ProximityAlert(stop: stops[0], createdAt: expiredDate)
        let alert2 = ProximityAlert(stop: stops[1], createdAt: expiredDate)
        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        userDefaultsStore.deleteExpiredProximityAlerts()

        expect(self.userDefaultsStore.proximityAlerts).to(beEmpty())
    }

    func test_deleteExpired_doesNotPostNotification_whenNothingExpired() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        let notificationExpectation = expectation(forNotification: .proximityAlertsDidChange, object: userDefaultsStore)
        notificationExpectation.isInverted = true

        userDefaultsStore.deleteExpiredProximityAlerts()

        waitForExpectations(timeout: 0.5)
    }

    // MARK: - Persistence Across Stores

    func test_persistsAcrossStoreInstances() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        let newStore = UserDefaultsStore(userDefaults: userDefaults)

        expect(newStore.proximityAlerts.count) == 1
        expect(newStore.proximityAlerts.first?.id) == alert.id
        expect(newStore.proximityAlerts.first?.stopID) == stop.id
        expect(newStore.proximityAlerts.first?.stopName) == stop.name
        expect(newStore.proximityAlerts.first?.latitude) == stop.location.coordinate.latitude
        expect(newStore.proximityAlerts.first?.longitude) == stop.location.coordinate.longitude
        expect(newStore.proximityAlerts.first?.radiusMeters) == 200.0
    }

    // MARK: - Notification

    func test_add_postsNotification() {
        let alert = ProximityAlert(stop: stop)

        expectation(forNotification: .proximityAlertsDidChange, object: userDefaultsStore)
        userDefaultsStore.add(proximityAlert: alert)

        waitForExpectations(timeout: 1.0)
    }

    func test_delete_postsNotification() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        expectation(forNotification: .proximityAlertsDidChange, object: userDefaultsStore)
        userDefaultsStore.delete(proximityAlert: alert)

        waitForExpectations(timeout: 1.0)
    }

    func test_deleteAll_postsNotification() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        expectation(forNotification: .proximityAlertsDidChange, object: userDefaultsStore)
        userDefaultsStore.deleteAllProximityAlerts()

        waitForExpectations(timeout: 1.0)
    }
}
