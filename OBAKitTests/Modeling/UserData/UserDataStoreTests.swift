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

    override func setUp() {
        super.setUp()
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        region = try! Fixtures.loadSomeRegions()[1]
    }

    override func tearDown() {
        super.tearDown()
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

    func test_appLaunch_defaultValueIsZero() {
        expect(self.userDefaultsStore.appLaunch) == 0
    }

    func test_appLaunch_readsStoredValue() {
        userDefaultsStore.increaseAppLaunchCount()
        expect(self.userDefaultsStore.appLaunch) == 1
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

}
