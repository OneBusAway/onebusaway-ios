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

    var userDefaults: UserDefaults!
    var userDefaultsStore: UserDefaultsStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: String(describing: self))
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
    }

    // MARK: - Recent Stops

    func test_recentStops_addStop() {
        let stops = try! loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_uniqueStops() {
        let stops = try! loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop)
        userDefaultsStore.addRecentStop(stop)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_maxCount() {
        let stops = try! loadSomeStops()
        expect(stops.count).to(beGreaterThan(userDefaultsStore.maximumRecentStopsCount))

        for s in stops {
            userDefaultsStore.addRecentStop(s)
        }

        expect(self.userDefaultsStore.recentStops.count) == userDefaultsStore.maximumRecentStopsCount
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
