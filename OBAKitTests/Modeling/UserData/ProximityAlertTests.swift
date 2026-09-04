//
//  ProximityAlertTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import CoreLocation
import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

// swiftlint:disable force_try

@Suite(.serialized)
final class ProximityAlertTests: OBATestCase {

    var stop: Stop!

    override init() async throws {
        try await super.init()

        stop = try! Fixtures.loadSomeStops().first!
    }

    // MARK: - Model Init

    @Test func `Init sets properties from stop`() {
        let alert = ProximityAlert(stop: stop)

        #expect(alert.stopID == stop.id)
        #expect(alert.stopName == stop.name)
        #expect(alert.latitude == stop.location.coordinate.latitude)
        #expect(alert.longitude == stop.location.coordinate.longitude)
        #expect(alert.radiusMeters == 200.0)
    }

    @Test func `Init custom radius`() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 500.0)

        #expect(alert.radiusMeters == 500.0)
    }

    @Test func `Init records the region the alert was set in`() {
        #expect(ProximityAlert(stop: stop, regionID: 12).regionID == 12)
        // Naming none is the default, and means the tap on this alert's
        // notification falls back to whichever region is current by then.
        #expect(ProximityAlert(stop: stop).regionID == nil)
    }

    // MARK: - Radius Clamping

    @Test func `Init clamps radius below the minimum`() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 5)

        #expect(alert.radiusMeters == ProximityAlert.minimumRadiusMeters)
    }

    @Test func `Init clamps radius above the maximum`() {
        // `CLCircularRegion` would accept this and silently monitor something
        // else, firing the alert at a distance the user never chose.
        let alert = ProximityAlert(stop: stop, radiusMeters: 50_000)

        #expect(alert.radiusMeters == ProximityAlert.maximumRadiusMeters)
    }

    @Test func `Init leaves an in range radius alone`() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 750)

        #expect(alert.radiusMeters == 750)
    }

    @Test func `Init accepts the range boundaries`() {
        let atMinimum = ProximityAlert(stop: stop, radiusMeters: ProximityAlert.minimumRadiusMeters)
        let atMaximum = ProximityAlert(stop: stop, radiusMeters: ProximityAlert.maximumRadiusMeters)

        #expect(atMinimum.radiusMeters == ProximityAlert.minimumRadiusMeters)
        #expect(atMaximum.radiusMeters == ProximityAlert.maximumRadiusMeters)
    }

    @Test func `Init replaces a non finite radius with the default`() {
        // Clamping alone wouldn't save this: `min`/`max` propagate NaN rather
        // than bounding it, leaving a radius Core Location cannot interpret.
        #expect(ProximityAlert(stop: stop, radiusMeters: .nan).radiusMeters == ProximityAlert.defaultRadiusMeters)
        #expect(ProximityAlert(stop: stop, radiusMeters: .infinity).radiusMeters == ProximityAlert.defaultRadiusMeters)
    }

    @Test func `Decoding clamps an out of range persisted radius`() throws {
        let alert = ProximityAlert(stop: stop, radiusMeters: 300)
        let encoded = try JSONEncoder().encode(alert)

        guard var dictionary = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Encoded proximity alert was not a JSON object.")
            return
        }

        // Stands in for an alert written by a build that predates the clamp.
        dictionary["radiusMeters"] = 50_000

        let tampered = try JSONSerialization.data(withJSONObject: dictionary)
        let decoded = try JSONDecoder().decode(ProximityAlert.self, from: tampered)

        #expect(decoded.radiusMeters == ProximityAlert.maximumRadiusMeters)
    }

    @Test func `Decoding an alert persisted without a region yields nil`() throws {
        let alert = ProximityAlert(stop: stop, regionID: 12)
        let encoded = try JSONEncoder().encode(alert)

        guard var dictionary = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
            Issue.record("Encoded proximity alert was not a JSON object.")
            return
        }

        // Stands in for an alert written by a build that predates the field. It
        // has to keep decoding — these are the rider's alerts, not disposable
        // cache — and the missing region is what sends its tap back to whichever
        // one is current.
        dictionary.removeValue(forKey: "regionID")

        let legacy = try JSONSerialization.data(withJSONObject: dictionary)
        let decoded = try JSONDecoder().decode(ProximityAlert.self, from: legacy)

        #expect(decoded.regionID == nil)
        #expect(decoded.stopID == stop.id)
    }

    @Test func `Coordinate returns correct value`() {
        let alert = ProximityAlert(stop: stop)

        #expect(alert.coordinate.latitude == stop.location.coordinate.latitude)
        #expect(alert.coordinate.longitude == stop.location.coordinate.longitude)
    }

    // MARK: - Codable Round-Trip

    @Test func `Codable round trip`() {
        let alert = ProximityAlert(stop: stop, radiusMeters: 350.0)
        let roundtripped = try! Fixtures.roundtripCodable(type: ProximityAlert.self, model: alert)

        #expect(roundtripped.id == alert.id)
        #expect(roundtripped.stopID == alert.stopID)
        #expect(roundtripped.stopName == alert.stopName)
        #expect(roundtripped.latitude == alert.latitude)
        #expect(roundtripped.longitude == alert.longitude)
        #expect(roundtripped.radiusMeters == 350.0)
        expectClose(roundtripped.createdAt.timeIntervalSince1970, alert.createdAt.timeIntervalSince1970, within: 1.0)
        #expect(roundtripped.regionID == nil)
    }

    @Test func `Codable round trip preserves the region`() {
        let alert = ProximityAlert(stop: stop, regionID: 12)
        let roundtripped = try! Fixtures.roundtripCodable(type: ProximityAlert.self, model: alert)

        #expect(roundtripped.regionID == 12)
    }

    @Test func `Codable round trip preserves coordinate`() {
        let alert = ProximityAlert(stop: stop)
        let roundtripped = try! Fixtures.roundtripCodable(type: ProximityAlert.self, model: alert)

        #expect(roundtripped.coordinate.latitude == alert.latitude)
        #expect(roundtripped.coordinate.longitude == alert.longitude)
    }

    // MARK: - Expiration

    @Test func `Is expired false when fresh`() {
        let alert = ProximityAlert(stop: stop)

        #expect(!alert.isExpired)
    }

    @Test func `Is expired true when older than 24 hours`() {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        let alert = ProximityAlert(stop: stop, createdAt: expiredDate)

        #expect(alert.isExpired)
    }

    @Test func `Is expired false just under 24 hours`() {
        let justUnderDate = Date().addingTimeInterval(-24 * 60 * 60 + 5) // 5 seconds under 24 hours
        let alert = ProximityAlert(stop: stop, createdAt: justUnderDate)

        #expect(!alert.isExpired)
    }

    // MARK: - Equality

    @Test func `Equality same ID`() {
        let alert = ProximityAlert(stop: stop)

        #expect(alert.isEqual(alert))
    }

    @Test func `Equality different ID`() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)

        #expect(!alert1.isEqual(alert2))
    }

    @Test func `Equality non proximity alert object`() {
        let alert = ProximityAlert(stop: stop)

        #expect(!alert.isEqual("not an alert"))
    }
}

// MARK: - UserDefaultsStore Integration

@Suite(.serialized)
final class ProximityAlertStoreTests: OBATestCase {

    var userDefaultsStore: UserDefaultsStore!
    var stop: Stop!

    override init() async throws {
        try await super.init()

        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        stop = try! Fixtures.loadSomeStops().first!
    }

    // MARK: - Empty State

    @Test func `Proximity alerts empty by default`() {
        #expect(self.userDefaultsStore.proximityAlerts.isEmpty)
    }

    // MARK: - Add

    @Test func `Add stores alert`() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        #expect(self.userDefaultsStore.proximityAlerts.count == 1)
        #expect(self.userDefaultsStore.proximityAlerts.first?.id == alert.id)
        #expect(self.userDefaultsStore.proximityAlerts.first?.stopID == stop.id)
    }

    @Test func `Add multiple alerts`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        #expect(self.userDefaultsStore.proximityAlerts.count == 2)
    }

    // MARK: - Delete

    @Test func `Delete removes alert`() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        userDefaultsStore.delete(proximityAlert: alert)

        #expect(self.userDefaultsStore.proximityAlerts.isEmpty)
    }

    @Test func `Delete nonexistent alert is no op`() {
        let alert1 = ProximityAlert(stop: stop)
        let alert2 = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert1)

        userDefaultsStore.delete(proximityAlert: alert2)

        #expect(self.userDefaultsStore.proximityAlerts.count == 1)
        #expect(self.userDefaultsStore.proximityAlerts.first?.id == alert1.id)
    }

    @Test func `Delete only removes target alert`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        userDefaultsStore.delete(proximityAlert: alert1)

        #expect(self.userDefaultsStore.proximityAlerts.count == 1)
        #expect(self.userDefaultsStore.proximityAlerts.first?.id == alert2.id)
    }

    // MARK: - Delete All

    @Test func `Delete all removes all alerts`() {
        let stops = try! Fixtures.loadSomeStops()
        let alert1 = ProximityAlert(stop: stops[0])
        let alert2 = ProximityAlert(stop: stops[1])

        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        userDefaultsStore.deleteAllProximityAlerts()

        #expect(self.userDefaultsStore.proximityAlerts.isEmpty)
    }

    // MARK: - Expired Alerts

    @Test func `Delete expired keeps non expired alerts`() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        userDefaultsStore.deleteExpiredProximityAlerts()

        #expect(self.userDefaultsStore.proximityAlerts.count == 1)
    }

    @Test func `Delete expired removes expired alerts`() {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60) // 25 hours ago
        let expiredAlert = ProximityAlert(stop: stop, createdAt: expiredDate)
        let freshAlert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: expiredAlert)
        userDefaultsStore.add(proximityAlert: freshAlert)

        userDefaultsStore.deleteExpiredProximityAlerts()

        #expect(self.userDefaultsStore.proximityAlerts.count == 1)
        #expect(self.userDefaultsStore.proximityAlerts.first?.id == freshAlert.id)
    }

    @Test func `Delete expired removes all when all expired`() {
        let stops = try! Fixtures.loadSomeStops()
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        let alert1 = ProximityAlert(stop: stops[0], createdAt: expiredDate)
        let alert2 = ProximityAlert(stop: stops[1], createdAt: expiredDate)
        userDefaultsStore.add(proximityAlert: alert1)
        userDefaultsStore.add(proximityAlert: alert2)

        userDefaultsStore.deleteExpiredProximityAlerts()

        #expect(self.userDefaultsStore.proximityAlerts.isEmpty)
    }

    @Test func `Delete expired does not post notification when nothing expired`() async {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        await expectProximityAlertsNotification(count: 0) {
            userDefaultsStore.deleteExpiredProximityAlerts()
        }
    }

    @Test func `Delete expired posts notification when expired alerts removed`() async {
        let expiredDate = Date().addingTimeInterval(-25 * 60 * 60)
        let alert = ProximityAlert(stop: stop, createdAt: expiredDate)
        userDefaultsStore.add(proximityAlert: alert)

        await expectProximityAlertsNotification {
            userDefaultsStore.deleteExpiredProximityAlerts()
        }
    }

    // MARK: - Persistence Across Stores

    @Test func `Persists across store instances`() {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        let newStore = UserDefaultsStore(userDefaults: userDefaults)

        #expect(newStore.proximityAlerts.count == 1)
        #expect(newStore.proximityAlerts.first?.id == alert.id)
        #expect(newStore.proximityAlerts.first?.stopID == stop.id)
        #expect(newStore.proximityAlerts.first?.stopName == stop.name)
        #expect(newStore.proximityAlerts.first?.latitude == stop.location.coordinate.latitude)
        #expect(newStore.proximityAlerts.first?.longitude == stop.location.coordinate.longitude)
        #expect(newStore.proximityAlerts.first?.radiusMeters == 200.0)
    }

    // MARK: - Notification

    @Test func `Add posts notification`() async {
        let alert = ProximityAlert(stop: stop)

        await expectProximityAlertsNotification {
            userDefaultsStore.add(proximityAlert: alert)
        }
    }

    @Test func `Delete posts notification`() async {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        await expectProximityAlertsNotification {
            userDefaultsStore.delete(proximityAlert: alert)
        }
    }

    @Test func `Delete all posts notification`() async {
        let alert = ProximityAlert(stop: stop)
        userDefaultsStore.add(proximityAlert: alert)

        await expectProximityAlertsNotification {
            userDefaultsStore.deleteAllProximityAlerts()
        }
    }

    /// Confirms `.proximityAlertsDidChange` is posted while `body` runs — or,
    /// with `count: 0`, that it isn't.
    ///
    /// Replaces `expectation(forNotification:object:)`. `UserDataStore` posts
    /// synchronously, so there is nothing to wait for; the old
    /// `waitForExpectations(timeout:)` calls were burning their timeout on the
    /// inverted case and returning immediately on the rest.
    private func expectProximityAlertsNotification(
        count: Int = 1,
        sourceLocation: SourceLocation = #_sourceLocation,
        during body: () -> Void
    ) async {
        await confirmation(expectedCount: count, sourceLocation: sourceLocation) { posted in
            let token = NotificationCenter.default.addObserver(
                forName: .proximityAlertsDidChange,
                object: userDefaultsStore,
                queue: nil
            ) { _ in posted() }
            defer { NotificationCenter.default.removeObserver(token) }

            body()
        }
    }

}
