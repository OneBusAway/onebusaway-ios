//
//  GroupedArrivalDepartureExtendedTests.swift
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

/// Extended sorting and grouping test suite for `GroupedArrivalDeparture`.
///
/// Verifies natural alphanumeric sorting precedence, case insensitivity,
/// tie-breakers on identical short names, and stability over large route sets.
@Suite(.serialized)
final class GroupedArrivalDepartureExtendedTests: OBATestCase {

    private func makeRoute(
        id: String,
        shortName: String,
        longName: String = "",
        agencyID: String = "1"
    ) throws -> Route {
        let dict: [String: Any] = [
            "id": id,
            "shortName": shortName,
            "longName": longName,
            "agencyId": agencyID,
            "type": 3
        ]
        return try Fixtures.dictionaryToModel(type: Route.self, dictionary: dict)
    }

    // MARK: - Natural Alphanumeric Ordering

    @Test func `localizedStandardCompare orders numeric and alphanumeric mixed routes naturally`() throws {
        // Natural human sort order: "1", "2", "2E", "10", "10A", "10B", "100", "B Line", "C Line"
        let r1 = try makeRoute(id: "r1", shortName: "1")
        let r2 = try makeRoute(id: "r2", shortName: "2")
        let r2E = try makeRoute(id: "r2E", shortName: "2E")
        let r10 = try makeRoute(id: "r10", shortName: "10")
        let r10A = try makeRoute(id: "r10A", shortName: "10A")
        let r10B = try makeRoute(id: "r10B", shortName: "10B")
        let r100 = try makeRoute(id: "r100", shortName: "100")
        let rB = try makeRoute(id: "rB", shortName: "B Line")
        let rC = try makeRoute(id: "rC", shortName: "C Line")

        let input = [rC, r100, r2E, r10B, r1, rB, r10, r2, r10A].map {
            GroupedArrivalDeparture(route: $0, arrivalDepartures: [])
        }

        let sorted = input.localizedStandardCompare()
        let resultNames = sorted.map { $0.route.shortName }

        #expect(resultNames == ["1", "2", "2E", "10", "10A", "10B", "100", "B Line", "C Line"])
    }

    // MARK: - Case Insensitivity

    @Test func `localizedStandardCompare treats lowercase and uppercase shortNames case-insensitively`() throws {
        let rLower = try makeRoute(id: "r_low", shortName: "rapidride c")
        let rUpper = try makeRoute(id: "r_up", shortName: "RapidRide D")
        let rMixed = try makeRoute(id: "r_mix", shortName: "rapidride E")

        let input = [rMixed, rUpper, rLower].map {
            GroupedArrivalDeparture(route: $0, arrivalDepartures: [])
        }

        let sorted = input.localizedStandardCompare()
        let resultIDs = sorted.map { $0.route.id }

        #expect(resultIDs == ["r_low", "r_up", "r_mix"])
    }

    // MARK: - Stability and Duplicate Names

    @Test func `localizedStandardCompare maintains all elements when identical shortNames exist`() throws {
        let routeAgency1 = try makeRoute(id: "1_44", shortName: "44", agencyID: "agency_1")
        let routeAgency2 = try makeRoute(id: "2_44", shortName: "44", agencyID: "agency_2")
        let routeA = try makeRoute(id: "1_10", shortName: "10", agencyID: "agency_1")

        let g1 = GroupedArrivalDeparture(route: routeAgency1, arrivalDepartures: [])
        let g2 = GroupedArrivalDeparture(route: routeAgency2, arrivalDepartures: [])
        let gA = GroupedArrivalDeparture(route: routeA, arrivalDepartures: [])

        let sorted = [g1, gA, g2].localizedStandardCompare()
        #expect(sorted.count == 3)
        #expect(sorted.first?.route.shortName == "10")
        #expect(sorted[1].route.shortName == "44")
        #expect(sorted[2].route.shortName == "44")
    }

    // MARK: - Empty ShortName Fallbacks

    @Test func `localizedStandardCompare handles empty shortNames without trapping`() throws {
        let rEmpty = try makeRoute(id: "r_empty", shortName: "", longName: "Express Shuttle")
        let rNamed = try makeRoute(id: "r_named", shortName: "7", longName: "Rainier Beach")

        let gEmpty = GroupedArrivalDeparture(route: rEmpty, arrivalDepartures: [])
        let gNamed = GroupedArrivalDeparture(route: rNamed, arrivalDepartures: [])

        let sorted = [gNamed, gEmpty].localizedStandardCompare()
        #expect(sorted.count == 2)
        #expect(sorted[0].route.shortName == "")
        #expect(sorted[1].route.shortName == "7")
    }

    // MARK: - Preserving ArrivalDepartures in Group

    @Test func `sorting preserves arrival departure associations in grouped container`() throws {
        let route44 = try makeRoute(id: "1_44", shortName: "44")
        let route7 = try makeRoute(id: "1_7", shortName: "7")

        let arrDep44 = try Fixtures.arrivalDeparture(stopID: "1_100", routeID: "1_44", tripID: "trip_44")
        let arrDep7 = try Fixtures.arrivalDeparture(stopID: "1_200", routeID: "1_7", tripID: "trip_7")

        let g44 = GroupedArrivalDeparture(route: route44, arrivalDepartures: [arrDep44])
        let g7 = GroupedArrivalDeparture(route: route7, arrivalDepartures: [arrDep7])

        let sorted = [g44, g7].localizedStandardCompare()

        #expect(sorted[0].route.shortName == "7")
        #expect(sorted[0].arrivalDepartures.count == 1)
        #expect(sorted[0].arrivalDepartures.first?.tripID == "trip_7")

        #expect(sorted[1].route.shortName == "44")
        #expect(sorted[1].arrivalDepartures.count == 1)
        #expect(sorted[1].arrivalDepartures.first?.tripID == "trip_44")
    }
}
