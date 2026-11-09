//
//  StopPreferencesDomainTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
@testable import OBAKit
@testable import OBAKitCore

/// Tests repeated route toggling, multiple hide/unhide sequences,
/// sort type switching, decoding failures for missing keys, and
/// `ArrivalDepartureFilter` Codable round trips.
@Suite(.serialized)
final class StopPreferencesDomainTests {

    // MARK: - Multiple Toggles and State Transitions

    @Test func `Toggle route repeatedly alternates hidden state`() {
        var prefs = StopPreferences()
        let routeID = "metro_44"

        #expect(!prefs.isRouteIDHidden(routeID))
        #expect(!prefs.hasHiddenRoutes)

        prefs.toggleRouteIDHidden(routeID)
        #expect(prefs.isRouteIDHidden(routeID))
        #expect(prefs.hasHiddenRoutes)
        #expect(prefs.hiddenRoutes == [routeID])

        prefs.toggleRouteIDHidden(routeID)
        #expect(!prefs.isRouteIDHidden(routeID))
        #expect(!prefs.hasHiddenRoutes)
        #expect(prefs.hiddenRoutes.isEmpty)

        prefs.toggleRouteIDHidden(routeID)
        #expect(prefs.isRouteIDHidden(routeID))
        #expect(prefs.hasHiddenRoutes)
    }

    @Test func `Multiple different routes can be hidden independently`() {
        var prefs = StopPreferences()
        let routes = ["1_10", "1_49", "1_70", "40_550"]

        for route in routes {
            prefs.toggleRouteIDHidden(route)
        }

        #expect(prefs.hasHiddenRoutes)
        #expect(prefs.hiddenRoutes.count == 4)

        for route in routes {
            #expect(prefs.isRouteIDHidden(route))
        }

        // Unhide middle route
        prefs.toggleRouteIDHidden("1_49")
        #expect(!prefs.isRouteIDHidden("1_49"))
        #expect(prefs.isRouteIDHidden("1_10"))
        #expect(prefs.isRouteIDHidden("1_70"))
        #expect(prefs.isRouteIDHidden("40_550"))
        #expect(prefs.hiddenRoutes.count == 3)
    }

    // MARK: - Sort Type Switching

    @Test func `StopPreferences sort type can be switched between time and route`() {
        var prefs = StopPreferences(sortType: .time, hiddenRoutes: [])
        #expect(prefs.sortType == .time)

        prefs.sortType = .route
        #expect(prefs.sortType == .route)

        prefs.sortType = .time
        #expect(prefs.sortType == .time)
    }

    // MARK: - Codable Edge Cases and Defaults

    @Test func `Decoding StopPreferences from empty JSON dictionary throws`() {
        let emptyJSON = "{}".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(StopPreferences.self, from: emptyJSON)
        }
    }

    @Test func `Decoding StopPreferences with only sortType throws`() {
        let json = "{\"sortType\":\"route\"}".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(StopPreferences.self, from: json)
        }
    }

    @Test func `Decoding StopPreferences with only hiddenRoutes throws`() {
        let json = "{\"hiddenRoutes\":[\"route_A\",\"route_B\"]}".data(using: .utf8)!
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(StopPreferences.self, from: json)
        }
    }

    // MARK: - Equality Property Check

    @Test func `StopPreferences property comparisons evaluate sortType and hiddenRoutes`() {
        let base = StopPreferences(sortType: .time, hiddenRoutes: ["1_10"])
        let identical = StopPreferences(sortType: .time, hiddenRoutes: ["1_10"])
        let differentSort = StopPreferences(sortType: .route, hiddenRoutes: ["1_10"])
        let differentRoutes = StopPreferences(sortType: .time, hiddenRoutes: ["1_20"])
        let emptyRoutes = StopPreferences(sortType: .time, hiddenRoutes: [])

        #expect(base.sortType == identical.sortType && base.hiddenRoutes == identical.hiddenRoutes)
        #expect(!(base.sortType == differentSort.sortType && base.hiddenRoutes == differentSort.hiddenRoutes))
        #expect(!(base.sortType == differentRoutes.sortType && base.hiddenRoutes == differentRoutes.hiddenRoutes))
        #expect(!(base.sortType == emptyRoutes.sortType && base.hiddenRoutes == emptyRoutes.hiddenRoutes))
    }

    // MARK: - ArrivalDepartureFilter

    @Test func `ArrivalDepartureFilter codable round-trip`() throws {
        let filters: [ArrivalDepartureFilter] = [.all, .estimatedOnly, .scheduledOnly]

        for filter in filters {
            let data = try JSONEncoder().encode(filter)
            let decoded = try JSONDecoder().decode(ArrivalDepartureFilter.self, from: data)
            #expect(decoded == filter)
        }
    }
}
