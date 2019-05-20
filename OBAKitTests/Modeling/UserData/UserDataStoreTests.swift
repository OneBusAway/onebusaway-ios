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

    func loadStops() -> [Stop] {
        let json = loadJSONDictionary(file: "stops_for_location_seattle.json")
        let stops = try! decodeModels(type: Stop.self, json: json)

        return stops
    }

    func test_recentStops_addStop() {
        let stops = loadStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_uniqueStops() {
        let stops = loadStops()
        let stop = stops.first!
        userDefaultsStore.addRecentStop(stop)
        userDefaultsStore.addRecentStop(stop)

        expect(self.userDefaultsStore.recentStops) == [stop]
    }

    func test_recentStops_maxCount() {
        let stops = loadStops()
        expect(stops.count).to(beGreaterThan(userDefaultsStore.maximumRecentStopsCount))

        for s in stops {
            userDefaultsStore.addRecentStop(s)
            print("Count: \(userDefaultsStore.recentStops.count)")
        }

        expect(self.userDefaultsStore.recentStops.count) == userDefaultsStore.maximumRecentStopsCount
    }
}
