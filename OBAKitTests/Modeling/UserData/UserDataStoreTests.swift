//
//  UserDataStoreTests.swift
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

class UserDefaultsStoreTests: OBATestCase {
    var userDefaultsStore: UserDefaultsStore!
    var region: Region!

    override func setUp() async throws {
        try await super.setUp()
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        region = try! Fixtures.loadSomeRegions()[1]
    }

    override func tearDown() async throws {
        try await super.tearDown()
    }

    // MARK: - Core

    func test_garbageData_doesNotBreakApp() {
        let garbageDefaults = UserDefaults(suiteName: "garbage data test")!
        garbageDefaults.set("garbage data", forKey: "bookmarkGroups")
        let garbageStore = UserDefaultsStore(userDefaults: garbageDefaults)

        expect(garbageStore.bookmarkGroups) == []
    }

    // MARK: - Recent Stops

    func test_recentStops_addStop() {
        let stops = try! Fixtures.loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_uniqueStops() {
        let stops = try! Fixtures.loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)
        userDefaultsStore.addRecentStop(stop, region: region)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_maxCount() {
        let stops = try! Fixtures.loadSomeStops()
        expect(stops.count).to(beGreaterThan(userDefaultsStore.maximumRecentStopsCount))

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        expect(self.userDefaultsStore.recentStops.count) == userDefaultsStore.maximumRecentStopsCount
    }

    func test_recentStops_search() {
        let stops = try! Fixtures.loadSomeStops()

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        let stop = userDefaultsStore.recentStops[5]
        let mungedStopName = "\r\n\(stop.name.lowercased())\r\n"
        let matches = userDefaultsStore.findRecentStops(matching: mungedStopName)

        expect(matches.count) >= 1
        let filtered = matches.filter({ $0.id == stop.id })
        expect(filtered.first!) == stop
    }

    func test_recentStops_removeAll() {
        let stops = try! Fixtures.loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)

        userDefaultsStore.deleteAllRecentStops()

        expect(self.userDefaultsStore.recentStops.count) == 0
    }

    func test_recentStops_removeStop() {
        let stops = try! Fixtures.loadSomeStops().prefix(20)
        let stop = stops.first!

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        userDefaultsStore.delete(recentStop: stop)

        expect(self.userDefaultsStore.recentStops.count) == (stops.count - 1)
    }

    // MARK: - Alarms

    func test_alarms_deleteMissingTripDate() {
        let missingDataAlarm = try! Fixtures.loadAlarm(id: "1")

        let futureAlarm = try! Fixtures.loadAlarm(id: "2")
        futureAlarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)

        userDefaultsStore.add(alarm: missingDataAlarm)
        userDefaultsStore.add(alarm: futureAlarm)

        let IDs1 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        expect(IDs1) == ["1", "2"]

        userDefaultsStore.deleteExpiredAlarms()

        let IDs2 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        expect(IDs2) == ["2"]

    }

    func test_alarms_deleteExpired() {
        let expiredAlarm = try! Fixtures.loadAlarm(id: "1")
        expiredAlarm.set(tripDate: Date(timeIntervalSinceReferenceDate: 0), alarmOffset: 5)

        let futureAlarm = try! Fixtures.loadAlarm(id: "2")
        futureAlarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)

        userDefaultsStore.add(alarm: expiredAlarm)
        userDefaultsStore.add(alarm: futureAlarm)

        let IDs1 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        expect(IDs1) == ["1", "2"]

        userDefaultsStore.deleteExpiredAlarms()

        let IDs2 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        expect(IDs2) == ["2"]
    }

    /// Regression test for the `tripDate`/`alarmDate` precision-loss bug in `Alarm.isEqual`.
    /// Before the fix, encoding to UserDefaults stripped sub-microsecond precision from
    /// the `Date` fields (via the `TimeInterval` round-trip in `Alarm.{init(from:),encode(to:)}`),
    /// so the reloaded Alarm would no longer compare equal to its in-memory original — and
    /// any equality-based delete would silently no-op. This test persists, reloads, then
    /// deletes by the round-tripped instance to anchor the fix path to a named test.
    func test_alarms_delete_afterUserDefaultsRoundTrip() {
        let alarm = try! Fixtures.loadAlarm(id: "round-trip")
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)

        userDefaultsStore.add(alarm: alarm)

        // Force the encode → decode round-trip by going through the `alarms` getter,
        // which reads back from UserDefaults rather than returning the in-memory instance.
        let reloaded = userDefaultsStore.alarms.first { $0.url == alarm.url }
        expect(reloaded).toNot(beNil())
        expect(reloaded) == alarm

        userDefaultsStore.delete(alarm: reloaded!)

        expect(self.userDefaultsStore.alarms.map(\.url)).toNot(contain(alarm.url))
    }

    // MARK: - Selected Tab Index

    func test_selectedTabIndex_mapSelectedByDefault() {
        expect(self.userDefaultsStore.lastSelectedView) == SelectedTab.map
    }

    func test_selectedTabIndex_changingDefaults() {
        userDefaultsStore.lastSelectedView = .bookmarks
        expect(self.userDefaultsStore.lastSelectedView) == SelectedTab.bookmarks
    }

    func test_selectedTabIndex_invalidRawValueFallsBackToMap() {
        userDefaults.set(999, forKey: "UserDataStore.lastSelectedView")
        expect(self.userDefaultsStore.lastSelectedView) == SelectedTab.map
    }

    // MARK: - Debug Mode

    func test_debugMode_defaultValue() {
        expect(self.userDefaultsStore.debugMode).to(beFalse())
    }

    func test_debugMode_setValue() {
        self.userDefaultsStore.debugMode = true
        expect(self.userDefaultsStore.debugMode).to(beTrue())

        let newStore = UserDefaultsStore(userDefaults: userDefaults)
        expect(newStore.debugMode).to(beTrue())
    }

    // MARK: - Stop UI Reduced Colors

    func test_stopUIReducedColors_defaultValue() {
        expect(self.userDefaultsStore.stopUIReducedColors).to(beFalse())
    }

    func test_stopUIReducedColors_setValue_persistsUnderTheAppStorageKey() {
        userDefaultsStore.stopUIReducedColors = true
        expect(self.userDefaultsStore.stopUIReducedColors).to(beTrue())
        // The @AppStorage readers and the Eureka form must see the same key,
        // and it must stay dot-free or KVO observation silently stops firing.
        expect(UserDefaultsStore.stopUIReducedColorsKey) == "stopUIReducedColors"
        expect(self.userDefaultsStore.userDefaults.bool(forKey: UserDefaultsStore.stopUIReducedColorsKey)).to(beTrue())
    }

    // MARK: - Survey Properties

    func test_surveyUserIdentifier_generatesUUID() {
        let id = userDefaultsStore.surveyUserIdentifier
        expect(id).toNot(beEmpty())
    }

    func test_surveyUserIdentifier_persistsBetweenCalls() {
        let first = userDefaultsStore.surveyUserIdentifier
        let second = userDefaultsStore.surveyUserIdentifier
        expect(first) == second
    }

    // MARK: - App Launch Counter

    func test_appLaunchCount_defaultValueIsZero() {
        expect(self.userDefaultsStore.appLaunchCount) == 0
    }

    func test_appLaunchCount_incrementsCorrectly() {
        userDefaultsStore.incrementAppLaunchCount()
        expect(self.userDefaultsStore.appLaunchCount) == 1

        userDefaultsStore.incrementAppLaunchCount()
        expect(self.userDefaultsStore.appLaunchCount) == 2
    }

    // MARK: - Survey Enabled

    func test_isSurveyEnabled_defaultsToTrue() {
        expect(self.userDefaultsStore.isSurveyEnabled).to(beTrue())
    }

    func test_isSurveyEnabled_persistsValue() {
        userDefaultsStore.isSurveyEnabled = false
        expect(self.userDefaultsStore.isSurveyEnabled).to(beFalse())

        userDefaultsStore.isSurveyEnabled = true
        expect(self.userDefaultsStore.isSurveyEnabled).to(beTrue())
    }

    // MARK: - Next Survey Reminder Date

    func test_nextSurveyReminderDate_defaultsToNil() {
        expect(self.userDefaultsStore.nextSurveyReminderDate).to(beNil())
    }

    func test_nextSurveyReminderDate_persistsValue() {
        let date = Date().addingTimeInterval(3600)
        userDefaultsStore.nextSurveyReminderDate = date
        expect(self.userDefaultsStore.nextSurveyReminderDate).to(beCloseTo(date, within: 1))
    }

    // MARK: - Survey Completion Tracking

    func test_markSurveyCompleted_tracksCompletedSurvey() {
        userDefaultsStore.markSurveyCompleted(surveyId: 1, userIdentifier: "user1")
        expect(self.userDefaultsStore.isSurveyCompleted(surveyId: 1, userIdentifier: "user1")).to(beTrue())
        expect(self.userDefaultsStore.isSurveyCompleted(surveyId: 2, userIdentifier: "user1")).to(beFalse())
    }

    func test_markSurveyForLater_tracksLaterSurvey() {
        userDefaultsStore.markSurveyForLater(surveyId: 1, userIdentifier: "user1")
        // Immediately after marking, shouldShowSurveyLater returns false (0 launches since marking)
        expect(self.userDefaultsStore.shouldShowSurveyLater(surveyId: 1, userIdentifier: "user1")).to(beFalse())
    }

    // MARK: - Walking Speed

    func test_walkingSpeed_defaultValue() {
        expect(self.userDefaultsStore.walkingSpeedMetersPerSecond).to(beCloseTo(1.4))
    }

    func test_walkingSpeed_roundTrip() {
        userDefaultsStore.walkingSpeedMetersPerSecond = 0.9
        expect(self.userDefaultsStore.walkingSpeedMetersPerSecond).to(beCloseTo(0.9))

        userDefaultsStore.walkingSpeedMetersPerSecond = 1.8
        expect(self.userDefaultsStore.walkingSpeedMetersPerSecond).to(beCloseTo(1.8))

        let newStore = UserDefaultsStore(userDefaults: userDefaults)
        expect(newStore.walkingSpeedMetersPerSecond).to(beCloseTo(1.8))
    }

    func test_walkingSpeedSource_defaultValue() {
        expect(self.userDefaultsStore.walkingSpeedSource) == .manual
    }

    func test_walkingSpeedSource_roundTrip() {
        userDefaultsStore.walkingSpeedSource = .healthKit
        expect(self.userDefaultsStore.walkingSpeedSource) == .healthKit

        userDefaultsStore.walkingSpeedSource = .manual
        expect(self.userDefaultsStore.walkingSpeedSource) == .manual
    }

    func test_walkingSpeedMetersPerSecond_clampsBelowRange() {
        userDefaultsStore.walkingSpeedMetersPerSecond = 0.1
        expect(self.userDefaultsStore.walkingSpeedMetersPerSecond).to(beCloseTo(WalkingSpeed.validRange.lowerBound))
    }

    func test_walkingSpeedMetersPerSecond_clampsAboveRange() {
        userDefaultsStore.walkingSpeedMetersPerSecond = 10.0
        expect(self.userDefaultsStore.walkingSpeedMetersPerSecond).to(beCloseTo(WalkingSpeed.validRange.upperBound))
    }

    // MARK: - Default Alarm Lead Time

    func test_defaultAlarmLeadTime_is10Minutes() {
        expect(self.userDefaultsStore.defaultAlarmLeadTimeMinutes) == 10
    }

    func test_defaultAlarmLeadTime_ignoresAndClearsLegacyStoredValue() {
        userDefaults.set(2, forKey: "UserDataStore.defaultAlarmLeadTimeMinutes")

        let newStore = UserDefaultsStore(userDefaults: userDefaults)

        expect(newStore.defaultAlarmLeadTimeMinutes) == 10
        expect(self.userDefaults.object(forKey: "UserDataStore.defaultAlarmLeadTimeMinutes")).to(beNil())
    }

}
