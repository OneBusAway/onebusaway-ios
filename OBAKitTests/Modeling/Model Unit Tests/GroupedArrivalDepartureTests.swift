//
//  GroupedArrivalDepartureTests.swift
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
final class GroupedArrivalDepartureTests {

    private func makeRoute(id: String, shortName: String, longName: String = "") throws -> Route {
        let dict: [String: Any] = [
            "id": id,
            "shortName": shortName,
            "longName": longName,
            "agencyId": "1",
            "type": 3
        ]
        return try Fixtures.dictionaryToModel(type: Route.self, dictionary: dict)
    }

    @Test func `Initialize GroupedArrivalDeparture container`() throws {
        let route = try makeRoute(id: "1_10", shortName: "10")
        let arrDep1 = try Fixtures.arrivalDeparture(stopID: "1_100", routeID: "1_10", tripID: "1_trip_1")
        let arrDep2 = try Fixtures.arrivalDeparture(stopID: "1_100", routeID: "1_10", tripID: "1_trip_2")

        let grouped = GroupedArrivalDeparture(route: route, arrivalDepartures: [arrDep1, arrDep2])

        #expect(grouped.route.id == "1_10")
        #expect(grouped.route.shortName == "10")
        #expect(grouped.arrivalDepartures.count == 2)
        #expect(grouped.arrivalDepartures[0].tripID == "1_trip_1")
        #expect(grouped.arrivalDepartures[1].tripID == "1_trip_2")
    }

    @Test func `localizedStandardCompare sorts by route shortName natural numeric order`() throws {
        // Natural string comparison should order: "2", "10", "44", "100", "B Line"
        let route100 = try makeRoute(id: "1_100", shortName: "100")
        let route2 = try makeRoute(id: "1_2", shortName: "2")
        let route10 = try makeRoute(id: "1_10", shortName: "10")
        let route44 = try makeRoute(id: "1_44", shortName: "44")
        let routeB = try makeRoute(id: "1_B", shortName: "B Line")

        let g100 = GroupedArrivalDeparture(route: route100, arrivalDepartures: [])
        let g2 = GroupedArrivalDeparture(route: route2, arrivalDepartures: [])
        let g10 = GroupedArrivalDeparture(route: route10, arrivalDepartures: [])
        let g44 = GroupedArrivalDeparture(route: route44, arrivalDepartures: [])
        let gB = GroupedArrivalDeparture(route: routeB, arrivalDepartures: [])

        let unsorted = [g100, gB, g44, g10, g2]
        let sorted = unsorted.localizedStandardCompare()

        let sortedShortNames = sorted.map { $0.route.shortName }
        #expect(sortedShortNames == ["2", "10", "44", "100", "B Line"])
    }

    @Test func `localizedStandardCompare on empty array returns empty`() {
        let empty: [GroupedArrivalDeparture] = []
        #expect(empty.localizedStandardCompare().isEmpty)
    }

    @Test func `localizedStandardCompare on single element returns identical element`() throws {
        let route = try makeRoute(id: "1_1", shortName: "1")
        let single = [GroupedArrivalDeparture(route: route, arrivalDepartures: [])]
        let sorted = single.localizedStandardCompare()

        #expect(sorted.count == 1)
        #expect(sorted[0].route.shortName == "1")
    }
}
