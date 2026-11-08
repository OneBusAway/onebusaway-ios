//
//  StopPreferencesTests.swift
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

@Suite(.serialized)
final class StopPreferencesTests: OBATestCase {

    // MARK: - Default Initialization

    @Test func `Default initialization sets time sort and empty hidden routes`() {
        let prefs = StopPreferences()
        #expect(prefs.sortType == .time)
        #expect(prefs.hiddenRoutes.isEmpty)
        #expect(prefs.hasHiddenRoutes == false)
    }

    // MARK: - Custom Initialization

    @Test func `Custom initialization preserves sort and hidden routes`() {
        let prefs = StopPreferences(sortType: .route, hiddenRoutes: ["1_100", "1_200"])
        #expect(prefs.sortType == .route)
        #expect(prefs.hiddenRoutes == ["1_100", "1_200"])
        #expect(prefs.hasHiddenRoutes == true)
        #expect(prefs.isRouteIDHidden("1_100") == true)
        #expect(prefs.isRouteIDHidden("1_300") == false)
    }

    // MARK: - Route Visibility Toggling

    @Test func `Toggle route hidden adds and removes route correctly`() {
        var prefs = StopPreferences()

        // Toggle to hide
        prefs.toggleRouteIDHidden("1_44")
        #expect(prefs.isRouteIDHidden("1_44") == true)
        #expect(prefs.hasHiddenRoutes == true)
        #expect(prefs.hiddenRoutes == ["1_44"])

        // Toggle again to unhide
        prefs.toggleRouteIDHidden("1_44")
        #expect(prefs.isRouteIDHidden("1_44") == false)
        #expect(prefs.hasHiddenRoutes == false)
        #expect(prefs.hiddenRoutes.isEmpty)
    }

    // MARK: - Codable Round-Trip

    @Test func `StopPreferences JSON encoding and decoding`() throws {
        let original = StopPreferences(sortType: .route, hiddenRoutes: ["1_70", "1_49"])
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(StopPreferences.self, from: data)

        #expect(decoded.sortType == original.sortType)
        #expect(decoded.hiddenRoutes == original.hiddenRoutes)
        #expect(decoded.hasHiddenRoutes == true)
    }

    // MARK: - Enums Codable and Case Values

    @Test func `StopSort enum string representation`() {
        #expect(StopSort.time.rawValue == "time")
        #expect(StopSort.route.rawValue == "route")
    }

    @Test func `ArrivalDepartureFilter enum cases and raw values`() {
        #expect(ArrivalDepartureFilter.allCases.count == 3)
        #expect(ArrivalDepartureFilter.all.rawValue == "all")
        #expect(ArrivalDepartureFilter.estimatedOnly.rawValue == "estimatedOnly")
        #expect(ArrivalDepartureFilter.scheduledOnly.rawValue == "scheduledOnly")
    }
}
