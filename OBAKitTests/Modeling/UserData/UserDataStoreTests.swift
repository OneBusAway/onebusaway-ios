//
//  UserDataStoreTests.swift
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
final class UserDefaultsStoreTests: OBATestCase {
    var userDefaultsStore: UserDefaultsStore!
    var region: Region!

    override init() async throws {
        try await super.init()

        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
        region = try! Fixtures.loadSomeRegions()[1]
    }

    // MARK: - Core

    @Test func `Garbage data does not break app`() {
        let garbageDefaults = UserDefaults(suiteName: "garbage data test")!
        garbageDefaults.set("garbage data", forKey: "bookmarkGroups")
        let garbageStore = UserDefaultsStore(userDefaults: garbageDefaults)

        #expect(garbageStore.bookmarkGroups == [])
    }

    // MARK: - Recent Stops

    @Test func `Recent stops add stop`() {
        let stops = try! Fixtures.loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)

        #expect(self.userDefaultsStore.recentStops == [stop])
    }

    @Test func `Recent stops unique stops`() {
        let stops = try! Fixtures.loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)
        userDefaultsStore.addRecentStop(stop, region: region)

        #expect(self.userDefaultsStore.recentStops == [stop])
    }

    @Test func `Recent stops max count`() {
        let stops = try! Fixtures.loadSomeStops()
        #expect(stops.count > userDefaultsStore.maximumRecentStopsCount)

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        #expect(self.userDefaultsStore.recentStops.count == userDefaultsStore.maximumRecentStopsCount)
    }

    @Test func `Recent stops search`() {
        let stops = try! Fixtures.loadSomeStops()

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        let stop = userDefaultsStore.recentStops[5]
        let mungedStopName = "\r\n\(stop.name.lowercased())\r\n"
        let matches = userDefaultsStore.findRecentStops(matching: mungedStopName)

        #expect(matches.count >= 1)
        let filtered = matches.filter({ $0.id == stop.id })
        #expect(filtered.first! == stop)
    }

    @Test func `Recent stops remove all`() {
        let stops = try! Fixtures.loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)

        userDefaultsStore.deleteAllRecentStops()

        #expect(self.userDefaultsStore.recentStops.count == 0)
    }

    @Test func `Recent stops remove stop`() {
        let stops = try! Fixtures.loadSomeStops().prefix(20)
        let stop = stops.first!

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        userDefaultsStore.delete(recentStop: stop)

        #expect(self.userDefaultsStore.recentStops.count == (stops.count - 1))
    }

    // MARK: - Alarms

    @Test func `Alarms delete missing trip date`() {
        let missingDataAlarm = try! Fixtures.loadAlarm(id: "1")

        let futureAlarm = try! Fixtures.loadAlarm(id: "2")
        futureAlarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)

        userDefaultsStore.add(alarm: missingDataAlarm)
        userDefaultsStore.add(alarm: futureAlarm)

        let IDs1 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        #expect(IDs1 == ["1", "2"])

        userDefaultsStore.deleteExpiredAlarms()

        let IDs2 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        #expect(IDs2 == ["2"])

    }

    @Test func `Alarms delete expired`() {
        let expiredAlarm = try! Fixtures.loadAlarm(id: "1")
        expiredAlarm.set(tripDate: Date(timeIntervalSinceReferenceDate: 0), alarmOffset: 5)

        let futureAlarm = try! Fixtures.loadAlarm(id: "2")
        futureAlarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)

        userDefaultsStore.add(alarm: expiredAlarm)
        userDefaultsStore.add(alarm: futureAlarm)

        let IDs1 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        #expect(IDs1 == ["1", "2"])

        userDefaultsStore.deleteExpiredAlarms()

        let IDs2 = userDefaultsStore.alarms.map({ String($0.url.absoluteString.split(separator: "/").last!) }).sorted()
        #expect(IDs2 == ["2"])
    }

    /// Regression test for the `tripDate`/`alarmDate` precision-loss bug in `Alarm.isEqual`.
    /// Before the fix, encoding to UserDefaults stripped sub-microsecond precision from
    /// the `Date` fields (via the `TimeInterval` round-trip in `Alarm.{init(from:),encode(to:)}`),
    /// so the reloaded Alarm would no longer compare equal to its in-memory original — and
    /// any equality-based delete would silently no-op. This test persists, reloads, then
    /// deletes by the round-tripped instance to anchor the fix path to a named test.
    @Test func `Alarms delete after user defaults round trip`() {
        let alarm = try! Fixtures.loadAlarm(id: "round-trip")
        alarm.set(tripDate: Date(timeIntervalSinceNow: 300), alarmOffset: 2)

        userDefaultsStore.add(alarm: alarm)

        // Force the encode → decode round-trip by going through the `alarms` getter,
        // which reads back from UserDefaults rather than returning the in-memory instance.
        let reloaded = userDefaultsStore.alarms.first { $0.url == alarm.url }
        #expect(reloaded != nil)
        #expect(reloaded == alarm)

        userDefaultsStore.delete(alarm: reloaded!)

        #expect(!self.userDefaultsStore.alarms.map(\.url).contains(alarm.url))
    }

    // MARK: - Selected Tab Index

    @Test func `Selected tab index map selected by default`() {
        #expect(self.userDefaultsStore.lastSelectedView == SelectedTab.map)
    }

    @Test func `Selected tab index changing defaults`() {
        userDefaultsStore.lastSelectedView = .bookmarks
        #expect(self.userDefaultsStore.lastSelectedView == SelectedTab.bookmarks)
    }

    @Test func `Selected tab index invalid raw value falls back to map`() {
        userDefaults.set(999, forKey: "UserDataStore.lastSelectedView")
        #expect(self.userDefaultsStore.lastSelectedView == SelectedTab.map)
    }

    // MARK: - Debug Mode

    @Test func `Debug mode default value`() {
        #expect(!self.userDefaultsStore.debugMode)
    }

    @Test func `Debug mode set value`() {
        self.userDefaultsStore.debugMode = true
        #expect(self.userDefaultsStore.debugMode)

        let newStore = UserDefaultsStore(userDefaults: userDefaults)
        #expect(newStore.debugMode)
    }

    // MARK: - Stop UI Reduced Colors

    @Test func `Stop UI reduced colors default value`() {
        #expect(!self.userDefaultsStore.stopUIReducedColors)
    }

    @Test func `Stop UI reduced colors set value persists under the app storage key`() {
        userDefaultsStore.stopUIReducedColors = true
        #expect(self.userDefaultsStore.stopUIReducedColors)
        // The @AppStorage readers and the Eureka form must see the same key,
        // and it must stay dot-free or KVO observation silently stops firing.
        #expect(UserDefaultsStore.stopUIReducedColorsKey == "stopUIReducedColors")
        #expect(self.userDefaultsStore.userDefaults.bool(forKey: UserDefaultsStore.stopUIReducedColorsKey))
    }

    // MARK: - Survey Properties

    @Test func `Survey user identifier generates UUID`() {
        let id = userDefaultsStore.surveyUserIdentifier
        #expect(!id.isEmpty)
    }

    @Test func `Survey user identifier persists between calls`() {
        let first = userDefaultsStore.surveyUserIdentifier
        let second = userDefaultsStore.surveyUserIdentifier
        #expect(first == second)
    }

    // MARK: - App Launch Counter

    @Test func `App launch count default value is zero`() {
        #expect(self.userDefaultsStore.appLaunchCount == 0)
    }

    @Test func `App launch count increments correctly`() {
        userDefaultsStore.incrementAppLaunchCount()
        #expect(self.userDefaultsStore.appLaunchCount == 1)

        userDefaultsStore.incrementAppLaunchCount()
        #expect(self.userDefaultsStore.appLaunchCount == 2)
    }

    // MARK: - Survey Enabled

    @Test func `Is survey enabled defaults to true`() {
        #expect(self.userDefaultsStore.isSurveyEnabled)
    }

    @Test func `Is survey enabled persists value`() {
        userDefaultsStore.isSurveyEnabled = false
        #expect(!self.userDefaultsStore.isSurveyEnabled)

        userDefaultsStore.isSurveyEnabled = true
        #expect(self.userDefaultsStore.isSurveyEnabled)
    }

    // MARK: - Next Survey Reminder Date

    @Test func `Next survey reminder date defaults to nil`() {
        #expect(self.userDefaultsStore.nextSurveyReminderDate == nil)
    }

    @Test func `Next survey reminder date persists value`() {
        let date = Date().addingTimeInterval(3600)
        userDefaultsStore.nextSurveyReminderDate = date
        expectClose(self.userDefaultsStore.nextSurveyReminderDate, date, within: 1)
    }

    // MARK: - Survey Completion Tracking

    @Test func `Mark survey completed tracks completed survey`() {
        userDefaultsStore.markSurveyCompleted(surveyId: 1, userIdentifier: "user1")
        #expect(self.userDefaultsStore.isSurveyCompleted(surveyId: 1, userIdentifier: "user1"))
        #expect(!self.userDefaultsStore.isSurveyCompleted(surveyId: 2, userIdentifier: "user1"))
    }

    @Test func `Mark survey for later tracks later survey`() {
        userDefaultsStore.markSurveyForLater(surveyId: 1, userIdentifier: "user1")
        // Immediately after marking, shouldShowSurveyLater returns false (0 launches since marking)
        #expect(!self.userDefaultsStore.shouldShowSurveyLater(surveyId: 1, userIdentifier: "user1"))
    }

    // MARK: - Walking Speed

    @Test func `Walking speed default value`() {
        expectClose(self.userDefaultsStore.walkingSpeedMetersPerSecond, 1.4)
    }

    @Test func `Walking speed round trip`() {
        userDefaultsStore.walkingSpeedMetersPerSecond = 0.9
        expectClose(self.userDefaultsStore.walkingSpeedMetersPerSecond, 0.9)

        userDefaultsStore.walkingSpeedMetersPerSecond = 1.8
        expectClose(self.userDefaultsStore.walkingSpeedMetersPerSecond, 1.8)

        let newStore = UserDefaultsStore(userDefaults: userDefaults)
        expectClose(newStore.walkingSpeedMetersPerSecond, 1.8)
    }

    @Test func `Walking speed source default value`() {
        #expect(self.userDefaultsStore.walkingSpeedSource == .manual)
    }

    @Test func `Walking speed source round trip`() {
        userDefaultsStore.walkingSpeedSource = .healthKit
        #expect(self.userDefaultsStore.walkingSpeedSource == .healthKit)

        userDefaultsStore.walkingSpeedSource = .manual
        #expect(self.userDefaultsStore.walkingSpeedSource == .manual)
    }

    @Test func `Walking speed meters per second clamps below range`() {
        userDefaultsStore.walkingSpeedMetersPerSecond = 0.1
        expectClose(self.userDefaultsStore.walkingSpeedMetersPerSecond, WalkingSpeed.validRange.lowerBound)
    }

    @Test func `Walking speed meters per second clamps above range`() {
        userDefaultsStore.walkingSpeedMetersPerSecond = 10.0
        expectClose(self.userDefaultsStore.walkingSpeedMetersPerSecond, WalkingSpeed.validRange.upperBound)
    }

    // MARK: - Default Alarm Lead Time

    @Test func `Default alarm lead time is 10 minutes`() {
        #expect(self.userDefaultsStore.defaultAlarmLeadTimeMinutes == 10)
    }

    @Test func `Default alarm lead time ignores and clears legacy stored value`() {
        userDefaults.set(2, forKey: "UserDataStore.defaultAlarmLeadTimeMinutes")

        let newStore = UserDefaultsStore(userDefaults: userDefaults)

        #expect(newStore.defaultAlarmLeadTimeMinutes == 10)
        #expect(self.userDefaults.object(forKey: "UserDataStore.defaultAlarmLeadTimeMinutes") == nil)
    }

}
