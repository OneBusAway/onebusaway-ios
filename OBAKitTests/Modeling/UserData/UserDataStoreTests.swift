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

    // MARK: - Selected Tab Index

    func test_selectedTabIndex_mapSelectedByDefault() {
        expect(self.userDefaultsStore.lastSelectedView) == .map
    }

    func test_selectedTabIndex_changingDefaults() {
        userDefaultsStore.lastSelectedView = .bookmarks
        expect(self.userDefaultsStore.lastSelectedView) == .bookmarks
    }
}
