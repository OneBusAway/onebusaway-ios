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

class UserDefaultsStoreTests: OBATestCase {

    var userDefaults: UserDefaults!
    var userDefaultsStore: UserDefaultsStore!

    override func setUp() {
        super.setUp()
        userDefaults = UserDefaults(suiteName: String(describing: self))
        userDefaultsStore = UserDefaultsStore(userDefaults: userDefaults)
    }

    func test_recentStops_addStop() {
        let stops = loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_uniqueStops() {
        let stops = loadSomeStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop)
        userDefaultsStore.addRecentStop(stop)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_maxCount() {
        let stops = loadSomeStops()
        expect(stops.count).to(beGreaterThan(userDefaultsStore.maximumRecentStopsCount))

        for s in stops {
            userDefaultsStore.addRecentStop(s)
            print("Count: \(userDefaultsStore.recentStops.count)")
        }

        expect(self.userDefaultsStore.recentStops.count) == userDefaultsStore.maximumRecentStopsCount
    }
}
