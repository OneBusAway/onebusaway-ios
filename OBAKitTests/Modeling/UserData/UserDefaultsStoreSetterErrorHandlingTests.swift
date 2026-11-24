//
//  UserDefaultsStoreSetterErrorHandlingTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKitCore

/// The `UserDefaultsStore` setters that used to call `encodeUserDefaultsObjects`
/// through `try!` trap when `simulatedPersistenceError` is set (or on any real
/// encoding failure). They now log the error and leave the stored value
/// unchanged instead of crashing the app.
@Suite(.serialized)
final class UserDefaultsStoreSetterErrorHandlingTests: OBATestCase {

    var userDefaultsStore: UserDefaultsStore!
    private let stops: [Stop]

    override init() async throws {
        try await super.init()

        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        stops = try Fixtures.loadSomeStops()
    }

    private let simulatedError = NSError(domain: "test.persistence", code: 500, userInfo: nil)

    private func loadServiceAlert() throws -> ServiceAlert {
        let data = Fixtures.loadData(file: "arrival-and-departure-for-stop-MTS_11589.json")
        let response = try JSONDecoder.RESTDecoder().decode(RESTAPIResponse<ArrivalDeparture>.self, from: data)
        return try #require(response.references?.serviceAlerts.first)
    }

    @Test func `RecentStops setter retains the stored value when persistence fails`() {
        userDefaultsStore.recentStops = [stops[0]]
        userDefaultsStore.simulatedPersistenceError = simulatedError

        userDefaultsStore.recentStops = []

        #expect(userDefaultsStore.recentStops == [stops[0]])
        userDefaultsStore.simulatedPersistenceError = nil
    }

    @Test func `Alarms setter retains the stored value when persistence fails`() throws {
        let alarm = try Fixtures.loadAlarm(id: "setter-error-handling")
        userDefaultsStore.alarms = [alarm]
        userDefaultsStore.simulatedPersistenceError = simulatedError

        userDefaultsStore.alarms = []

        #expect(userDefaultsStore.alarms.map(\.url) == [alarm.url])
        userDefaultsStore.simulatedPersistenceError = nil
    }

    @Test func `ProximityAlerts setter retains the stored value when persistence fails`() {
        let alert = ProximityAlert(stop: stops[0], regionID: 12)
        userDefaultsStore.proximityAlerts = [alert]
        userDefaultsStore.simulatedPersistenceError = simulatedError

        userDefaultsStore.proximityAlerts = []

        #expect(userDefaultsStore.proximityAlerts == [alert])
        userDefaultsStore.simulatedPersistenceError = nil
    }

    @Test func `Completed surveys setter logs instead of trapping when persistence fails`() {
        userDefaultsStore.simulatedPersistenceError = simulatedError

        userDefaultsStore.markSurveyCompleted(surveyId: 7, userIdentifier: "user-1")

        #expect(!userDefaultsStore.isSurveyCompleted(surveyId: 7, userIdentifier: "user-1"))
        userDefaultsStore.simulatedPersistenceError = nil

        userDefaultsStore.markSurveyCompleted(surveyId: 7, userIdentifier: "user-1")
        #expect(userDefaultsStore.isSurveyCompleted(surveyId: 7, userIdentifier: "user-1"))
    }

    @Test func `Surveys for later setter logs instead of trapping when persistence fails`() {
        userDefaultsStore.simulatedPersistenceError = simulatedError

        userDefaultsStore.markSurveyForLater(surveyId: 9, userIdentifier: "user-2")

        #expect(!userDefaultsStore.isSurveyMarkedForLater(surveyId: 9, userIdentifier: "user-2"))
        userDefaultsStore.simulatedPersistenceError = nil

        userDefaultsStore.markSurveyForLater(surveyId: 9, userIdentifier: "user-2")
        #expect(userDefaultsStore.isSurveyMarkedForLater(surveyId: 9, userIdentifier: "user-2"))
    }

    @Test func `Stop preferences setter logs instead of trapping when persistence fails`() {
        let stop = stops[0]
        let region = Fixtures.pugetSoundRegion
        let prefs = StopPreferences(sortType: .route, hiddenRoutes: [])

        userDefaultsStore.simulatedPersistenceError = simulatedError
        userDefaultsStore.set(stopPreferences: prefs, stop: stop, region: region)

        // Write failed: the default still holds.
        #expect(userDefaultsStore.preferences(stopID: stop.id, region: region).sortType == .time)
        userDefaultsStore.simulatedPersistenceError = nil

        userDefaultsStore.set(stopPreferences: prefs, stop: stop, region: region)
        #expect(userDefaultsStore.preferences(stopID: stop.id, region: region).sortType == .route)
    }

    @Test func `Read service alerts setter retains the unread state when persistence fails`() throws {
        let serviceAlert = try loadServiceAlert()

        userDefaultsStore.simulatedPersistenceError = simulatedError
        userDefaultsStore.markRead(serviceAlert: serviceAlert)

        #expect(userDefaultsStore.isUnread(serviceAlert: serviceAlert))
        userDefaultsStore.simulatedPersistenceError = nil

        userDefaultsStore.markRead(serviceAlert: serviceAlert)
        #expect(!userDefaultsStore.isUnread(serviceAlert: serviceAlert))
    }

    @Test func `Trip planning setter logs and keeps the default when persistence fails`() {
        let region = Fixtures.pugetSoundRegion

        userDefaultsStore.simulatedPersistenceError = simulatedError
        userDefaultsStore.setTripPlanningEnabled(false, for: region)

        // The write failed: the default (enabled) still holds.
        #expect(userDefaultsStore.isTripPlanningEnabled(for: region))
        userDefaultsStore.simulatedPersistenceError = nil

        userDefaultsStore.setTripPlanningEnabled(false, for: region)
        #expect(!userDefaultsStore.isTripPlanningEnabled(for: region))
    }
}
