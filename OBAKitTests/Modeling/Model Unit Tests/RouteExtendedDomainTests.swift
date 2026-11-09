//
//  RouteExtendedDomainTests.swift
//  OBAKitTests
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import Foundation
import Testing
import UIKit
@testable import OBAKit
@testable import OBAKitCore

/// Tests for `Route` domain operations: equality, sorting,
/// route type mapping, color fallbacks, and nil agency handling.
@Suite(.serialized)
final class RouteExtendedDomainTests: OBATestCase {

    private func makeRoute(
        id: String,
        shortName: String,
        longName: String = "",
        agencyID: String = "1",
        routeType: Route.RouteType = .bus,
        colorHex: String? = nil,
        textColorHex: String? = nil
    ) throws -> Route {
        var dict: [String: Any] = [
            "id": id,
            "agencyId": agencyID,
            "shortName": shortName,
            "type": routeType.rawValue
        ]
        if !longName.isEmpty {
            dict["longName"] = longName
        }
        if let colorHex {
            dict["color"] = colorHex
        }
        if let textColorHex {
            dict["textColor"] = textColorHex
        }

        return try Fixtures.dictionaryToModel(type: Route.self, dictionary: dict)
    }

    // MARK: - Route Equality and Hashing

    @Test func `Route equality compares all identity fields`() throws {
        let route1 = try makeRoute(id: "1_10", shortName: "10", longName: "Downtown")
        let route2 = try makeRoute(id: "1_10", shortName: "10", longName: "Downtown")
        let renamed = try makeRoute(id: "1_10", shortName: "Ten", longName: "Downtown")
        let route3 = try makeRoute(id: "1_44", shortName: "44")

        #expect(route1 == route2)
        #expect(route1.hash == route2.hash)
        #expect(route1 != renamed)
        #expect(route1 != route3)
    }

    // MARK: - Route Type Exhaustion

    @Test func `RouteType maps known GTFS route types accurately`() throws {
        let lightRail = try makeRoute(id: "r_0", shortName: "1 Line", routeType: .lightRail)
        #expect(lightRail.routeType == .lightRail)

        let subway = try makeRoute(id: "r_1", shortName: "Subway", routeType: .subway)
        #expect(subway.routeType == .subway)

        let rail = try makeRoute(id: "r_2", shortName: "Sounder", routeType: .rail)
        #expect(rail.routeType == .rail)

        let bus = try makeRoute(id: "r_3", shortName: "Bus", routeType: .bus)
        #expect(bus.routeType == .bus)

        let ferry = try makeRoute(id: "r_4", shortName: "WSF", routeType: .ferry)
        #expect(ferry.routeType == .ferry)

        let cableCar = try makeRoute(id: "r_5", shortName: "Cable", routeType: .cableCar)
        #expect(cableCar.routeType == .cableCar)

        let gondola = try makeRoute(id: "r_6", shortName: "Gondola", routeType: .gondola)
        #expect(gondola.routeType == .gondola)

        let funicular = try makeRoute(id: "r_7", shortName: "Funicular", routeType: .funicular)
        #expect(funicular.routeType == .funicular)
    }

    // MARK: - Color Parsing and Contrast Fallback

    @Test func `Route parses six-character hex colors into UIColor`() throws {
        let route = try makeRoute(id: "colored_route", shortName: "550", colorHex: "0055AA", textColorHex: "FFFFFF")
        #expect(route.color != nil)
        #expect(route.textColor != nil)
    }

    @Test func `Route with nil color properties returns nil UIColors`() throws {
        let route = try makeRoute(id: "uncolored_route", shortName: "40")
        #expect(route.color == nil)
        #expect(route.textColor == nil)
    }

    // MARK: - Display Name and Fallback

    @Test func `Route uses shortName or longName appropriately`() throws {
        let withBoth = try makeRoute(id: "r_both", shortName: "44", longName: "Ballard - Montlake")
        #expect(withBoth.shortName == "44")
        #expect(withBoth.longName == "Ballard - Montlake")

        let shortOnly = try makeRoute(id: "r_short", shortName: "RapidRide E")
        #expect(shortOnly.shortName == "RapidRide E")
        #expect(shortOnly.longName == nil)
    }
}
