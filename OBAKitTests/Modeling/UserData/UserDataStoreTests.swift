//
//  UserDataStoreTests.swift
//  OBAKitTests
//
//  Created by Aaron Brethorst on 5/20/19.
//

import XCTest
import Nimble
import OHHTTPStubs
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
        region = try! loadSomeRegions()[1]
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
        let stops = try! loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_uniqueStops() {
        let stops = try! loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)
        userDefaultsStore.addRecentStop(stop, region: region)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_maxCount() {
        let stops = try! loadSomeStops()
        expect(stops.count).to(beGreaterThan(userDefaultsStore.maximumRecentStopsCount))

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        expect(self.userDefaultsStore.recentStops.count) == userDefaultsStore.maximumRecentStopsCount
    }

    func test_recentStops_search() {
        let stops = try! loadSomeStops()

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
        let stops = try! loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop, region: region)

        userDefaultsStore.deleteAllRecentStops()

        expect(self.userDefaultsStore.recentStops.count) == 0
    }

    func test_recentStops_removeStop() {
        let stops = try! loadSomeStops().prefix(20)
        let stop = stops.first!

        for s in stops {
            userDefaultsStore.addRecentStop(s, region: region)
        }

        userDefaultsStore.delete(recentStop: stop)

        expect(self.userDefaultsStore.recentStops.count) == (stops.count - 1)
    }

    // MARK: - Alarms

    func test_alarms_deleteMissingTripDate() {
        let missingDataAlarm = try! loadAlarm(id: "1")

        let futureAlarm = try! loadAlarm(id: "2")
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
        let expiredAlarm = try! loadAlarm(id: "1")
        expiredAlarm.set(tripDate: Date(timeIntervalSinceReferenceDate: 0), alarmOffset: 5)

        let futureAlarm = try! loadAlarm(id: "2")
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
        expect(self.userDefaultsStore.lastSelectedView) == .map
    }

    func test_selectedTabIndex_changingDefaults() {
        userDefaultsStore.lastSelectedView = .bookmarks
        expect(self.userDefaultsStore.lastSelectedView) == .bookmarks
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
}
